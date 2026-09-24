import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct CahootsApp: App {
    @UIApplicationDelegateAdaptor(CahootsAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @State private var store: AppStore

    init() {
        let container = Self.makeContainer()
        modelContainer = container
        let environment = AppEnvironment.make(modelContext: ModelContext(container))
        let appStore = AppStore(environment: environment)
        _store = State(initialValue: appStore)
        // Attach before the first scene appears so a cold-start notification tap is not dropped.
        appDelegate.store = appStore
        CahootsMetricSubscriber.shared.start()
        if let identifier = Bundle.main.bundleIdentifier.map({ "\($0).sync" }) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
                guard let processingTask = task as? BGProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                let work = Task {
                    await appStore.handleBecameActive()
                    guard !Task.isCancelled else { return }
                    processingTask.setTaskCompleted(success: true)
                }
                processingTask.expirationHandler = {
                    work.cancel()
                    Task { @MainActor in
                        appStore.handleBackgroundTaskExpired()
                        processingTask.setTaskCompleted(success: false)
                    }
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(preferredScheme)
                .onAppear {
                    // Re-bind in case SwiftUI recreated the scene while keeping the same store.
                    appDelegate.store = store
                }
        }
        .modelContainer(modelContainer)
    }

    private var preferredScheme: ColorScheme? {
        switch store.snapshot?.appearance ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            AppSnapshotEntity.self,
            CachedUserEntity.self,
            CachedGroupEntity.self,
            CachedChallengeEntity.self,
            CachedSubmissionEntity.self,
            CachedScoreEventEntity.self
        ])
        let inMemory = ProcessInfo.processInfo.arguments.contains("-ephemeralData")
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: CahootsSwiftDataMigrationPlan.self,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: inMemory)]
            )
        } catch {
            do {
                return try ModelContainer(
                    for: schema,
                    migrationPlan: CahootsSwiftDataMigrationPlan.self,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            } catch {
                fatalError("Cahoots could not create its local store: \(error.localizedDescription)")
            }
        }
    }
}
