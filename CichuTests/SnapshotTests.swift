import XCTest
import SwiftUI
import SwiftData
@testable import Cichu

/// Native, fixed-data image references, generated only on the pinned CI simulator.
@MainActor final class SnapshotTests: XCTestCase {
    func testMainScreensSnapshots() throws {
        let date = Date(timeIntervalSince1970: 1_790_064_000)
        let schema = Schema([Place.self, JournalEntry.self, LocationObservation.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        try DemoData.populate(container.mainContext, now: date)
        let store = JournalStore(context: container.mainContext, isDemo: true)
        let location = LocationService(store: store, driver: MockLocationDriver())
        for scheme in [ColorScheme.light, .dark] {
            try snapshot(TodayView(date: date).environment(store).environment(location), name: "today-\(scheme)", scheme: scheme)
            try snapshot(ReviewView(date: date).environment(store).environment(location), name: "review-\(scheme)", scheme: scheme)
            try snapshot(WelcomeView(finish: {}), name: "welcome-\(scheme)", scheme: scheme)
        }
        try snapshot(TodayView(date: date).environment(store).environment(location).environment(\.dynamicTypeSize, .accessibility1), name: "today-large-text", scheme: .light)
    }
    private func snapshot<V: View>(_ view: V, name: String, scheme: ColorScheme) throws {
        let controller = UIHostingController(rootView: view.environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh_CN")).environment(\.accessibilityReduceMotion, true).tint(Theme.accentText))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds; controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("__Snapshots__/SnapshotTests")
        let reference = directory.appendingPathComponent(name + ".png")
        if ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] != nil {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(image.pngData()).write(to: reference); return
        }
        guard let expected = UIImage(contentsOfFile: reference.path) else { XCTFail("Snapshot reference missing: \(name); run CI with record_snapshots"); return }
        let actualPixels = try pixels(image), expectedPixels = try pixels(expected)
        XCTAssertEqual(actualPixels.count, expectedPixels.count, "Snapshot dimensions changed: \(name)")
        guard actualPixels.count == expectedPixels.count else { return }
        let changed = zip(actualPixels, expectedPixels).filter { abs(Int($0.0) - Int($0.1)) > 8 }.count
        XCTAssertLessThan(Double(changed) / Double(actualPixels.count), 0.01, "Snapshot changed: \(name)")
    }
    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height))); return bytes
    }
}
