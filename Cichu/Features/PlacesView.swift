import SwiftUI
import MapKit

struct PlacesView: View {
    @Environment(JournalStore.self) private var store
    @Environment(LocationService.self) private var location
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: Place?
    @State private var adding = false
    @State private var satellite = false
    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(store.visiblePlaces) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    Button { selected = place } label: {
                        PlaceBadge(kind: place.kind).padding(5).background(Theme.surface, in: Circle())
                            .overlay(Circle().stroke(Theme.color(place.kind).opacity(0.35), lineWidth: 2))
                    }.accessibilityLabel("查看\(place.name)")
                }
                MapCircle(center: place.coordinate, radius: place.radius).foregroundStyle(Theme.color(place.kind).opacity(0.1))
            }
        }
        .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .safeAreaInset(edge: .top) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我的地点").font(.largeTitle.bold())
                    Text("生活发生的地方").font(.subheadline).foregroundStyle(.secondary)
                }.padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                Spacer()
                Button { adding = true } label: { Image(systemName: "plus").font(.title2).frame(width: 52, height: 52).background(.regularMaterial, in: Circle()) }
                    .accessibilityLabel("添加地点")
            }.padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .trailing, spacing: 12) {
                HStack {
                    Spacer()
                    Button { satellite.toggle() } label: { Image(systemName: "square.3.layers.3d").frame(width: 48, height: 48) }
                        .background(.regularMaterial, in: Circle()).accessibilityLabel("切换地图样式")
                    Button {
                        location.locateOnce()
                        camera = .userLocation(fallback: .automatic)
                    } label: { Image(systemName: "location.fill").frame(width: 48, height: 48) }
                        .background(.regularMaterial, in: Circle()).accessibilityLabel("定位到我")
                }.padding(.horizontal)
                if store.visiblePlaces.isEmpty {
                    Button("在地图上添加第一个地点", systemImage: "plus.circle.fill") { adding = true }
                        .padding(20).frame(maxWidth: .infinity).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).padding()
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(store.visiblePlaces) { place in
                                Button {
                                    camera = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 1800, longitudinalMeters: 1800))
                                    selected = place
                                } label: {
                                    PlaceTile(place: place, duration: store.total(in: TimeMath.day(.now), kind: .stay, placeID: place.id))
                                        .frame(width: 170).background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
                                }.buttonStyle(PressStyle())
                            }
                        }.padding(16)
                    }.scrollIndicators(.hidden).background(.ultraThinMaterial)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $adding) { PlaceEditor() }
        .sheet(item: $selected) { place in NavigationStack { PlaceDetailView(place: place).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { selected = nil } } } } }
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
            VStack(alignment: .leading, spacing: 24) {
                Map { Marker(place.name, systemImage: place.kind.symbol, coordinate: place.coordinate).tint(Theme.color(place.kind)) }
                    .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 28))
                HStack { PlaceBadge(kind: place.kind); PageHeading(eyebrow: "地点记忆", title: place.name) }
                if !place.address.isEmpty { Text(place.address).font(.subheadline).foregroundStyle(.secondary) }
                Card {
                    VStack(spacing: 24) {
                        HStack {
                            Metric(title: "累计停留", value: TimeMath.duration(visits.reduce(0) { $0 + max(0, ($1.end ?? .now).timeIntervalSince($1.start)) }))
                            Metric(title: "到访次数", value: "\(visits.count) 次")
                        }
                        HStack {
                            Metric(title: "第一次到访", value: visits.last?.start.formatted(date: .abbreviated, time: .omitted) ?? "尚未到访")
                            Metric(title: "最近到访", value: visits.first?.start.formatted(date: .abbreviated, time: .omitted) ?? "尚未到访")
                        }
                    }
                }
                if !place.archived {
                    Button("我现在在这里", systemImage: "record.circle") { store.arrive(place, source: .manual) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Text("最近的停留").font(.title2.bold())
                ForEach(Array(visits.prefix(30))) { entry in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.start.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                            Text(TimeMath.duration(max(0, (entry.end ?? .now).timeIntervalSince(entry.start)))).foregroundStyle(.secondary)
                            if !entry.note.isEmpty { Text(entry.note).font(.subheadline) }
                        }
                    }
                }
                if visits.isEmpty { EmptyCard(title: "记忆，从第一次到访开始", message: "在这里度过的时间，会慢慢汇成你的生活。", symbol: "leaf") }
                if !place.archived { Button("归档地点", role: .destructive) { archive = true }.frame(minHeight: 44) }
            }.padding(20).frame(maxWidth: 760)
        }.frame(maxWidth: .infinity).pageCanvas().navigationTitle(place.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { if !place.archived { Button("编辑") { edit = true } } }
            .sheet(isPresented: $edit) { PlaceEditor(existing: place) }
            .confirmationDialog("归档后停止监测，历史记录仍会保留。", isPresented: $archive, titleVisibility: .visible) {
                Button("归档地点", role: .destructive) { store.archive(place); location.refreshRegions(); dismiss() }
            }
    }
}
