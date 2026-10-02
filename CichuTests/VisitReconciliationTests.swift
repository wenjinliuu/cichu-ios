import XCTest
import SwiftData
import CoreLocation
@testable import Cichu

@MainActor final class VisitReconciliationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_928_000)
    func testDelayedVisitRepairsStayAndCommuteWithoutDoubleCounting() throws {
        let (container, store, place) = try makeStore()
        let start = now.addingTimeInterval(-7200), end = now.addingTimeInterval(-1800)
        store.arrive(place, at: start.addingTimeInterval(300))
        store.reconcileVisit(place, arrival: start, departure: end, key: "visit-1", receivedAt: now)
        let stay = try XCTUnwrap(store.entries.first { $0.kind == .stay })
        XCTAssertEqual(stay.start, start); XCTAssertEqual(stay.end, end)
        XCTAssertEqual(store.active?.kind, .travel); XCTAssertEqual(store.active?.start, end)
        let total = store.total(in: DateInterval(start: start, end: now), kind: .stay, now: now)
        XCTAssertEqual(total, 5400)
        store.reconcileVisit(place, arrival: start, departure: end, key: "visit-1", receivedAt: now)
        XCTAssertEqual(store.entries.count, 2); XCTAssertEqual(store.observations.count, 1)
        _ = container
    }
    func testManualIntervalAndMissingArrivalAreNotInventedOrOverwritten() throws {
        let (container, store, place) = try makeStore()
        let start = now.addingTimeInterval(-7200), end = now.addingTimeInterval(-1800)
        XCTAssertTrue(store.saveEntry(existing: nil, place: place, start: start, end: end, note: "手动"))
        let id = store.entries.first?.id
        store.reconcileVisit(place, arrival: start, departure: end, key: "manual", receivedAt: now)
        XCTAssertEqual(store.entries.first?.id, id); XCTAssertEqual(store.entries.first?.note, "手动")
        XCTAssertEqual(store.observations.first?.result, "protected-manual-record")
        store.reconcileVisit(place, arrival: nil, departure: now, key: "unknown-arrival", receivedAt: now)
        XCTAssertEqual(store.entries.count, 1)
        _ = container
    }
    func testUnknownLocationIsDiscoveredAndPauseDoesNotBackfill() throws {
        let (container, store, _) = try makeStore()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "trackingEnabled"); defaults.set(now.addingTimeInterval(-3600), forKey: "trackingSince")
        let service = LocationService(store: store, defaults: defaults, driver: MockLocationDriver())
        service.handleVisit(coordinate: .init(latitude: 32, longitude: 121), accuracy: 50, arrival: now.addingTimeInterval(-7200), departure: now.addingTimeInterval(-600), receivedAt: now)
        XCTAssertEqual(store.places.filter(\.isDiscovered).count, 1)
        XCTAssertEqual(store.entries.first { $0.kind == .stay }?.start, now.addingTimeInterval(-3600))
        service.handleVisit(coordinate: .init(latitude: 32, longitude: 121), accuracy: 50, arrival: now.addingTimeInterval(-7200), departure: now.addingTimeInterval(-600), receivedAt: now)
        XCTAssertEqual(store.places.count, 2); XCTAssertEqual(store.observations.count, 1)
        _ = container
    }
    func testLegacyBackupLoadsAndNewMetadataRoundTrips() throws {
        let (container, store, place) = try makeStore()
        place.isDiscovered = true; store.arrive(place, at: .now.addingTimeInterval(-60))
        store.active?.needsReview = true; store.commit()
        let data = try store.exportBackup().data
        let (restoredContainer, restored, _) = try makeStore(empty: true)
        try restored.restoreBackup(data)
        XCTAssertTrue(restored.places.first?.isDiscovered == true)
        XCTAssertTrue(restored.entries.first?.needsReview == true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = 1
        json["places"] = (json["places"] as! [[String: Any]]).map { item in var item = item; item.removeValue(forKey: "isDiscovered"); return item }
        json["entries"] = (json["entries"] as! [[String: Any]]).map { item in var item = item; item.removeValue(forKey: "needsReview"); item.removeValue(forKey: "lastObserved"); return item }
        let (legacyContainer, legacy, _) = try makeStore(empty: true)
        try legacy.restoreBackup(JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(legacy.places.first!.isDiscovered); XCTAssertFalse(legacy.entries.first!.needsReview)
        _ = (container, restoredContainer, legacyContainer)
    }
    private func makeStore(empty: Bool = false) throws -> (ModelContainer, JournalStore, Place) {
        let schema = Schema([Place.self, JournalEntry.self, LocationObservation.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let store = JournalStore(context: container.mainContext)
        let place = Place(name: "家", kind: .home, latitude: 31, longitude: 121)
        if !empty { container.mainContext.insert(place); store.commit() }
        return (container, store, place)
    }
}
