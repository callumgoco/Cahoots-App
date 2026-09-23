import AuthenticationServices
import Foundation

extension AppStore {
    func start() async {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-skipOnboarding") {
            hasCompletedOnboarding = true
            UserDefaults.standard.set(true, forKey: AppDefaults.onboardingComplete)
        }
        guard hasCompletedOnboarding else { return }
        await load(reset: arguments.contains("-resetDemo"))
    }

    func startDemo(reset: Bool = false) async {
        hasCompletedOnboarding = true
        isSignedIn = true
        UserDefaults.standard.set(true, forKey: AppDefaults.onboardingComplete)
        await load(reset: reset)
    }

    /// Generates a raw Apple Sign In nonce, stores it for the upcoming exchange, and returns the SHA256 hex digest for `ASAuthorizationAppleIDRequest.nonce`.
    func beginAppleSignIn() -> String {
        let raw = AppleSignInNonce.random()
        pendingAppleNonce = raw
        return AppleSignInNonce.sha256(raw)
    }

    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            pendingAppleNonce = nil
            errorBanner = String(localized: "Sign in was cancelled.")
        case .failure:
            pendingAppleNonce = nil
            errorBanner = String(localized: "Sign in could not be completed. Try again.")
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                pendingAppleNonce = nil
                errorBanner = String(localized: "Apple did not return a valid identity token.")
                return
            }
            guard let nonce = pendingAppleNonce else {
                errorBanner = String(localized: "Sign in could not be completed. Try again.")
                return
            }
            pendingAppleNonce = nil
            do {
                try await environment.authService?.exchangeAppleIdentityToken(token, nonce: nonce)
                try environment.keychain.set(credential.user, for: "appleSubjectID")
                hasCompletedOnboarding = true
                isSignedIn = true
                UserDefaults.standard.set(true, forKey: AppDefaults.onboardingComplete)
                await load(reset: false)
                await registerForRemoteNotificationsIfNeeded()
            } catch {
                errorBanner = error.localizedDescription
            }
        }
    }

    func signUp(email: String, password: String, displayName: String) async {
        guard let auth = environment.authService else {
            errorBanner = String(localized: "Live sign-in is not configured.")
            return
        }
        do {
            try await auth.signUp(email: email, password: password, displayName: displayName)
            hasCompletedOnboarding = true
            isSignedIn = true
            UserDefaults.standard.set(true, forKey: AppDefaults.onboardingComplete)
            await load(reset: false)
            await registerForRemoteNotificationsIfNeeded()
        } catch RepositoryError.emailConfirmationRequired {
            noticeBanner = String(localized: "Confirm your email, then sign in.")
            errorBanner = nil
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        guard let auth = environment.authService else {
            errorBanner = String(localized: "Live sign-in is not configured.")
            return
        }
        do {
            try await auth.signIn(email: email, password: password)
            hasCompletedOnboarding = true
            isSignedIn = true
            UserDefaults.standard.set(true, forKey: AppDefaults.onboardingComplete)
            await load(reset: false)
            await registerForRemoteNotificationsIfNeeded()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    func resetPassword(email: String) async {
        guard let auth = environment.authService else {
            errorBanner = String(localized: "Live sign-in is not configured.")
            return
        }
        do {
            try await auth.resetPassword(email: email)
            noticeBanner = String(localized: "Check your email for a reset link.")
            errorBanner = nil
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    func signOut() {
        Task { await signOutAsync() }
    }

    func signOutAsync() async {
        boundaryTask?.cancel()
        foregroundSyncTask?.cancel()
        foregroundSyncTask = nil
        notificationPrimerTask?.cancel()
        notificationPrimerTask = nil
        showNotificationPrimer = false
        await environment.authService?.signOut()
        if environment.authService == nil {
            environment.keychain.removeAll()
        }
        WorkoutClipStore.removeAllFiles()
        PendingWorkoutSessionStore.clear()
        try? await environment.repository.clearLocalOfflineState()
        snapshot = nil
        isSignedIn = false
        hasCompletedOnboarding = false
        loadState = .idle
        sessionRecoveryRequired = false
        pendingJoinCode = nil
        pendingLogWorkoutGroupID = nil
        pendingOpenVoteProposalID = nil
        presentWorkoutSession = false
        presentOpenVote = false
        presentInvite = false
        isDeletingAccount = false
        UserDefaults.standard.set(false, forKey: AppDefaults.onboardingComplete)
    }

    func deleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        guard await applyCommand(.deleteAccount, preferReturnedSnapshot: false) else { return }
        await environment.notifications.replacePlan([])
        await signOutAsync()
    }

    func beginSessionRecovery() async {
        sessionRecoveryRequired = false
        await signOutAsync()
    }
}
