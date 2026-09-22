import Foundation
import SwiftData
import CoreLocation

enum PlaceKind: String, Codable, CaseIterable, Identifiable {
    case home, work, exercise, cafe, study, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "家"; case .work: "工作"; case .exercise: "运动"
        case .cafe: "咖啡"; case .study: "学习"; case .other: "其他"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house.fill"; case .work: "briefcase.fill"
        case .exercise: "figure.run"; case .cafe: "cup.and.saucer.fill"
        case .study: "book.closed.fill"; case .other: "mappin.and.ellipse"
        }
    }
}

@Model final class Place {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var address: String
    var archived: Bool
    var createdAt: Date
    var kind: PlaceKind { PlaceKind(rawValue: kindRaw) ?? .other }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    init(id: UUID = UUID(), name: String, kind: PlaceKind, latitude: Double,
         longitude: Double, radius: Double = 150, address: String = "") {
        self.id = id; self.name = name; kindRaw = kind.rawValue
        self.latitude = latitude; self.longitude = longitude; self.radius = radius
        self.address = address; archived = false; createdAt = .now
    }
}

enum EntryKind: String, Codable { case stay, travel }
enum EntrySource: String, Codable { case automatic, manual }

@Model final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var placeID: UUID?
    var destinationID: UUID?
    var start: Date
    var end: Date?
    var sourceRaw: String
    var note: String
    var kind: EntryKind { EntryKind(rawValue: kindRaw) ?? .stay }
    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }
    init(id: UUID = UUID(), kind: EntryKind, placeID: UUID?, destinationID: UUID? = nil,
         start: Date, end: Date? = nil, source: EntrySource, note: String = "") {
        self.id = id; kindRaw = kind.rawValue; self.placeID = placeID
        self.destinationID = destinationID; self.start = start; self.end = end
        sourceRaw = source.rawValue; self.note = note
    }
    func duration(in interval: DateInterval, now: Date = .now) -> TimeInterval {
        TimeMath.overlap(start: start, end: end ?? now, interval: interval)
    }
}

enum TimeMath {
    static func overlap(start: Date, end: Date, interval: DateInterval) -> TimeInterval {
        max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start)))
    }
    static func day(_ date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)!
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes < 60 { return "\(minutes) 分钟" }
        return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分"
    }
}

enum ReviewPeriod: String, CaseIterable, Identifiable {
    case week = "周", month = "月", year = "年", all = "全部"
    var id: String { rawValue }
    func interval(ending date: Date, earliest: Date?) -> DateInterval {
        let calendar = Calendar.current
        switch self {
        case .week: return calendar.dateInterval(of: .weekOfYear, for: date)!
        case .month: return calendar.dateInterval(of: .month, for: date)!
        case .year: return calendar.dateInterval(of: .year, for: date)!
        case .all: return .init(start: min(earliest ?? date, date), end: date)
        }
    }
}
