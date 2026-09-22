import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct Backup: Codable {
    let version: Int
    let exportedAt: Date
    let places: [PlaceRecord]
    let entries: [EntryRecord]
    struct PlaceRecord: Codable {
        let id: UUID; let name: String; let kind: PlaceKind
        let latitude: Double; let longitude: Double; let radius: Double
        let address: String; let archived: Bool; let createdAt: Date
    }
    struct EntryRecord: Codable {
        let id: UUID; let kind: EntryKind; let placeID: UUID?; let destinationID: UUID?
        let start: Date; let end: Date?; let source: EntrySource; let note: String
    }
    func validate(now: Date = .now) throws {
        let ids = Set(places.map(\.id))
        guard version == 1, places.count <= 10000, entries.count <= 500000,
              ids.count == places.count, Set(entries.map(\.id)).count == entries.count else { throw JournalError.invalidBackup }
        for place in places {
            guard !place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  place.name.count <= 60, place.latitude.isFinite, place.longitude.isFinite,
                  (-90...90).contains(place.latitude), (-180...180).contains(place.longitude),
                  (100...1000).contains(place.radius) else { throw JournalError.invalidBackup }
        }
        let sorted = entries.sorted { $0.start < $1.start }
        var previousEnd = Date.distantPast
        for entry in sorted {
            guard let placeID = entry.placeID, ids.contains(placeID), entry.start <= now,
                  entry.start >= previousEnd,
                  entry.destinationID == nil || ids.contains(entry.destinationID!),
                  entry.kind != .stay || entry.destinationID == nil else { throw JournalError.invalidBackup }
            if let end = entry.end { guard end >= entry.start, end <= now else { throw JournalError.invalidBackup } }
            previousEnd = entry.end ?? .distantFuture
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension JournalStore {
    func exportBackup() throws -> BackupDocument {
        let backup = Backup(version: 1, exportedAt: .now, places: places.map {
            .init(id: $0.id, name: $0.name, kind: $0.kind, latitude: $0.latitude, longitude: $0.longitude,
                  radius: $0.radius, address: $0.address, archived: $0.archived, createdAt: $0.createdAt)
        }, entries: entries.map {
            .init(id: $0.id, kind: $0.kind, placeID: $0.placeID, destinationID: $0.destinationID,
                  start: $0.start, end: $0.end, source: $0.source, note: $0.note)
        })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return BackupDocument(data: try encoder.encode(backup))
    }
    func restoreBackup(_ data: Data) throws {
        guard data.count <= 50_000_000 else { throw JournalError.invalidBackup }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        try backup.validate()
        // Restore is allowed only into an empty store, avoiding accidental overwrite/merge.
        guard places.isEmpty && entries.isEmpty else { throw JournalError.invalidBackup }
        for record in backup.places {
            let place = Place(id: record.id, name: record.name, kind: record.kind, latitude: record.latitude,
                              longitude: record.longitude, radius: record.radius, address: record.address)
            place.archived = record.archived; place.createdAt = record.createdAt; context.insert(place)
        }
        for record in backup.entries {
            // Open intervals end at export time so restoring never invents days of tracking.
            context.insert(JournalEntry(id: record.id, kind: record.kind, placeID: record.placeID, destinationID: record.destinationID,
                                        start: record.start, end: record.end ?? max(record.start, min(backup.exportedAt, .now)), source: record.source, note: record.note))
        }
        do { try context.save(); reload() }
        catch { context.rollback(); reload(); throw error }
    }
}
