import SwiftUI
import Charts

private enum TodaySheet: String, Identifiable {
    case place, entry, share
    var id: String { rawValue }
}

struct TodayView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDate = Date.now
    @State private var sheet: TodaySheet?
    private var interval: DateInterval { TimeMath.day(selectedDate) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack {
                    DatePicker("查看日期", selection: $selectedDate, in: ...Date.now, displayedComponents: .date).labelsHidden()
                    Spacer()
                    if !Calendar.current.isDateInToday(selectedDate) {
                        Button("今天") { selectedDate = .now }.frame(minHeight: 44)
                    }
                }
                if Calendar.current.isDateInToday(selectedDate) { CurrentCard() }
                DaySummary(interval: interval)
                if !store.concerns().isEmpty {
                    NavigationLink { RecordReviewView() } label: {
                        Label("\(store.concerns().count) 段记录待核对", systemImage: "exclamationmark.circle")
                            .font(.subheadline).frame(minHeight: 44)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("停留地点").font(.headline)
                    if store.places.isEmpty {
                        EmptyCard(title: "从一个熟悉的地方开始", message: "添加家或公司，慢慢留下生活的轮廓。", symbol: "mappin")
                        Button("添加地点") { sheet = .place }.buttonStyle(PrimaryButtonStyle()).controlSize(.large)
                    } else if store.visitedPlaces(in: interval).isEmpty {
                        Text("这一天还没有地点停留，常用地点可在“地点”页查看。")
                            .font(.subheadline).foregroundStyle(Theme.quiet).padding(.vertical, 12)
                    } else {
                        ForEach(store.visitedPlaces(in: interval)) { place in
                            NavigationLink { PlaceDetailView(place: place) } label: {
                                PlaceTile(place: place, duration: store.total(in: interval, kind: .stay, placeID: place.id))
                            }.buttonStyle(PressStyle())
                            Divider().opacity(0.5)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("最近记录").font(.headline); Spacer()
                        NavigationLink("全部") { DayJournalView(date: selectedDate) }.font(.subheadline).frame(minHeight: 44)
                    }
                    if store.entries(in: interval).isEmpty {
                        Text("这一天还没有记录。").foregroundStyle(Theme.quiet).font(.subheadline).padding(.vertical, 12)
                    } else { EntryList(interval: interval, limit: 3) }
                }
            }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 680)
        }.frame(maxWidth: .infinity).pageCanvas().navigationTitle("此处")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("补记时间", systemImage: "plus") { sheet = .entry }.disabled(store.visiblePlaces.isEmpty)
                        Button("添加地点", systemImage: "mappin.and.ellipse") { sheet = .place }
                        Button("分享这一天", systemImage: "square.and.arrow.up") { sheet = .share }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("今日操作")
                }
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .place: PlaceEditor()
                case .entry: EntryEditor(date: selectedDate)
                case .share: SharePosterView(interval: interval)
                }
            }
            .animation(reduceMotion ? nil : Motion.change, value: Calendar.current.isDateInToday(selectedDate))
    }
}

private struct CurrentCard: View {
    @Environment(JournalStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(location.statusTitle, systemImage: store.active == nil ? "circle" : "record.circle")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                Spacer()
                if store.active != nil {
                    Button {
                        if location.enabled { location.setEnabled(false) } else { store.stop() }
                    } label: { Image(systemName: "pause").frame(width: 44, height: 44) }
                        .accessibilityLabel("暂停记录").buttonStyle(PressStyle())
                }
            }
            if let active = store.active {
                Text(store.title(active)).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    let duration = TimeMath.duration(timeline.date.timeIntervalSince(active.start))
                    Text(duration).font(.system(.largeTitle, design: .rounded).weight(.medium)).monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : Motion.change, value: duration)
                }
                Text("\(active.start.formatted(date: .omitted, time: .shortened)) 开始")
                    .font(.subheadline).foregroundStyle(Theme.quiet)
            } else {
                Text("慢慢走，留下生活。").font(.title2.weight(.medium))
                if !store.isDemo && !store.visiblePlaces.isEmpty {
                    if location.authorization == .denied || location.authorization == .restricted {
                        Button("检查定位权限") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }.buttonStyle(.bordered).controlSize(.large)
                    } else {
                        Button(location.enabled ? "刷新位置" : "继续记录") {
                            if location.enabled { location.locateOnce() } else { location.setEnabled(true) }
                        }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            if store.active != nil && !location.enabled && !store.isDemo {
                Button("继续自动识别") { location.setEnabled(true) }.buttonStyle(.bordered)
            }
            Text(location.statusDetail).font(.footnote).foregroundStyle(Theme.quiet)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.highlight, in: RoundedRectangle(cornerRadius: 24))
            .animation(reduceMotion ? nil : Motion.change, value: store.active?.id)
    }
}

struct DaySummary: View {
    @Environment(JournalStore.self) private var store
    let interval: DateInterval
    @State private var explanation = false
    @State private var selectedTime: Date?
    @State private var destination: TimelineDestination?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("时间分布").font(.headline)
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let entries = store.entries(in: interval, now: timeline.date)
                Chart(entries) { entry in
                    BarMark(xStart: .value("开始", max(entry.start, interval.start)),
                            xEnd: .value("结束", min(entry.end ?? timeline.date, interval.end)), y: .value("记录", "时间"))
                    .foregroundStyle(entry.kind == .travel ? Theme.quiet.opacity(0.35) : Theme.color(store.place(entry.placeID)?.kind ?? .other))
                    .cornerRadius(3)
                    .accessibilityLabel(store.title(entry))
                    .accessibilityValue(TimeMath.duration(entry.duration(in: interval, now: timeline.date)))
                }.chartXScale(domain: interval.start...interval.end).chartYAxis(.hidden)
                    .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted))) } }
                    .frame(height: 72).chartXSelection(value: $selectedTime)
                if let selectedTime, selectedTime < min(interval.end, timeline.date) {
                    if let entry = entries.first(where: { $0.start <= selectedTime && ($0.end ?? timeline.date) > selectedTime }) {
                        Button { destination = .entry(entry) } label: {
                            Label("\(store.title(entry)) · 查看与修正", systemImage: "pencil")
                                .font(.subheadline).frame(minHeight: 44)
                        }
                    } else {
                        Button("补记这段空白", systemImage: "plus") {
                            let start = max(interval.start, entries.compactMap(\.end).filter { $0 <= selectedTime }.max() ?? interval.start)
                            let end = min(min(interval.end, timeline.date), entries.map(\.start).filter { $0 > selectedTime }.min() ?? timeline.date)
                            if end > start { destination = .gap(DateInterval(start: start, end: end)) }
                        }.font(.subheadline).frame(minHeight: 44).disabled(store.visiblePlaces.isEmpty)
                    }
                } else {
                    Text("轻点或拖动时间轴，选择记录或空白时间。") .font(.caption).foregroundStyle(Theme.quiet)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { metrics(timeline.date) }
                    VStack(alignment: .leading, spacing: 20) { metrics(timeline.date) }
                }
            }
            DisclosureGroup("如何计算", isExpanded: $explanation) {
                Text("空白是未记录的时间。移动时长由离开与到达计算，不代表连续 GPS 轨迹。")
                    .font(.footnote).foregroundStyle(Theme.quiet).padding(.top, 8)
            }.font(.caption).foregroundStyle(Theme.quiet)
                .animation(reduceMotion ? nil : Motion.expand, value: explanation)
        }
        .onChange(of: interval.start) { _, _ in selectedTime = nil }
        .sheet(item: $destination) { destination in
            switch destination {
            case .entry(let entry): EntryDetailView(entry: entry)
            case .gap(let range): EntryEditor(date: range.start, suggestedRange: range)
            }
        }
    }
    @ViewBuilder private func metrics(_ now: Date) -> some View {
        Metric(title: "地点停留", value: TimeMath.duration(store.total(in: interval, kind: .stay, now: now)))
        Metric(title: "移动", value: TimeMath.duration(store.total(in: interval, kind: .travel, now: now)))
    }
}

struct PlaceTile: View {
    let place: Place
    let duration: TimeInterval
    var body: some View {
        HStack(spacing: 14) {
            PlaceBadge(kind: place.kind)
            VStack(alignment: .leading, spacing: 5) {
                Text(place.name).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(TimeMath.duration(duration)).font(.subheadline).foregroundStyle(Theme.quiet)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.quiet)
        }.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

struct EntryList: View {
    @Environment(JournalStore.self) private var store
    let interval: DateInterval
    var limit: Int? = nil
    @State private var editing: JournalEntry?
    private var visible: [JournalEntry] {
        let all = store.entries(in: interval)
        return limit.map { Array(all.suffix($0).reversed()) } ?? all
    }
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(visible) { entry in
                Button { editing = entry } label: {
                    HStack(alignment: .top, spacing: 16) {
                        Text(max(entry.start, interval.start).formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.quiet).frame(minWidth: 46, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.title(entry)).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                            Text(TimeMath.duration(entry.duration(in: interval))).font(.subheadline).foregroundStyle(Theme.quiet)
                            if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(Theme.quiet).lineLimit(2) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.quiet)
                    }.padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(PressStyle()).foregroundStyle(Theme.ink)
                Divider().opacity(0.5)
            }
        }.sheet(item: $editing) { EntryDetailView(entry: $0) }
    }
}

struct DayJournalView: View {
    let date: Date
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(date.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(Theme.quiet)
                NavigationLink { DayReplayView(date: date) } label: {
                    Label("地图回看", systemImage: "play.circle").frame(minHeight: 44)
                }
                EntryList(interval: TimeMath.day(date))
            }.padding(24).frame(maxWidth: 680)
        }.frame(maxWidth: .infinity).pageCanvas().navigationTitle("这一天").navigationBarTitleDisplayMode(.inline)
    }
}


private enum TimelineDestination: Identifiable {
    case entry(JournalEntry)
    case gap(DateInterval)
    var id: String {
        switch self {
        case .entry(let entry): entry.id.uuidString
        case .gap(let range): "gap-\(range.start.timeIntervalSince1970)"
        }
    }
}
