import SwiftUI
import MapKit

private enum MapSheet: Identifiable {
    case add
    case detail(Place)
    var id: String {
        switch self { case .add: "add"; case .detail(let place): place.id.uuidString }
    }
}

struct PlacesView: View {
    @Environment(JournalStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var camera: MapCameraPosition = .automatic
    @State private var sheet: MapSheet?
    @State private var focusedID: UUID?
    @State private var satellite = false
    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(store.visiblePlaces) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    Button { select(place) } label: {
                        Image(systemName: place.kind.symbol).font(.body.weight(.medium))
                            .foregroundStyle(focusedID == place.id ? Theme.accent : Theme.ink)
                            .frame(width: 44, height: 44).background(Theme.surface, in: Circle())
                            .overlay(Circle().stroke(focusedID == place.id ? Theme.accent : Theme.quiet.opacity(0.25), lineWidth: 1))
                            .scaleEffect(focusedID == place.id && !reduceMotion ? 1.08 : 1)
                    }.buttonStyle(PressStyle()).accessibilityLabel("查看\(place.name)")
                }
                if focusedID == place.id {
                    MapCircle(center: place.coordinate, radius: place.radius).foregroundStyle(Theme.accent.opacity(0.1))
                }
            }
        }
        .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .navigationTitle("地点").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sheet = .add } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("添加地点")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 0) {
                    Button { satellite.toggle() } label: { Image(systemName: "square.3.layers.3d").frame(width: 48, height: 48) }.accessibilityLabel("切换地图样式").accessibilityValue(satellite ? "卫星地图" : "标准地图")
                    Divider().frame(height: 20)
                    Button {
                        location.locateOnce()
                        withAnimation(reduceMotion ? nil : Motion.expand) { camera = .userLocation(fallback: .automatic) }
                    } label: { Image(systemName: "location").frame(width: 48, height: 48) }.accessibilityLabel("定位到我")
                }.background(.regularMaterial, in: Capsule()).padding(.horizontal, 20)
                if store.visiblePlaces.isEmpty {
                    Button("添加第一个地点", systemImage: "plus") { sheet = .add }
                        .buttonStyle(PrimaryButtonStyle()).controlSize(.large).padding(20)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(store.visiblePlaces) { place in
                                Button { select(place) } label: {
                                    Label(place.name, systemImage: place.kind.symbol).font(.subheadline.weight(.medium))
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                        .frame(maxWidth: 220, alignment: .leading)
                                        .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
                                        .foregroundStyle(focusedID == place.id ? Theme.accent : Theme.ink)
                                        .background(focusedID == place.id ? Theme.highlight : Theme.surface, in: Capsule())
                                }.buttonStyle(PressStyle())
                                    .accessibilityLabel("查看\(place.name)")
                                    .accessibilityAddTraits(focusedID == place.id ? .isSelected : [])
                            }
                        }.padding(.horizontal, 20).padding(.vertical, 12)
                    }.scrollIndicators(.hidden).background(.regularMaterial)
                }
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .add: PlaceEditor()
            case .detail(let place):
                NavigationStack {
                    PlaceDetailView(place: place).toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } }
                    }
                }.presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large]).presentationDragIndicator(.visible)
            }
        }
    }
    private func select(_ place: Place) {
        withAnimation(reduceMotion ? nil : Motion.expand) {
            focusedID = place.id
            camera = .region(.init(center: place.coordinate, latitudinalMeters: 1800, longitudinalMeters: 1800))
        }
        sheet = .detail(place)
    }
}

struct PlaceEditor: View {
    @Environment(JournalStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    let existing: Place?
    @State private var name: String
    @State private var kind: PlaceKind
    @State private var radius: Double
    @State private var address: String
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var awaitingLocation = false
    init(existing: Place? = nil) {
        self.existing = existing
        // Intentional one-time editing draft. The model is changed only on Save.
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind ?? .home)
        _radius = State(initialValue: existing?.radius ?? 150)
        _address = State(initialValue: existing?.address ?? "")
        _coordinate = State(initialValue: existing?.coordinate)
        _camera = State(initialValue: existing.map { .region(.init(center: $0.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)) } ?? .automatic)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("地点信息") {
                    TextField("名称，例如：家", text: $name)
                    Picker("类型", selection: $kind) { ForEach(PlaceKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                }
                Section {
                    HStack {
                        TextField("搜索地址或地点", text: $query).submitLabel(.search).onSubmit(search)
                        Button(action: search) { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                            .accessibilityLabel("搜索地点").disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                    }
                    if searching { ProgressView("正在搜索") }
                    if let searchError { Text(searchError).foregroundStyle(.red).font(.footnote) }
                    ForEach(results, id: \.self) { item in
                        Button {
                            choose(item.placemark.coordinate)
                            address = item.placemark.title ?? ""
                            if name.isEmpty { name = item.name ?? "" }
                            results = []
                        } label: {
                            VStack(alignment: .leading) { Text(item.name ?? "地点"); Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    MapReader { proxy in
                        Map(position: $camera) {
                            if let coordinate {
                                Marker(name.isEmpty ? "选定位置" : name, coordinate: coordinate)
                                MapCircle(center: coordinate, radius: radius).foregroundStyle(Theme.accent.opacity(0.15))
                            }
                        }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 16))
                            .onTapGesture { point in if let value = proxy.convert(point, from: .local) { choose(value); address = "地图选点" } }
                    }
                    Button("使用当前位置", systemImage: "location") {
                        if let value = location.coordinate { choose(value); address = "当前位置" }
                        else { awaitingLocation = true; location.locateOnce() }
                    }.frame(minHeight: 44)
                    if let coordinate { Text("\(coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(5))))").font(.caption).foregroundStyle(.secondary) }
                    if !address.isEmpty { Text(address).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("位置") } footer: { Text("搜索选择或轻点地图。地址搜索和地图底图由 Apple 地图提供，需要网络。") }
                Section {
                    Slider(value: $radius, in: 100...1000, step: 50) { Text("识别半径") }
                    Text("识别半径 · \(Int(radius)) 米")
                } footer: { Text("建议 150–300 米。相邻地点应避免范围重叠，定位可能存在延迟。最多同时自动监测 20 个地点，其余地点可手动记录。") }
                if let error = store.errorMessage { Section { Text(error).foregroundStyle(.red) } }
                if let error = location.statusMessage { Section { Text(error).font(.footnote).foregroundStyle(.secondary) } }
            }
            .navigationTitle(existing == nil ? "新的地点" : "编辑地点").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let coordinate else { return }
                        if store.savePlace(existing: existing, name: name, kind: kind, latitude: coordinate.latitude, longitude: coordinate.longitude, radius: radius, address: address) {
                            location.refreshRegions(); dismiss()
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinate == nil)
                }
            }
            .onDisappear { searchTask?.cancel() }
            .onChange(of: location.coordinate?.latitude) { _, _ in
                if awaitingLocation, let value = location.coordinate {
                    choose(value); address = "当前位置"; awaitingLocation = false
                }
            }
        }
    }
    private func choose(_ value: CLLocationCoordinate2D) {
        coordinate = value
        camera = .region(.init(center: value, latitudinalMeters: max(radius * 4, 1200), longitudinalMeters: max(radius * 4, 1200)))
    }
    private func search() {
        searchTask?.cancel(); searching = true; searchError = nil
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
        searchTask = Task { @MainActor in
            defer { searching = false }
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = Array(response.mapItems.prefix(6))
                if results.isEmpty { searchError = "没有找到匹配地点，可直接在地图选点。" }
            } catch { if !Task.isCancelled { searchError = "搜索失败，请检查网络或直接在地图选点。" } }
        }
    }
}

struct PlaceDetailView: View {
    @Environment(JournalStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    let place: Place
    @State private var edit = false
    @State private var archive = false
    private var visits: [JournalEntry] { store.entries.filter { $0.kind == .stay && $0.placeID == place.id } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 14) {
                    PlaceBadge(kind: place.kind)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.kind.title).font(.headline)
                        if !place.address.isEmpty { Text(place.address).font(.subheadline).foregroundStyle(Theme.quiet) }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { primaryMetrics }
                    VStack(alignment: .leading, spacing: 20) { primaryMetrics }
                }
                if !place.archived {
                    Button(store.active?.placeID == place.id && store.active?.kind == .stay ? "正在这里记录" : "我现在在这里", systemImage: "record.circle") {
                        store.arrive(place, source: .manual)
                    }.buttonStyle(PrimaryButtonStyle()).controlSize(.large)
                        .disabled(store.active?.placeID == place.id && store.active?.kind == .stay)
                }
                Map { Marker(place.name, systemImage: place.kind.symbol, coordinate: place.coordinate).tint(Theme.accent) }
                    .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("第一次到访", value: visits.last?.start.formatted(date: .abbreviated, time: .omitted) ?? "尚未到访")
                    LabeledContent("最近到访", value: visits.first?.start.formatted(date: .abbreviated, time: .omitted) ?? "尚未到访")
                }.font(.subheadline).foregroundStyle(Theme.quiet)
                Text("最近停留").font(.headline)
                ForEach(Array(visits.prefix(30))) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.start.formatted(date: .abbreviated, time: .shortened)).font(.body.weight(.medium))
                        Text(TimeMath.duration(max(0, (entry.end ?? .now).timeIntervalSince(entry.start)))).font(.subheadline).foregroundStyle(Theme.quiet)
                        if !entry.note.isEmpty { Text(entry.note).font(.subheadline).foregroundStyle(Theme.quiet) }
                        Divider().opacity(0.5).padding(.top, 8)
                    }
                }
                if visits.isEmpty { EmptyCard(title: "从第一次到访开始", message: "每一段停留，都会留在这里。", symbol: "clock") }
            }.padding(24).frame(maxWidth: 680)
        }.frame(maxWidth: .infinity).pageCanvas().navigationTitle(place.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !place.archived {
                    Menu {
                        Button("编辑地点") { edit = true }
                        Button("归档地点", role: .destructive) { archive = true }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("地点操作")
                }
            }
            .sheet(isPresented: $edit) { PlaceEditor(existing: place) }
            .confirmationDialog("归档后停止监测，历史记录仍会保留。", isPresented: $archive, titleVisibility: .visible) {
                Button("归档地点", role: .destructive) { store.archive(place); location.refreshRegions(); dismiss() }
            }
    }
    @ViewBuilder private var primaryMetrics: some View {
        Metric(title: "累计停留", value: TimeMath.duration(visits.reduce(0) { $0 + max(0, ($1.end ?? .now).timeIntervalSince($1.start)) }))
        Metric(title: "到访次数", value: "\(visits.count) 次")
    }
}
