import SwiftUI

struct RecordReviewView: View {
    @Environment(JournalStore.self) private var store
    @State private var selected: JournalEntry?
    var body: some View {
        List {
            Section {
                Text("这些记录可能正常，也可能有漏记。此处不会擅自截断你的时间；请核对后调整或确认。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(store.concerns()) { entry in
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.title(entry)).font(.headline)
                    Text(entry.start.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    Text(entry.kind == .stay ? "持续超过 24 小时，请核对是否漏记离开。" : "移动过长或缺少终点，请核对。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    AdaptiveRow {
                        Button("查看并修正") { selected = entry }.buttonStyle(.bordered)
                        Button("记录无误") { store.confirm(entry) }.buttonStyle(.bordered)
                            .disabled(entry.end == nil)
                    }
                    if entry.end == nil { Text("进行中的记录可调整结束时间，或结束后确认。") .font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 8)
            }
            if store.concerns().isEmpty { Label("没有待核对的记录", systemImage: "checkmark.circle") }
        }.navigationTitle("记录核对")
            .sheet(item: $selected) { EntryDetailView(entry: $0) }
    }
}
