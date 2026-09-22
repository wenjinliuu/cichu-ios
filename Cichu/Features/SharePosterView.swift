import SwiftUI
import UIKit

private struct PosterRow: Identifiable {
    let id: String
    let title: String
    let seconds: Double
}

struct SharePosterView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let interval: DateInterval
    @State private var includeNames = false
    @State private var image: UIImage?
    @State private var error: String?
    private var rows: [PosterRow] {
        let stays = store.places.map { place in
            PosterRow(id: place.id.uuidString, title: includeNames ? place.name : place.kind.title,
                      seconds: store.total(in: interval, kind: .stay, placeID: place.id))
        }.filter { $0.seconds > 0 }
        if includeNames { return stays.sorted { $0.seconds > $1.seconds } }
        return Dictionary(grouping: stays, by: \.title).map { title, rows in
            PosterRow(id: title, title: title, seconds: rows.reduce(0) { $0 + $1.seconds })
        }.sorted { $0.seconds > $1.seconds }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Toggle("包含自定义地点名称", isOn: $includeNames)
                    Text(includeNames ? "已包含地点名称，分享前请检查。" : "只展示地点类别，保留一点私密。")
                        .font(.footnote).foregroundStyle(Theme.quiet).frame(maxWidth: .infinity, alignment: .leading)
                    DisclosureGroup("分享内容说明") {
                        Text("海报不含地址、坐标、备注或具体到访时刻。关闭名称开关时，同类地点会合并显示。")
                            .font(.footnote).foregroundStyle(Theme.quiet).padding(.top, 8)
                    }.font(.footnote)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 24))
                            .accessibilityLabel("时间分配分享海报")
                            .accessibilityValue(rows.map { "\($0.title)，\(TimeMath.duration($0.seconds))" }.joined(separator: "；"))
                    } else if let error {
                        VStack(alignment: .leading, spacing: 12) {
                            EmptyCard(title: "海报暂时没有生成", message: error, symbol: "photo")
                            Button("重新生成", systemImage: "arrow.clockwise", action: render)
                                .buttonStyle(.bordered).frame(minHeight: 44)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else { ProgressView("准备海报").padding(.vertical, 40) }
                }.padding(20).frame(maxWidth: 480)
            }.frame(maxWidth: .infinity).pageCanvas().navigationTitle("分享这段时光").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 8) {
                        if let image {
                            ShareLink(item: Image(uiImage: image), preview: SharePreview("此处 · 时间留在哪里", image: Image(uiImage: image))) {
                                Label("分享图片", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                            }.buttonStyle(PrimaryButtonStyle())
                        }
                        ShareLink(item: "此处 · 看见时间，留在哪里。\n已记录 \(TimeMath.duration(store.total(in: interval)))，移动 \(TimeMath.duration(store.total(in: interval, kind: .travel)))。") {
                            Label("只分享文字", systemImage: "text.alignleft").font(.subheadline).frame(minHeight: 44)
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: 480)
                        .frame(maxWidth: .infinity).background(Theme.surface)
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .task(id: includeNames) { render() }
        }
    }
    @MainActor private func render() {
        let snapshot = rows
        let renderer = ImageRenderer(content: PosterCanvas(rows: snapshot, interval: interval,
            total: store.total(in: interval), travel: store.total(in: interval, kind: .travel))
            .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .large))
        renderer.scale = 3
        image = renderer.uiImage
        error = image == nil ? "可以重新生成，也可以先分享文字摘要。" : nil
    }
}

private struct PosterCanvas: View {
    let rows: [PosterRow]
    let interval: DateInterval
    let total: Double
    let travel: Double
    private var shown: [PosterRow] {
        let first = Array(rows.prefix(6))
        return rows.count <= 6 ? first : first + [PosterRow(id: "remainder", title: "其余地点", seconds: rows.dropFirst(6).reduce(0) { $0 + $1.seconds })]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 8) { BrandMark().frame(width: 22, height: 22); Text("此处").font(.subheadline.weight(.medium)); Spacer() }
            Text("时间，\n留在生活里。").font(.system(size: 36, weight: .bold, design: .rounded))
            Text("\(interval.start.formatted(date: .abbreviated, time: .omitted)) — \(min(interval.end, .now).formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text(TimeMath.duration(total)).font(.title.bold())
                Text("这一段，被记住的时光").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(shown) { row in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Spacer(); Text(TimeMath.duration(row.seconds)).font(.caption.monospacedDigit())
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.accent.opacity(0.08))
                            Capsule().fill(Theme.accent.opacity(0.6)).frame(width: proxy.size.width * min(1, row.seconds / max(total, 1)))
                        }
                    }.frame(height: 8)
                }
            }
            if rows.isEmpty { Text("留一点空白，等生活慢慢写下。").font(.subheadline) }
            Divider()
            HStack { Text("路上时间"); Spacer(); Text(TimeMath.duration(travel)) }.font(.subheadline)
            Text("看见时间，留在哪里。\n仅统计已有记录，空白时间未计入。")
                .font(.caption).foregroundStyle(.secondary).lineSpacing(5)
        }.padding(28).frame(width: 360).foregroundStyle(Theme.ink).background(Theme.background)
    }
}
