import Foundation
import SwiftData

@MainActor
struct AppEnvironment {
    let repository: any AppRepository
    let notifications: NotificationService
    let entitlements: any EntitlementService
    let network: NetworkMonitor
    let keychain: KeychainStore
    let authService: SupabaseAuthService?
    let clock: any AppClock
    let syncCoordinator: OfflineSyncCoordinator

    static func make(modelContext: ModelContext) -> AppEnvironment {
        let keychain = KeychainStore()
        let repository: any AppRepository
        let authService: SupabaseAuthService?
        let arguments = ProcessInfo.processInfo.arguments
        let forceDemo = arguments.contains("-forceDemo") || arguments.contains("-marketingSeed")
        if let configuration = SupabaseConfiguration.bundled, !forceDemo {
            repository = LiveAppRepository(configuration: configuration, keychain: keychain, modelContext: modelContext)
            authService = SupabaseAuthService(configuration: configuration, keychain: keychain)
        } else {
            repository = DemoAppRepository(context: modelContext)
            authService = nil
        }
        let clock = SystemAppClock()
        let entitlements: any EntitlementService = {
            if arguments.contains("-entitlement plus") {
                return PlusEntitlementService()
            }
            if arguments.contains("-entitlement free") {
                return FreeEntitlementService()
            }
            if authService == nil {
                // Demo mode: keep multi-crew flows unlocked.
                return PlusEntitlementService()
            }
            return StoreKitEntitlementService()
        }()
        return AppEnvironment(
            repository: repository,
            notifications: NotificationService(),
            entitlements: entitlements,
            network: NetworkMonitor(),
            keychain: keychain,
            authService: authService,
            clock: clock,
            syncCoordinator: OfflineSyncCoordinator(repository: repository, clock: clock)
        )
    }
}
