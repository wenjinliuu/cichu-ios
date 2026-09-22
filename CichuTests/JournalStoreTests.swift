import XCTest
import SwiftData
@testable import Cichu

@MainActor final class JournalStoreTests: XCTestCase {
    private func makeStore() throws -> (ModelContainer, JournalStore) {
        let schema = Schema([Place.self, JournalEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, JournalStore(context: container.mainContext))
    }
    func testDuplicateArrivalAndCommute() throws {
        let (container, store) = try makeStore()
        let home = Place(name: "家", kind: .home, latitude: 31, longitude: 121)
        let work = Place(name: "公司", kind: .work, latitude: 32, longitude: 121)
        container.mainContext.insert(home); container.mainContext.insert(work); store.commit()
        let date = Date.now.addingTimeInterval(-7200)
        store.arrive(home, at: date); store.arrive(home, at: date.addingTimeInterval(60))
        XCTAssertEqual(store.entries.count, 1)
        store.depart(home.id, at: date.addingTimeInterval(3600))
        store.depart(home.id, at: date.addingTimeInterval(3610))
        store.arrive(work, at: date.addingTimeInterval(5400))
        XCTAssertEqual(store.entries.count, 3)
        let trip = try XCTUnwrap(store.entries.first { $0.kind == .travel })
        XCTAssertEqual(trip.destinationID, work.id)
        XCTAssertEqual(trip.end!.timeIntervalSince(trip.start), 1800)
    }
    func testPauseDoesNotBridgeGapAndManualOverlapRejected() throws {
        let (container, store) = try makeStore()
        let place = Place(name: "家", kind: .home, latitude: 31, longitude: 121)
        container.mainContext.insert(place); store.commit()
        let date = Date.now.addingTimeInterval(-7200)
        store.arrive(place, at: date); store.stop(at: date.addingTimeInterval(600))
        store.arrive(place, at: date.addingTimeInterval(3600)); store.stop(at: date.addingTimeInterval(4200))
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertFalse(store.entries.contains { $0.kind == .travel })
        XCTAssertFalse(store.saveEntry(existing: nil, place: place, start: date, end: date.addingTimeInterval(300), note: ""))
        XCTAssertEqual(store.entries.count, 2)
    }
    func testRestoreRefusesOverwriteAndClosesOpenSession() throws {
        let (container, store) = try makeStore()
        let place = Place(name: "家", kind: .home, latitude: 31, longitude: 121)
        container.mainContext.insert(place); store.commit()
        store.arrive(place, at: .now.addingTimeInterval(-60))
        let data = try store.exportBackup().data
        XCTAssertThrowsError(try store.restoreBackup(data))
        let (restoredContainer, restored) = try makeStore()
        try restored.restoreBackup(data)
        XCTAssertEqual(restored.places.count, 1)
        XCTAssertNil(restored.active)
        _ = restoredContainer
    }
    func testSplitAndMergePreserveDurationAndRejectGap() throws {
        let (container, store) = try makeStore()
        let place = Place(name: "家", kind: .home, latitude: 31, longitude: 121)
        container.mainContext.insert(place); store.commit()
        let start = Date.now.addingTimeInterval(-7200)
        XCTAssertTrue(store.saveEntry(existing: nil, place: place, start: start, end: start.addingTimeInterval(3600), note: ""))
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertTrue(store.split(entry, at: start.addingTimeInterval(1800)))
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.total(in: DateInterval(start: start, duration: 7200)), 3600)
        XCTAssertTrue(store.mergeNext(entry))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(store.saveEntry(existing: nil, place: place, start: start.addingTimeInterval(4000), end: start.addingTimeInterval(5000), note: ""))
        XCTAssertFalse(store.mergeNext(entry))
        XCTAssertEqual(store.entries.count, 2)
    }
}
