import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    let environment: AppEnvironment
    var snapshot: DemoSnapshot?
    var loadState: LoadState = .idle
    var hasCompletedOnboarding: Bool
    var isSignedIn = false
    var activeGroupID: UUID?
    var selectedTab = 0
    var colorTheme: AppColorTheme
    var errorBanner: String?
    var noticeBanner: String?
    var showNotificationPrimer = false
    var showCompletion = false
    var pendingJoinCode: String?
    var pendingLogWorkoutGroupID: UUID?
    var pendingOpenVoteProposalID: UUID?
    var presentWorkoutSession = false
    var presentOpenVote = false
    var presentInvite = false
    /// Bumped when a two-clip pending session is saved or cleared so Today refreshes Finish workout.
    var pendingWorkoutSessionRevision = 0
    var notificationsDenied = false
    var notificationAuthorizationState: NotificationAuthorizationState = .undetermined
    var sessionRecoveryRequired = false
    /// Raw Apple Sign In nonce held between request preparation and token exchange.
    var pendingAppleNonce: String?
    var boundaryTask: Task<Void, Never>?
    var foregroundSyncTask: Task<Void, Never>?
    var isDeletingAccount = false

    init(environment: AppEnvironment) {
        self.environment = environment
        AppDefaults.migrateLegacyKeysIfNeeded()
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetDemo") {
            UserDefaults.standard.removeObject(forKey: AppDefaults.onboardingComplete)
            UserDefaults.standard.removeObject(forKey: AppDefaults.activeGroupID)
            UserDefaults.standard.removeObject(forKey: AppDefaults.splashPlayed)
            UserDefaults.standard.removeObject(forKey: AppDefaults.colorTheme)
            UserDefaults.standard.removeObject(forKey: AppDefaults.legacyOnboardingComplete)
            UserDefaults.standard.removeObject(forKey: AppDefaults.legacyActiveGroupID)
        }
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: AppDefaults.onboardingComplete)
        activeGroupID = UserDefaults.standard.string(forKey: AppDefaults.activeGroupID).flatMap(UUID.init(uuidString:))
        let savedTheme = UserDefaults.standard.string(forKey: AppDefaults.colorTheme)
            .flatMap(AppColorTheme.init(rawValue:)) ?? .mint
        colorTheme = savedTheme
        AppColorThemeBridge.current = savedTheme
    }
}
