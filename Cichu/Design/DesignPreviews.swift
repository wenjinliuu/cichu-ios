import SwiftUI
import SwiftData

private enum PreviewScreen { case today, places, review, settings }
private enum PreviewFixture { case typical, empty, longNames, travelOnly }

@MainActor private final class PreviewDependencies {
    let container: ModelContainer
    let store: JournalStore
    let location: LocationService
    init(fixture: PreviewFixture) throws {
        let schema = Schema([Place.self, JournalEntry.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        if fixture == .travelOnly {
            container.mainContext.insert(JournalEntry(kind: .travel, placeID: nil,
                start: .now.addingTimeInterval(-7200), end: .now.addingTimeInterval(-3600), source: .manual))
            try container.mainContext.save()
        } else if fixture != .empty {
            try DemoData.populate(container.mainContext)
            if fixture == .longNames {
                for place in try container.mainContext.fetch(FetchDescriptor<Place>()) {
                    place.name += " · 城市另一端的安静角落与周末常去的地方"
                }
                try container.mainContext.save()
            }
        }
        store = JournalStore(context: container.mainContext, isDemo: true)
        location = LocationService(store: store)
    }
}

private struct DesignPreview: View {
    let screen: PreviewScreen
    var fixture: PreviewFixture = .typical
    @State private var dependencies: PreviewDependencies?
    @State private var failure: String?
    var body: some View {
        Group {
            if let dependencies {
                NavigationStack {
                    switch screen {
                    case .today: TodayView()
                    case .places: PlacesView()
                    case .review: ReviewView()
                    case .settings: SettingsView()
                    }
                }.environment(dependencies.store).environment(dependencies.location).tint(Theme.accent)
            } else if let failure { Text(failure) }
            else { ProgressView() }
        }.task {
            guard dependencies == nil else { return }
            do { dependencies = try PreviewDependencies(fixture: fixture) }
            catch { failure = error.localizedDescription }
        }
    }
}

#Preview("今日 · 暖白") { DesignPreview(screen: .today).preferredColorScheme(.light) }
#Preview("今日 · 暖黑") { DesignPreview(screen: .today).preferredColorScheme(.dark) }
#Preview("今日 · 大字体") { DesignPreview(screen: .today).dynamicTypeSize(.accessibility3) }
#Preview("地图") { DesignPreview(screen: .places) }
#Preview("回顾") { DesignPreview(screen: .review) }
#Preview("设置") { DesignPreview(screen: .settings) }

#Preview("今日 · 空白") { DesignPreview(screen: .today, fixture: .empty) }
#Preview("回顾 · 长名称与最大字体") {
    DesignPreview(screen: .review, fixture: .longNames).dynamicTypeSize(.accessibility5)
}
#Preview("回顾 · 仅移动记录") { DesignPreview(screen: .review, fixture: .travelOnly) }
#Preview("地图 · 长名称与大字体") {
    DesignPreview(screen: .places, fixture: .longNames).dynamicTypeSize(.accessibility3)
}
