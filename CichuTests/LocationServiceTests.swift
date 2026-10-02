import XCTest
import SwiftData
import CoreLocation
@testable import Cichu

@MainActor final class MockLocationDriver: LocationDriving {
    var delegate: CLLocationManagerDelegate?
    var authorization: CLAuthorizationStatus = .authorizedAlways
    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    var regions: Set<CLRegion> = []
    var regionsAvailable = true
    var maximumRegionMonitoringDistance: Double = 1000
    var requests = 0
    var visits = false
    var starts = 0
    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    func requestLocation() { requests += 1 }
    func startMonitoring(for region: CLRegion) { regions.insert(region); starts += 1 }
    func stopMonitoring(for region: CLRegion) { regions.remove(region) }
    func requestState(for region: CLRegion) {}
    func startMonitoringSignificantLocationChanges() {}
    func stopMonitoringSignificantLocationChanges() {}
    func startMonitoringVisits() { visits = true }
    func stopMonitoringVisits() { visits = false }
}

@MainActor final class LocationServiceTests: XCTestCase {
    func testFirstFixStartsImmediatelyAndExitCreatesTravel() throws {
        let (_, store, service, driver) = try makeTracking()
        let now = Date.now
        let fix = CLLocation(coordinate: .init(latitude: 31, longitude: 121), altitude: 0, horizontalAccuracy: 120, verticalAccuracy: 0, timestamp: now)
        service.locateOnce(); service.handleFix(fix, now: now)
        XCTAssertEqual(store.active?.kind, .stay)
        XCTAssertEqual(store.active?.placeID, store.places.first?.id)
        XCTAssertEqual(store.entries.count, 1)
        service.handleFix(fix, now: now)
        XCTAssertEqual(store.entries.count, 1)
        let away = CLLocation(coordinate: .init(latitude: 31.01, longitude: 121), altitude: 0, horizontalAccuracy: 20, verticalAccuracy: 0, timestamp: now.addingTimeInterval(60))
        service.handleFix(away, now: now.addingTimeInterval(60))
        XCTAssertEqual(store.active?.kind, .travel)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertTrue(driver.visits)
    }
    func testPoorFixDoesNotCreateStayAndRegionStartsWithoutSecondFix() throws {
        let (_, store, service, _) = try makeTracking()
        let now = Date.now
        service.handleFix(CLLocation(coordinate: .init(latitude: 31, longitude: 121), altitude: 0, horizontalAccuracy: 900, verticalAccuracy: 0, timestamp: now), now: now)
        XCTAssertNil(store.active)
        let place = try XCTUnwrap(store.places.first)
        let region = CLCircularRegion(center: place.coordinate, radius: 150, identifier: place.id.uuidString)
        service.handleRegion(region, entered: true, at: now)
        XCTAssertEqual(store.active?.placeID, place.id)
        service.handleRegion(region, entered: true, at: now)
        XCTAssertEqual(store.entries.count, 1)
    }
    func testRegionRefreshIsIdempotentAndReducedAccuracyIsVisible() throws {
        let (_, _, service, driver) = try makeTracking()
        let count = driver.starts
        service.refreshRegions(); service.refreshRegions()
        XCTAssertEqual(driver.starts, count)
        driver.accuracyAuthorization = .reducedAccuracy; service.authorizationChanged()
        XCTAssertEqual(service.monitoredPlaceCount, 0)
        XCTAssertEqual(service.statusTitle, "需要开启精确位置")
        XCTAssertFalse(service.backgroundReady)
    }
    func testDisabledAndManualSessionAreProtected() throws {
        let (_, store, service, _) = try makeTracking()
        let place = try XCTUnwrap(store.places.first)
        store.arrive(place, at: .now.addingTimeInterval(-60), source: .manual)
        let id = store.active?.id
        service.handleRegion(CLCircularRegion(center: place.coordinate, radius: 150, identifier: place.id.uuidString), entered: true)
        XCTAssertEqual(store.active?.id, id); XCTAssertEqual(store.active?.source, .manual)
        service.setEnabled(false)
        service.handleFix(CLLocation(latitude: 31, longitude: 121))
        XCTAssertNil(store.active)
    }
    func testPermissionDenialStopsOnlyAutomaticSessions() throws {
        let (_, store, service, driver) = try makeTracking()
        let place = try XCTUnwrap(store.places.first)
        store.arrive(place, at: .now.addingTimeInterval(-60), source: .manual)
        let manualID = store.active?.id
        driver.authorization = .denied; service.authorizationChanged()
        XCTAssertEqual(store.active?.id, manualID)
        XCTAssertEqual(store.active?.source, .manual)
        store.stop()
        driver.authorization = .authorizedAlways; service.authorizationChanged()
        store.arrive(place)
        let automaticID = store.active?.id
        driver.authorization = .denied; service.authorizationChanged()
        XCTAssertNil(store.active)
        XCTAssertTrue(store.entries.first { $0.id == automaticID }?.needsReview == true)
    }
    private func makeTracking() throws -> (ModelContainer, JournalStore, LocationService, MockLocationDriver) {
        let schema = Schema([Place.self, JournalEntry.self, LocationObservation.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let store = JournalStore(context: container.mainContext)
        container.mainContext.insert(Place(name: "家", kind: .home, latitude: 31, longitude: 121)); store.commit()
        let defaults = UserDefaults(suiteName: "location-tests-" + UUID().uuidString)!
        defaults.set(true, forKey: "trackingEnabled")
        let driver = MockLocationDriver()
        let service = LocationService(store: store, defaults: defaults, driver: driver)
        return (container, store, service, driver)
    }
}
