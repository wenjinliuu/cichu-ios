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
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "YOUR TIME, IN PERSPECTIVE", title: "日子，慢慢成形。")
                Picker("回顾范围", selection: $period) { ForEach(ReviewPeriod.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if period != .all { DatePicker("回顾日期", selection: $date, in: ...Date.now, displayedComponents: .date) }
                Card {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("\(interval.start.formatted(date: .abbreviated, time: .omitted)) — \(min(interval.end, .now).formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(TimeMath.duration(store.total(in: interval))).font(.largeTitle.bold()).monospacedDigit()
                        Text("被记录的生活").foregroundStyle(.secondary)
                        if totals.isEmpty {
                            Text("还没有足够的数据。每一次停留，都会让轮廓更清晰。").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Chart(totals) { total in
                                SectorMark(angle: .value("停留时间", total.seconds), innerRadius: .ratio(0.76), angularInset: 3)
                                    .foregroundStyle(by: .value("地点", total.place.id.uuidString)).cornerRadius(5)
                                    .accessibilityLabel(total.place.name).accessibilityValue(TimeMath.duration(total.seconds))
                            }
                            .chartForegroundStyleScale(domain: totals.map { $0.place.id.uuidString }, range: totals.map { Theme.color($0.place.kind) })
                            .chartLegend(.hidden).frame(height: 190)
                            .chartBackground { _ in VStack { Text("\(totals.count)").font(.largeTitle.bold()); Text("个生活坐标").font(.caption).foregroundStyle(.secondary) } }
                            ForEach(totals) { total in
                                HStack {
                                    Label(total.place.name, systemImage: total.place.kind.symbol).foregroundStyle(Theme.color(total.place.kind))
                                    Spacer(); Text(TimeMath.duration(total.seconds)).font(.subheadline.monospacedDigit())
                                }.accessibilityElement(children: .combine)
                            }
                        }
                        Divider()
                        Metric(title: "移动时间", value: TimeMath.duration(store.total(in: interval, kind: .travel)))
                    }
                }
                if !store.entries(in: interval).isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(period == .year || period == .all ? "每个月的时间" : "每天的时间").font(.headline)
                            Chart(buckets, id: \.self) { bucket in
                                let component: Calendar.Component = period == .year || period == .all ? .month : .day
                                let range = Calendar.current.dateInterval(of: component, for: bucket)!
                                BarMark(x: .value("日期", bucket, unit: component), y: .value("小时", store.total(in: range) / 3600))
                                    .foregroundStyle(Theme.accent.gradient).cornerRadius(4)
                            }.frame(height: 180).chartXSelection(value: $selectedDay)
                            if let selectedDay {
                                Text("\(selectedDay.formatted(date: .abbreviated, time: .omitted)) · \(TimeMath.duration(store.total(in: Calendar.current.dateInterval(of: period == .year || period == .all ? .month : .day, for: selectedDay)!)))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text("往返之间").font(.title2.bold())
                if routes.isEmpty {
                    EmptyCard(title: "路上也有生活", message: "有了完整的离开与到达记录，就能看到常走路线的平均耗时。", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                } else {
                    ForEach(routes) { route in
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(route.title).font(.headline)
                                HStack {
                                    Metric(title: "单次平均", value: TimeMath.duration(route.seconds / Double(route.count)))
                                    Metric(title: "完整移动", value: "\(route.count) 次")
                                }
                            }
                        }
                    }
                }
                NavigationLink("全部地点记忆", systemImage: "archivebox") {
                    List(store.places) { place in
                        NavigationLink { PlaceDetailView(place: place) } label: {
                            HStack { PlaceBadge(kind: place.kind); Text(place.name); if place.archived { Text("已归档").font(.caption).foregroundStyle(.secondary) } }
                        }
                    }.navigationTitle("地点记忆")
                }.frame(minHeight: 44)
                Button("生成分享海报", systemImage: "photo") { poster = true }.buttonStyle(.borderedProminent).controlSize(.large)
                ShareLink(item: "此处 · 看见时间，留在哪里。\n\(interval.start.formatted(date: .abbreviated, time: .omitted)) 至 \(min(interval.end, .now).formatted(date: .abbreviated, time: .omitted))\n记录了 \(TimeMath.duration(store.total(in: interval)))，在 \(totals.count) 个地点留下生活。") {
                    Label("分享这段时光", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.bordered)
            }.padding(20).frame(maxWidth: 760)
        }.frame(maxWidth: .infinity).pageCanvas().toolbar(.hidden, for: .navigationBar)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: period)
            .sheet(isPresented: $poster) { SharePosterView(interval: interval) }
            .onChange(of: period) { _, _ in selectedDay = nil }
    }
}
