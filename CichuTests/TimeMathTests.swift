import XCTest
@testable import Cichu

final class TimeMathTests: XCTestCase {
    func testCrossMidnightUsesOnlyIntersection() {
        let start = Date(timeIntervalSince1970: 0)
        let day = DateInterval(start: start, duration: 86400)
        XCTAssertEqual(TimeMath.overlap(start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(7200), interval: day), 7200)
        XCTAssertEqual(TimeMath.overlap(start: start.addingTimeInterval(85000), end: start.addingTimeInterval(90000), interval: day), 1400)
    }
    func testNoOverlapAndInvertedIntervalNeverGiveNegativeTime() {
        let start = Date(timeIntervalSince1970: 0)
        let range = DateInterval(start: start, duration: 100)
        XCTAssertEqual(TimeMath.overlap(start: start.addingTimeInterval(200), end: start.addingTimeInterval(300), interval: range), 0)
        XCTAssertEqual(TimeMath.overlap(start: start.addingTimeInterval(80), end: start.addingTimeInterval(20), interval: range), 0)
    }
}
