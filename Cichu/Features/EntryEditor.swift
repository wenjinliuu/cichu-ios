import SwiftUI

struct EntryEditor: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let existing: JournalEntry?
    @State private var placeID: UUID?
    @State private var start: Date
    @State private var end: Date
    @State private var note: String
    @State private var kind: EntryKind
    @State private var destinationID: UUID?
    init(date: Date = .now, existing: JournalEntry? = nil) {
        self.existing = existing
        let end = min(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date, .now)
        _placeID = State(initialValue: existing?.placeID)
        _start = State(initialValue: existing?.start ?? end.addingTimeInterval(-3600))
        _end = State(initialValue: existing?.end ?? end)
        _note = State(initialValue: existing?.note ?? "")
        _kind = State(initialValue: existing?.kind ?? .stay)
        _destinationID = State(initialValue: existing?.destinationID)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("停留地点") {
                    Picker("记录类型", selection: $kind) {
                        Text("停留").tag(EntryKind.stay); Text("移动").tag(EntryKind.travel)
                    }
                    Picker("地点", selection: $placeID) {
                        Text("请选择").tag(nil as UUID?)
                        ForEach(store.places.filter { !$0.archived || $0.id == existing?.placeID }) { place in
                            Text(place.name).tag(Optional(place.id))
                        }
                    }
                    if kind == .travel {
                        Picker("到达地点", selection: $destinationID) {
                            Text("未到达 / 未知").tag(nil as UUID?)
                            ForEach(store.places) { place in Text(place.name).tag(Optional(place.id)) }
                        }
                    }
                }
                Section("这段时间") {
                    DatePicker("到达", selection: $start, in: ...Date.now)
                    DatePicker("离开", selection: $end, in: ...Date.now)
                    if end > start { LabeledContent("停留", value: TimeMath.duration(end.timeIntervalSince(start))) }
                    else { Text("离开时间需要晚于到达时间。").foregroundStyle(.red) }
                }
                Section("给这次停留留一句话") { TextField("例如：久违地读完了一本书", text: $note, axis: .vertical).lineLimit(3...6) }
                Section { Text("补记不会自动推测前后通勤。与已有记录重叠的时间不能保存。").font(.footnote).foregroundStyle(.secondary) }
                if let error = store.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(existing == nil ? "补记一段时间" : "调整记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let place = store.place(placeID) else { return }
                        if store.saveEntry(existing: existing, place: place, start: start, end: end, note: note,
                                           kind: kind, destination: store.place(destinationID)) { dismiss() }
                    }.disabled(placeID == nil || end <= start)
                }
            }
        }
    }
}

struct EntryDetailView: View {
    @Environment(JournalStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    let entry: JournalEntry
    @State private var edit = false
    @State private var delete = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("地点", value: store.title(entry))
                    LabeledContent("开始", value: entry.start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("结束", value: entry.end?.formatted(date: .abbreviated, time: .shortened) ?? "正在记录")
                    LabeledContent("来源", value: entry.source == .automatic ? "自动识别（可能有延迟）" : "手动记录")
                    if !entry.note.isEmpty { Text(entry.note) }
                }
                if entry.end == nil {
                    Button("结束这段记录") {
                        if location.enabled { location.setEnabled(false) } else { store.stop() }
                        dismiss()
                    }
                } else {
                    Button("调整时间与备注") { edit = true }
                }
                if entry.kind == .travel { Text("移动表示两次地点事件之间的时间，并非连续 GPS 轨迹。暂停前尚未到达的移动记录不会参与路线均值统计。").font(.footnote).foregroundStyle(.secondary) }
                Button("删除记录", role: .destructive) { delete = true }
            }.navigationTitle("记录详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .sheet(isPresented: $edit) { EntryEditor(existing: entry) }
                .confirmationDialog("删除这段记录？此操作无法撤销。", isPresented: $delete, titleVisibility: .visible) {
                    Button("删除", role: .destructive) { store.delete(entry); dismiss() }
                }
        }
    }
}
