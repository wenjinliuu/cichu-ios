import SwiftUI
import SwiftData

/// A separate in-memory container: sample locations never enter the personal database.
struct DemoHost: View {
    @State private var container: ModelContainer?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let container { AppHost(container: container, isDemo: true) }
            else if let error {
                VStack(spacing: 20) { Text(error); Button("返回") { dismiss() } }.padding()
            } else { ProgressView("准备示例") }
        }.task {
            guard container == nil else { return }
            do {
                let schema = Schema([Place.self, JournalEntry.self])
                let model = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
                try DemoData.populate(model.mainContext)
                container = model
            } catch { self.error = "示例暂时无法打开：\(error.localizedDescription)" }
        }
    }
}

enum DemoData {
    @MainActor static func populate(_ context: ModelContext, now: Date = .now) throws {
        let home = Place(name: "温暖的家", kind: .home, latitude: 31.224, longitude: 121.455)
        let work = Place(name: "工作室", kind: .work, latitude: 31.235, longitude: 121.485)
        let cafe = Place(name: "街角咖啡", kind: .cafe, latitude: 31.219, longitude: 121.465)
        [home, work, cafe].forEach { context.insert($0) }
        let calendar = Calendar.current
        for offset in -20...0 {
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            let schedule: [(Double, Double, EntryKind, Place, Place?)] = [
                (0, 8, .stay, home, nil), (8, 8.6, .travel, home, work),
                (8.6, 17.5, .stay, work, nil), (17.5, 18, .travel, work, cafe),
                (18, 19, .stay, cafe, nil), (19, 19.3, .travel, cafe, home),
                (19.3, 24, .stay, home, nil)
            ]
            for (from, to, kind, place, destination) in schedule {
                let start = day.addingTimeInterval(from * 3600)
                let end = day.addingTimeInterval(to * 3600)
                guard start < now else { continue }
                context.insert(JournalEntry(kind: kind, placeID: place.id,
                                            destinationID: kind == .travel && end <= now ? destination?.id : nil,
                                            start: start, end: end > now ? nil : end, source: .automatic,
                                            note: kind == .stay && place.id == cafe.id ? "一杯咖啡，把步调慢下来。" : ""))
            }
        }
        try context.save()
    }
}
