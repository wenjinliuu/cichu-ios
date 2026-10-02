import XCTest

final class KeyFlowTests: XCTestCase {
    func testDailyReviewSettingsAndLocationHealth() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["今日"].waitForExistence(timeout: 15))
        capture(app, "today")
        app.tabBars.buttons["回顾"].tap()
        XCTAssertTrue(app.staticTexts["时间，都留在这里。"].waitForExistence(timeout: 5) || app.navigationBars["回顾"].waitForExistence(timeout: 5))
        capture(app, "review")
        app.tabBars.buttons["地点"].tap()
        XCTAssertTrue(app.navigationBars["地点"].waitForExistence(timeout: 5))
        capture(app, "places")
        app.tabBars.buttons["设置"].tap()
        capture(app, "settings")
        let health = app.buttons["settings.location-health"]
        for _ in 0..<4 where !health.isHittable { app.swipeUp() }
        XCTAssertTrue(health.waitForExistence(timeout: 5)); health.tap()
        XCTAssertTrue(app.navigationBars["自动记录检查"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["location.refresh"].exists)
        capture(app, "location-health")
    }
    // Audit failures remain warnings in central CI, while the separate flow test blocks
    // publication on any broken navigation or missing control.
    func testAccessibilityAuditMainScreens() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["今日"].waitForExistence(timeout: 15))
        for page in ["今日", "回顾", "地点", "设置"] {
            app.tabBars.buttons[page].tap()
            try audit(app, page: page)
        }
        let health = app.buttons["settings.location-health"]
        for _ in 0..<4 where !health.isHittable { app.swipeUp() }
        XCTAssertTrue(health.waitForExistence(timeout: 5)); health.tap()
        XCTAssertTrue(app.navigationBars["自动记录检查"].waitForExistence(timeout: 5))
        try audit(app, page: "自动记录检查")
    }
    private func audit(_ app: XCUIApplication, page: String) throws {
        if #available(iOS 17.0, *) {
            var issues: [String] = []
            try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .trait]) { issue in
                issues.append("Accessibility audit（\(page)）：\(issue.debugDescription)"); return true
            }
            issues.forEach { XCTFail($0) }
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
