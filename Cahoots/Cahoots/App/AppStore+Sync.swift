import BackgroundTasks
import Foundation
import OSLog
import UIKit
import UserNotifications

extension AppStore {
    @discardableResult
    func applyCommand(_ command: RepositoryCommand, preferReturnedSnapshot: Bool = true) async -> Bool {
        do {
            if let updated = try await environment.repository.perform(command) {
                snapshot = SnapshotMigrator.migrate(updated)
            } else if preferReturnedSnapshot {
                await load(reset: false)
            }
            return true
        } catch {
            errorBanner = error.localizedDescription
            return false
        }
    }

    func load(reset: Bool) async {
        loadState = .loading
        do {
            snapshot = SnapshotMigrator.migrate(reset ? try await environment.repository.reset() : try await environment.repository.load())
            if ProcessInfo.processInfo.arguments.contains("-emptyDemo"), var emptySnapshot = snapshot {
                emptySnapshot.memberships.removeAll { $0.userID == emptySnapshot.currentUser.id }
                snapshot = emptySnapshot
            }
            if ProcessInfo.processInfo.arguments.contains("-noProposal"), var proposalSnapshot = snapshot {
                let openProposalIDs = Set(proposalSnapshot.proposals.filter { $0.status == .voting }.map(\.id))
                proposalSnapshot.proposals.removeAll { openProposalIDs.contains($0.id) }
                proposalSnapshot.votes.removeAll { openProposalIDs.contains($0.proposalID) }
                snapshot = proposalSnapshot
            }
            if !activeGroups.contains(where: { $0.id == activeGroupID }) { setActiveGroup(activeGroups.first?.id) }
            await reconcileAndPersist()
            await drainPending()
            await rebuildNotificationPlan()
            let arguments = ProcessInfo.processInfo.arguments
            if let tabFlag = arguments.firstIndex(of: "-tab"),
               arguments.indices.contains(tabFlag + 1),
               let requestedTab = Int(arguments[tabFlag + 1]),
               0...2 ~= requestedTab {
                selectedTab = requestedTab
            }
            isSignedIn = true
            loadState = currentGroup == nil ? .empty : .loaded
            presentPendingRouteIfPossible()
            await registerForRemoteNotificationsIfNeeded()
            AppLog.lifecycle.info("Loaded local app state with \(self.activeGroups.count, privacy: .public) active groups")
            logTodayCheckInDiagnostics(context: reset ? "reset" : "load")
        } catch RepositoryError.authenticationRequired {
            await beginSessionRecovery()
        } catch {
            if case RepositoryError.server(let message) = error,
               message == "not_authenticated" || RepositoryError.readable(message) == RepositoryError.authenticationRequired.errorDescription {
                await beginSessionRecovery()
                return
            }
            loadState = .error(error.localizedDescription)
            AppLog.persistence.error("Failed to load app state: \(error.localizedDescription, privacy: .private)")
        }
    }

    func refresh() async {
        await load(reset: false)
    }

    func retryPending() async {
        guard var snapshot else { return }
        for operation in snapshot.pendingOperations {
            snapshot = environment.syncCoordinator.prepareManualRetry(snapshot, clientGeneratedID: operation.clientGeneratedID)
        }
        self.snapshot = snapshot
        await drainPending(force: true)
    }

    func handleConnectivityChanged(_ connected: Bool) async {
        guard connected else {
            foregroundSyncTask?.cancel()
            foregroundSyncTask = nil
            return
        }
        await drainPending()
        await reconcileAndPersist()
        await rebuildNotificationPlan()
        await registerForRemoteNotificationsIfNeeded()
    }

    func handleBecameActive() async {
        await reconcileAndPersist()
        await drainPending()
        await rebuildNotificationPlan()
        await registerForRemoteNotificationsIfNeeded()
    }

    func handleSignificantTimeChange() async {
        await reconcileAndPersist()
        await rebuildNotificationPlan()
    }

    func handleBackgroundTaskExpired() {
        scheduleBackgroundSyncIfNeeded()
    }

    func persist() async throws {
        guard let snapshot else { return }
        try await environment.repository.save(snapshot)
    }

    @discardableResult
    func saveOrShowError() async -> Bool {
        do {
            try await persist()
            return true
        } catch {
            errorBanner = error.localizedDescription
            return false
        }
    }

    func requireConnection() -> Bool {
        guard !isOffline else {
            errorBanner = String(localized: "Connect to the internet to make this group change. Offline check-ins remain available.")
            return false
        }
        return true
    }

    func reconcileAndPersist() async {
        guard let snapshot else { return }
        let result = CahootsStateReconciler.reconcile(snapshot: snapshot, at: environment.clock.now)
        self.snapshot = result.snapshot
        if !result.events.isEmpty { AppLog.lifecycle.info("Reconciled \(result.events.count, privacy: .public) domain transitions") }
        noteCrewSizeChanges()
        await saveOrShowError()
        scheduleBoundary(result.nextBoundary)
    }

    /// Soft CTA when a solo crew gains a second active member and can put rounds to vote.
    func noteCrewSizeChanges() {
        guard let snapshot else { return }
        for group in activeGroups {
            let count = snapshot.memberships.filter { $0.groupID == group.id && $0.status == .active }.count
            let key = AppDefaults.memberCountPrefix + group.id.uuidString
            let previous = UserDefaults.standard.object(forKey: key) as? Int
            UserDefaults.standard.set(count, forKey: key)
            guard let previous, previous < 2, count >= 2 else { continue }
            let hasOpenVote = snapshot.proposals.contains { $0.groupID == group.id && $0.status == .voting }
            let hasScheduled = snapshot.challenges.contains { $0.groupID == group.id && $0.status == .scheduled }
            guard !hasOpenVote, !hasScheduled else { continue }
            noticeBanner = CrewEdgeCopy.crewReadyToPropose
        }
    }

    func scheduleBoundary(_ date: Date?) {
        boundaryTask?.cancel()
        guard let date else { return }
        boundaryTask = Task { [weak self] in
            guard let self else { return }
            try? await environment.clock.sleep(until: date)
            guard !Task.isCancelled else { return }
            await reconcileAndPersist()
            await rebuildNotificationPlan()
        }
    }

    func drainPending(force: Bool = false, scheduleRetries: Bool = true) async {
        guard let snapshot else { return }
        let hadPending = !snapshot.pendingOperations.isEmpty
        self.snapshot = await environment.syncCoordinator.drain(snapshot, connected: !isOffline, force: force)
        sessionRecoveryRequired = self.snapshot?.pendingOperations.contains {
            $0.lastError == "Authentication required"
        } == true
        let remaining = self.snapshot?.pendingOperations.count ?? 0
        AppLog.sync.info("Pending check-in count is now \(remaining, privacy: .public)")
        await reconcileAndPersist()
        scheduleBackgroundSyncIfNeeded()
        if scheduleRetries {
            scheduleForegroundSyncRetries()
        }
        if hadPending, remaining == 0 {
            await registerForRemoteNotificationsIfNeeded()
        }
    }

    /// Keeps draining while the app is foregrounded so backoff delays actually fire.
    func scheduleForegroundSyncRetries() {
        foregroundSyncTask?.cancel()
        guard !isOffline,
              let snapshot,
              !snapshot.pendingOperations.isEmpty,
              environment.syncCoordinator.earliestAutoRetryDate(in: snapshot) != nil else {
            foregroundSyncTask = nil
            return
        }
        foregroundSyncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard !self.isOffline, let snap = self.snapshot, !snap.pendingOperations.isEmpty else { return }
                guard let next = self.environment.syncCoordinator.earliestAutoRetryDate(in: snap) else { return }
                let delay = max(0.25, next.timeIntervalSince(self.environment.clock.now))
                let nanoseconds = UInt64(min(delay, 60) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await self.drainPending(force: false, scheduleRetries: false)
                if self.snapshot?.pendingOperations.isEmpty != false { return }
                if self.environment.syncCoordinator.earliestAutoRetryDate(in: self.snapshot ?? snap) == nil { return }
            }
        }
    }

    func scheduleBackgroundSyncIfNeeded() {
        guard snapshot?.pendingOperations.isEmpty == false,
              let identifier = Bundle.main.bundleIdentifier.map({ "\($0).sync" }) else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        // Prefer a quick background attempt; the foreground retry loop covers the common case.
        request.earliestBeginDate = environment.clock.now.addingTimeInterval(60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func registerForRemoteNotificationsIfNeeded() async {
        guard mode == .live, isSignedIn else { return }
        let status = await environment.notifications.authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func handleDevicePushToken(_ token: Data) async {
        guard mode == .live, let auth = environment.authService else { return }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        let environmentName: String = {
            #if DEBUG
            return "sandbox"
            #else
            return "production"
            #endif
        }()
        do {
            try await auth.registerPushToken(hex, environment: environmentName)
        } catch {
            AppLog.notifications.error("Push token registration failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func rebuildNotificationPlan() async {
        guard let snapshot else { return }
        let status = await environment.notifications.authorizationStatus()
        notificationsDenied = status == .denied
        switch status {
        case .notDetermined: notificationAuthorizationState = .undetermined
        case .denied: notificationAuthorizationState = .denied
        case .provisional, .ephemeral: notificationAuthorizationState = .provisional
        default: notificationAuthorizationState = .authorized
        }
        let settings = snapshot.notificationSettings ?? UserNotificationSettings.defaults(userID: snapshot.currentUser.id, groups: activeGroups)
        let suppressPrimer = ProcessInfo.processInfo.arguments.contains("-suppressNotificationPrimer")
        if status == .notDetermined,
           !suppressPrimer,
           !settings.primerDismissed,
           snapshot.challenges.contains(where: { activeGroups.map(\.id).contains($0.groupID) && ($0.status == .active || $0.status == .scheduled) }) {
            showNotificationPrimer = true
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            await environment.notifications.replacePlan([])
            return
        }
        await environment.notifications.replacePlan(NotificationPlanBuilder.build(snapshot: snapshot, now: environment.clock.now))
        AppLog.notifications.info("Rebuilt local notification plan")
        await registerForRemoteNotificationsIfNeeded()
    }
}
