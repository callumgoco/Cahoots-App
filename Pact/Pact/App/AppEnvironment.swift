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
        if let configuration = SupabaseConfiguration.bundled {
            repository = LiveAppRepository(configuration: configuration, keychain: keychain)
            authService = SupabaseAuthService(configuration: configuration, keychain: keychain)
        } else {
            repository = DemoAppRepository(context: modelContext)
            authService = nil
        }
        let clock = SystemAppClock()
        return AppEnvironment(
            repository: repository,
            notifications: NotificationService(),
            entitlements: FreeEntitlementService(),
            network: NetworkMonitor(),
            keychain: keychain,
            authService: authService,
            clock: clock,
            syncCoordinator: OfflineSyncCoordinator(repository: repository, clock: clock)
        )
    }
}
