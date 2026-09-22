import SwiftUI
import Charts

struct TodayView: View {
    @Environment(JournalStore.self) private var store
    @Environment(LocationService.self) private var location
    @State private var selectedDate = Date.now
    @State private var addEntry = false
    @State private var addPlace = false
    private var interval: DateInterval { TimeMath.day(selectedDate) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "HERE / 此处", title: "时间，有迹可循。")
                HStack {
                    DatePicker("日期", selection: $selectedDate, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden().accessibilityLabel("查看日期")
                    Spacer()
                    if !Calendar.current.isDateInToday(selectedDate) {
                        Button("回到今天") { selectedDate = .now }.frame(minHeight: 44)
                    }
                }
                if Calendar.current.isDateInToday(selectedDate) { CurrentCard() }
                DaySummary(interval: interval)
                HStack {
                    Text("时间留在这里").font(.title2.bold()); Spacer()
                    Button { addPlace = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                        .accessibilityLabel("添加地点")
                }
                if store.visiblePlaces.isEmpty {
                    EmptyCard(title: "从一个熟悉的地方开始", message: "添加家、公司或常去的咖啡店，让每一天的时间有处安放。", symbol: "mappin.circle")
                    Button("添加第一个地点") { addPlace = true }.buttonStyle(.borderedProminent)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(store.visiblePlaces) { place in
                            NavigationLink { PlaceDetailView(place: place) } label: {
                                PlaceTile(place: place, duration: store.total(in: interval, kind: .stay, placeID: place.id))
                            }.buttonStyle(PressStyle())
                        }
                    }
                }
                HStack {
                    Text("这一天").font(.title2.bold()); Spacer()
                    Button("补记", systemImage: "plus") { addEntry = true }.disabled(store.visiblePlaces.isEmpty).frame(minHeight: 44)
                }
                if store.entries(in: interval).isEmpty {
                    EmptyCard(title: "留一点空白，也很好", message: "这一天还没有记录。自动识别的停留和手动补记会出现在这里。", symbol: "clock")
                } else {
                    NavigationLink { DayReplayView(date: selectedDate) } label: {
                        Label("在地图上回看这一天", systemImage: "play.circle.fill").frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered)
                    EntryList(interval: interval)
                }
            }.padding(20).frame(maxWidth: 760)
        }.frame(maxWidth: .infinity).pageCanvas().toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $addPlace) { PlaceEditor() }
            .sheet(isPresented: $addEntry) { EntryEditor(date: selectedDate) }
    }
}

private struct CurrentCard: View {
    @Environment(JournalStore.self) private var store
    @Environment(LocationService.self) private var location
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label(store.active == nil ? "此刻" : "正在记录", systemImage: store.active == nil ? "circle" : "record.circle")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.mint)
                Spacer()
                Image(systemName: store.active?.kind == .travel ? "figure.walk" : (store.place(store.active?.placeID)?.kind.symbol ?? "leaf"))
                    .font(.title2).foregroundStyle(Theme.mint).accessibilityHidden(true)
            }
            if let active = store.active {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.title(active)).font(.largeTitle.bold())
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        Text(TimeMath.duration(timeline.date.timeIntervalSince(active.start)))
                            .font(.system(.largeTitle, design: .rounded).weight(.medium)).monospacedDigit()
                            .foregroundStyle(Theme.mint)
                    }
                    Text("\(active.start.formatted(date: .omitted, time: .shortened)) 开始 · \(active.source == .automatic ? "自动识别" : "手动记录")")
                        .font(.footnote).foregroundStyle(.white.opacity(0.8))
                }
                Button {
                    if location.enabled { location.setEnabled(false) } else { store.stop() }
                } label: {
                    Label("暂停记录", systemImage: "pause.fill").frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.bordered).tint(.white)
            } else {
                Text("慢慢走，\n生活会留下印记。").font(.title.bold())
                Text(location.statusTitle).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                if !store.isDemo {
                    Button(location.enabled ? "刷新当前位置" : "开启自动记录") {
                        if location.enabled { location.locateOnce() } else { location.setEnabled(true) }
                    }.buttonStyle(.bordered).tint(.white).disabled(store.visiblePlaces.isEmpty)
                }
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background {
                ZStack(alignment: .topTrailing) {
                    Theme.hero
                    Circle().stroke(.white.opacity(0.06), lineWidth: 32).frame(width: 190, height: 190).offset(x: 65, y: -45)
                    Circle().stroke(.white.opacity(0.05), lineWidth: 1).frame(width: 280, height: 280).offset(x: 85, y: -90)
                }.clipShape(RoundedRectangle(cornerRadius: 32))
            }
    }
}

struct DaySummary: View {
    @Environment(JournalStore.self) private var store
    let interval: DateInterval
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("一天的轮廓").font(.headline); Spacer(); Image(systemName: "clock").foregroundStyle(Theme.accent) }
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    let entries = store.entries(in: interval, now: timeline.date)
                    Chart(entries) { entry in
                        BarMark(xStart: .value("开始", max(entry.start, interval.start)),
                                xEnd: .value("结束", min(entry.end ?? timeline.date, interval.end)), y: .value("记录", "时间"))
                        .foregroundStyle(entry.kind == .travel ? Color.gray : Theme.color(store.place(entry.placeID)?.kind ?? .other))
                        .cornerRadius(4)
                        .accessibilityLabel(store.title(entry))
                        .accessibilityValue(TimeMath.duration(entry.duration(in: interval, now: timeline.date)))
                    }.chartXScale(domain: interval.start...interval.end).chartYAxis(.hidden)
                        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted))) } }
                        .frame(height: 64)
                    HStack(alignment: .top, spacing: 16) {
                        Metric(title: "地点停留", value: TimeMath.duration(store.total(in: interval, kind: .stay, now: timeline.date)))
                        Metric(title: "移动时间", value: TimeMath.duration(store.total(in: interval, kind: .travel, now: timeline.date)))
                    }
                }
                Text("空白表示没有记录；移动时长由离开与到达时间计算。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct PlaceTile: View {
    let place: Place
    let duration: TimeInterval
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { PlaceBadge(kind: place.kind); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary) }
            Text(place.name).font(.headline).foregroundStyle(Theme.ink)
            Text(TimeMath.duration(duration)).font(.subheadline).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.color(place.kind).opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .combine)
    }
}

struct EntryList: View {
    @Environment(JournalStore.self) private var store
    let interval: DateInterval
    @State private var editing: JournalEntry?
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(store.entries(in: interval)) { entry in
                Button { editing = entry } label: {
                    Card {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: entry.kind == .travel ? "arrow.triangle.turn.up.right.diamond" : (store.place(entry.placeID)?.kind.symbol ?? "mappin"))
                                .foregroundStyle(Theme.accent).frame(width: 28).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.title(entry)).font(.headline)
                                Text("\(max(entry.start, interval.start).formatted(date: .omitted, time: .shortened)) — \(entry.end.map { min($0, interval.end).formatted(date: .omitted, time: .shortened) } ?? "现在")")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(TimeMath.duration(entry.duration(in: interval))) · \(entry.source == .automatic ? "自动识别" : "手动记录")")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !entry.note.isEmpty { Text(entry.note).font(.subheadline).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.buttonStyle(PressStyle()).foregroundStyle(Theme.ink)
            }
        }.sheet(item: $editing) { entry in EntryDetailView(entry: entry) }
    }
}
