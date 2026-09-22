import SwiftUI
import SwiftData

@main struct CichuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            if let store = delegate.store, let location = delegate.location {
                AppHost(store: store, location: location)
            } else {
                ContentUnavailableView {
                    Label("暂时无法打开记录", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("原有数据未被删除。请关闭应用后重试。\n\(delegate.failure ?? "")")
                }
            }
        }
    }
}

/// Own services at application lifetime, including launches delivered for location events.
@MainActor final class AppDelegate: NSObject, UIApplicationDelegate {
    private(set) var container: ModelContainer?
    private(set) var store: JournalStore?
    private(set) var location: LocationService?
    private(set) var failure: String?
    override init() {
        super.init()
        do {
            let schema = Schema([Place.self, JournalEntry.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)])
            let store = JournalStore(context: container.mainContext)
            self.container = container; self.store = store
            location = LocationService(store: store)
        } catch {
            failure = error.localizedDescription
        }
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if launchOptions?[.location] != nil { location?.refreshRegions() }
        return true
    }
}

struct AppHost: View {
    @State private var store: JournalStore
    @State private var location: LocationService
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = "system"
    init(store: JournalStore, location: LocationService) {
        _store = State(initialValue: store)
        _location = State(initialValue: location)
    }
    init(container: ModelContainer, isDemo: Bool = false) {
        let store = JournalStore(context: container.mainContext, isDemo: isDemo)
        _store = State(initialValue: store)
        _location = State(initialValue: LocationService(store: store))
    }
    var body: some View {
        RootView().environment(store).environment(location)
            .tint(Theme.accent)
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .onChange(of: phase) { _, phase in
                if phase == .active { store.reload(); location.refreshRegions() }
            }
            .alert("未能完成操作", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("知道了") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }
}
