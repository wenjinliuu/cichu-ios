import SwiftUI
import Charts

struct PlaceTotal: Identifiable {
    let place: Place
    let seconds: Double
    var id: UUID { place.id }
}
struct RouteTotal: Identifiable {
    let id: String
    let title: String
    let count: Int
    let seconds: Double
}

struct ReviewView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period: ReviewPeriod = .week
    @State private var date = Date.now
    @State private var poster = false
    @State private var selectedDay: Date?
    private var interval: DateInterval { period.interval(ending: date, earliest: store.entries.last?.start) }
    private var totals: [PlaceTotal] {
        store.places.map { PlaceTotal(place: $0, seconds: store.total(in: interval, kind: .stay, placeID: $0.id)) }
            .filter { $0.seconds > 0 }.sorted { $0.seconds > $1.seconds }
    }
    private var routes: [RouteTotal] {
        let trips = store.entries(in: interval).filter { $0.kind == .travel && $0.end != nil && $0.destinationID != nil }
        return Dictionary(grouping: trips) { "\($0.placeID?.uuidString ?? "")/\($0.destinationID?.uuidString ?? "")" }
            .compactMap { key, entries in
                guard let first = entries.first else { return nil }
                return RouteTotal(id: key, title: store.title(first), count: entries.count,
                                  seconds: entries.reduce(0) { $0 + max(0, ($1.end ?? $1.start).timeIntervalSince($1.start)) })
            }.sorted { $0.seconds > $1.seconds }
    }
    private var buckets: [Date] {
        let component: Calendar.Component = period == .year || period == .all ? .month : .day
        var result: [Date] = []
        var cursor = Calendar.current.dateInterval(of: component, for: interval.start)?.start ?? interval.start
        while cursor < min(interval.end, .now), result.count < 1200 {
            result.append(cursor)
            guard let next = Calendar.current.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(spacing: 16) {
                    Picker("回顾范围", selection: $period) { ForEach(ReviewPeriod.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    if period != .all { DatePicker("回顾日期", selection: $date, in: ...Date.now, displayedComponents: .date).font(.subheadline) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    if let first = totals.first {
                        Text("这段时光，最多留在\(first.place.name)。")
                            .font(.title2.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("等生活，慢慢留下轮廓。") .font(.title2.weight(.medium))
                    }
                    Text("已记录 \(TimeMath.duration(store.total(in: interval))) · \(totals.count) 个地点")
                        .font(.subheadline).foregroundStyle(Theme.quiet)
                }
                if totals.isEmpty {
                    Metric(title: "移动时间", value: TimeMath.duration(store.total(in: interval, kind: .travel)))
                }
                if !totals.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("停留分配").font(.headline)
                        Chart(totals) { total in
                            SectorMark(angle: .value("停留时间", total.seconds), innerRadius: .ratio(0.82), angularInset: 2)
                                .foregroundStyle(by: .value("地点", total.place.id.uuidString)).cornerRadius(3)
                                .accessibilityLabel(total.place.name).accessibilityValue(TimeMath.duration(total.seconds))
                        }
                        .chartForegroundStyleScale(domain: totals.map { $0.place.id.uuidString }, range: totals.map { Theme.color($0.place.kind) })
                        .chartLegend(.hidden).frame(height: 156)
                        .chartBackground { _ in
                            VStack(spacing: 4) {
                                Text("\(totals.count)").font(.title.weight(.medium)).monospacedDigit()
                                Text("个地点").font(.caption).foregroundStyle(Theme.quiet)
                            }
                        }
                        ForEach(totals) { total in
                            NavigationLink { PlaceDetailView(place: total.place) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: total.place.kind.symbol).foregroundStyle(Theme.color(total.place.kind)).frame(width: 24).accessibilityHidden(true)
                                    Text(total.place.name).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text(TimeMath.duration(total.seconds)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.quiet)
                                }.padding(.vertical, 6).frame(minHeight: 44)
                            }.buttonStyle(PressStyle()).accessibilityElement(children: .combine)
                        }
                        Divider().opacity(0.5)
                        HStack { Text("移动时间"); Spacer(); Text(TimeMath.duration(store.total(in: interval, kind: .travel))).monospacedDigit() }
                            .font(.subheadline).foregroundStyle(Theme.quiet)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        Text(period == .year || period == .all ? "每个月的时间" : "每天的时间").font(.headline)
                        Chart(buckets, id: \.self) { bucket in
                            let component: Calendar.Component = period == .year || period == .all ? .month : .day
                            let range = Calendar.current.dateInterval(of: component, for: bucket)!
                            BarMark(x: .value("日期", bucket, unit: component), y: .value("小时", store.total(in: range) / 3600))
                                .foregroundStyle(Theme.accent.opacity(0.75)).cornerRadius(3)
                        }.frame(height: 168).chartXSelection(value: $selectedDay)
                            .animation(reduceMotion ? nil : Motion.change, value: period)
                        if let selectedDay {
                            Text("\(selectedDay.formatted(date: .abbreviated, time: .omitted)) · \(TimeMath.duration(store.total(in: Calendar.current.dateInterval(of: period == .year || period == .all ? .month : .day, for: selectedDay)!)))")
                                .font(.footnote).foregroundStyle(Theme.quiet)
                        }
                    }
                }
                DisclosureGroup("常走的路线") {
                    VStack(alignment: .leading, spacing: 16) {
                        if routes.isEmpty {
                            Text("完整的离开与到达记录，会形成路线统计。") .font(.subheadline).foregroundStyle(Theme.quiet)
                        }
                        ForEach(routes) { route in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(route.title).font(.body.weight(.medium))
                                Text("平均 \(TimeMath.duration(route.seconds / Double(route.count))) · \(route.count) 次")
                                    .font(.subheadline).foregroundStyle(Theme.quiet)
                            }.padding(.vertical, 8)
                        }
                    }.padding(.top, 16)
                }.font(.headline)
                NavigationLink("全部地点记忆", systemImage: "archivebox") {
                    List(store.places) { place in
                        NavigationLink { PlaceDetailView(place: place) } label: {
                            HStack { PlaceBadge(kind: place.kind); Text(place.name); if place.archived { Text("已归档").font(.caption).foregroundStyle(Theme.quiet) } }
                        }
                    }.navigationTitle("地点记忆")
                }.font(.subheadline).frame(minHeight: 44)
            }.padding(24).frame(maxWidth: 680)
        }.frame(maxWidth: .infinity).pageCanvas().navigationTitle("回顾")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { poster = true } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.accessibilityLabel("分享回顾")
                }
            }
            .sheet(isPresented: $poster) { SharePosterView(interval: interval) }
            .onChange(of: period) { _, _ in selectedDay = nil }
    }
}
