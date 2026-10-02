import XCTest

final class KeyFlowTests: XCTestCase {
    func testDailyReviewSettingsAndLocationHealth() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["今日"].waitForExistence(timeout: 15))
        capture(app, "today"); try audit(app, page: "今日")
        app.tabBars.buttons["回顾"].tap()
        XCTAssertTrue(app.staticTexts["时间，都留在这里。"].waitForExistence(timeout: 5) || app.navigationBars["回顾"].waitForExistence(timeout: 5))
        capture(app, "review"); try audit(app, page: "回顾")
        app.tabBars.buttons["地点"].tap()
        XCTAssertTrue(app.navigationBars["地点"].waitForExistence(timeout: 5))
        capture(app, "places"); try audit(app, page: "地点")
        app.tabBars.buttons["设置"].tap()
        capture(app, "settings"); try audit(app, page: "设置")
        let health = app.buttons["settings.location-health"]
        for _ in 0..<4 where !health.isHittable { app.swipeUp() }
        XCTAssertTrue(health.waitForExistence(timeout: 5)); health.tap()
        XCTAssertTrue(app.navigationBars["自动记录检查"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["location.refresh"].exists)
        capture(app, "location-health")
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
