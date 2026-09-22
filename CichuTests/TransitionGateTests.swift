import XCTest
@testable import Cichu

final class TransitionGateTests: XCTestCase {
    func testPassingPlaceNeverConfirms() {
        var gate = TransitionGate()
        let home = UUID(), cafe = UUID(), start = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(gate.observe(placeID: cafe, currentID: home, at: start))
        XCTAssertFalse(gate.observe(placeID: cafe, currentID: home, at: start.addingTimeInterval(30)))
        XCTAssertFalse(gate.observe(placeID: home, currentID: home, at: start.addingTimeInterval(60)))
        XCTAssertNil(gate.candidate)
    }
    func testArrivalAndDepartureRequireCorroboration() {
        var gate = TransitionGate()
        let home = UUID(), start = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(gate.observe(placeID: home, currentID: nil, at: start))
        XCTAssertTrue(gate.observe(placeID: home, currentID: nil, at: start.addingTimeInterval(95)))
        XCTAssertFalse(gate.observe(placeID: nil, currentID: home, at: start.addingTimeInterval(200)))
        XCTAssertTrue(gate.observe(placeID: nil, currentID: home, at: start.addingTimeInterval(295)))
    }
    func testStaleObservationDoesNotConfirmAfterSuspension() throws {
        var gate = TransitionGate()
        let home = UUID(), start = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(gate.observe(placeID: home, currentID: nil, at: start))
        let data = try JSONEncoder().encode(gate)
        var restored = try JSONDecoder().decode(TransitionGate.self, from: data)
        XCTAssertFalse(restored.observe(placeID: home, currentID: nil, at: start.addingTimeInterval(700)))
        XCTAssertTrue(restored.observe(placeID: home, currentID: nil, at: start.addingTimeInterval(795)))
    }
}
