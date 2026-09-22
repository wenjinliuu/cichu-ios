import Foundation
import Observation
import SwiftData

enum JournalError: LocalizedError {
    case invalidTime, overlap, invalidPlace, invalidBackup
    var errorDescription: String? {
        switch self {
        case .invalidTime: "离开时间必须晚于到达时间，且不能在未来。"
        case .overlap: "这段时间已有记录，请先调整或删除重叠的记录。"
        case .invalidPlace: "请选择有效地点，名称不能为空，范围应在 100–1000 米。"
        case .invalidBackup: "备份格式或数据不完整，未导入任何记录。"
        }
    }
}

@MainActor @Observable final class JournalStore {
    private(set) var places: [Place] = []
    private(set) var entries: [JournalEntry] = []
    var errorMessage: String?
    let context: ModelContext
    let isDemo: Bool
    var active: JournalEntry? { entries.first { $0.end == nil } }
    var visiblePlaces: [Place] { places.filter { !$0.archived } }

    init(context: ModelContext, isDemo: Bool = false) {
        self.context = context; self.isDemo = isDemo
        context.autosaveEnabled = false
        reload()
    }
    func reload() {
        do {
            places = try context.fetch(FetchDescriptor<Place>(sortBy: [SortDescriptor(\Place.createdAt)]))
            entries = try context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\JournalEntry.start, order: .reverse)]))
        } catch { errorMessage = "读取记录失败：\(error.localizedDescription)" }
    }
    @discardableResult func commit() -> Bool {
        do { try context.save(); reload(); return true }
        catch { context.rollback(); reload(); errorMessage = "保存失败：\(error.localizedDescription)"; return false }
    }
    func place(_ id: UUID?) -> Place? { places.first { $0.id == id } }
    func title(_ entry: JournalEntry) -> String {
        let origin = place(entry.placeID)?.name ?? "未命名地点"
        return entry.kind == .stay ? origin : "\(origin) → \(place(entry.destinationID)?.name ?? "移动中")"
    }
    func entries(in interval: DateInterval, now: Date = .now) -> [JournalEntry] {
        entries.filter { $0.duration(in: interval, now: now) > 0 }.sorted { $0.start < $1.start }
    }
    func total(in interval: DateInterval, kind: EntryKind? = nil, placeID: UUID? = nil, now: Date = .now) -> TimeInterval {
        entries.lazy.filter { (kind == nil || $0.kind == kind) && (placeID == nil || $0.placeID == placeID) }
            .reduce(0) { $0 + $1.duration(in: interval, now: now) }
    }
    @discardableResult func savePlace(existing: Place?, name: String, kind: PlaceKind,
                                     latitude: Double, longitude: Double, radius: Double, address: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude), (100...1000).contains(radius) else {
            errorMessage = JournalError.invalidPlace.localizedDescription; return false
        }
        let place = existing ?? Place(name: name, kind: kind, latitude: latitude, longitude: longitude)
        if existing == nil { context.insert(place) }
        place.name = name; place.kindRaw = kind.rawValue; place.latitude = latitude
        place.longitude = longitude; place.radius = radius; place.address = address
        return commit()
    }
    func archive(_ place: Place) {
        if let active, active.placeID == place.id { active.end = .now }
        place.archived = true; commit()
    }
    func arrive(_ place: Place, at date: Date = .now, source: EntrySource = .automatic) {
        guard !place.archived else { return }
        if let current = active {
            guard date >= current.start else { return }
            if current.kind == .stay && current.placeID == place.id { return }
            current.end = date
            if current.kind == .travel { current.destinationID = place.id }
        }
        // Ignore delayed location events that would overwrite a manually recorded interval.
        guard !entries.contains(where: { ($0.end ?? .distantFuture) > date && $0.start > date }) else {
            context.rollback(); reload(); return
        }
        context.insert(JournalEntry(kind: .stay, placeID: place.id, start: date, source: source))
        commit()
    }
    func depart(_ placeID: UUID, at date: Date = .now) {
        guard let current = active, current.kind == .stay, current.placeID == placeID,
              date >= current.start else { return }
        current.end = date
        context.insert(JournalEntry(kind: .travel, placeID: placeID, start: date, source: .automatic))
        commit()
    }
    func stop(at date: Date = .now) {
        if let active { active.end = max(active.start, date); commit() }
    }
    @discardableResult func saveEntry(existing: JournalEntry?, place: Place, start: Date, end: Date, note: String,
                                     kind: EntryKind = .stay, destination: Place? = nil) -> Bool {
        guard end > start, end <= Date.now else { errorMessage = JournalError.invalidTime.localizedDescription; return false }
        guard !entries.contains(where: { $0.id != existing?.id && $0.start < end && ($0.end ?? .distantFuture) > start }) else {
            errorMessage = JournalError.overlap.localizedDescription; return false
        }
        let entry = existing ?? JournalEntry(kind: .stay, placeID: place.id, start: start, end: end, source: .manual)
        if existing == nil { context.insert(entry) }
        entry.placeID = place.id; entry.start = start; entry.end = end
        entry.kindRaw = kind.rawValue; entry.destinationID = kind == .travel ? destination?.id : nil
        entry.note = note; entry.sourceRaw = EntrySource.manual.rawValue
        return commit()
    }
    func delete(_ entry: JournalEntry) { context.delete(entry); commit() }
    func erase() { entries.forEach { context.delete($0) }; places.forEach { context.delete($0) }; commit() }
}
