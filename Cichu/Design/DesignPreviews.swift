import SwiftUI
import SwiftData

private enum PreviewScreen { case today, places, review, settings }

@MainActor private final class PreviewDependencies {
    let container: ModelContainer
    let store: JournalStore
    let location: LocationService
    init() throws {
        let schema = Schema([Place.self, JournalEntry.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        try DemoData.populate(container.mainContext)
        store = JournalStore(context: container.mainContext, isDemo: true)
        location = LocationService(store: store)
    }
}

private struct DesignPreview: View {
    let screen: PreviewScreen
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
            do { dependencies = try PreviewDependencies() }
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
