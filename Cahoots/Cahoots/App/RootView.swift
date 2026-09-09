import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            AppBannerHost()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await store.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.handleBecameActive() } }
        }
        .onChange(of: store.environment.network.isConnected) { _, connected in
            Task { await store.handleConnectivityChanged(connected) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await store.handleSignificantTimeChange() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
            Task { await store.handleSignificantTimeChange() }
        }
        .onOpenURL { store.handleURL($0) }
        .sheet(isPresented: Bindable(store).showNotificationPrimer) {
            NotificationPrimerView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { store.hasCompletedOnboarding && store.isSignedIn && store.pendingJoinCode != nil },
            set: { if !$0 { store.clearPendingJoinRoute() } }
        )) {
            JoinGroupView(initialCode: store.pendingJoinCode ?? "")
        }
        .alert("Your session has expired", isPresented: Bindable(store).sessionRecoveryRequired) {
            Button("Sign in again") { Task { await store.beginSessionRecovery() } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Your check-in is still saved on this device. Sign in again to resume synchronization.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.hasCompletedOnboarding {
            OnboardingView()
        } else {
            switch store.loadState {
            case .idle, .loading:
                LoadingSkeleton().roundPage()
            case .error(let message):
                LoadRecoveryView(message: message)
            case .empty:
                EmptyAccountView()
            case .loaded:
                if store.currentGroup == nil { EmptyAccountView() } else { MainTabView() }
            }
        }
    }
}

private struct LoadRecoveryView: View {
    @Environment(AppStore.self) private var store
    let message: String

    private var isAuthFailure: Bool {
        message.localizedCaseInsensitiveContains("session has expired")
            || message.localizedCaseInsensitiveContains("sign in again")
            || message.localizedCaseInsensitiveContains("authentication")
    }

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            CahootsEmptyState(symbol: "externaldrive.badge.exclamationmark", title: "Couldn’t load Cahoots", message: message)
            if isAuthFailure {
                Button("Sign in again") { Task { await store.beginSessionRecovery() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("load.signInAgain")
            } else {
                Button("Try again") { Task { await store.refresh() } }.buttonStyle(PrimaryButtonStyle())
            }
            if store.mode == .demo {
                Button("Reset local demo data", role: .destructive) { Task { await store.load(reset: true) } }
                    .buttonStyle(SecondaryButtonStyle())
                Text("Resetting is explicit. Cahoots does not replace unreadable saved data automatically.")
                    .font(.caption).foregroundStyle(AppColors.secondaryInk).multilineTextAlignment(.center)
            }
        }
        .padding(AppSpacing.page)
        .roundPage()
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            Tab("Today", systemImage: "circle.dotted.circle", value: 0) { TodayView() }
            Tab("Crew", systemImage: "person.3.fill", value: 1) { GroupView() }
            Tab("You", systemImage: "person.crop.circle", value: 2) { ProfileView() }
        }
        .tint(AppColors.accent)
    }
}

struct NotificationPrimerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 42))
                .foregroundStyle(AppColors.accent)
                .frame(width: 88, height: 88)
                .background(AppColors.accentSoft, in: RoundedRectangle(cornerRadius: 28))
            VStack(spacing: AppSpacing.small) {
                Text("A useful nudge, on your terms").font(.title2.bold()).multilineTextAlignment(.center)
                Text("Cahoots can remind you about scheduled check-ins and votes. No workout quantities appear on your lock screen.")
                    .foregroundStyle(AppColors.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            Button("Allow reminders") { Task { await store.requestNotifications() } }
                .buttonStyle(PrimaryButtonStyle())
            Button("Not now") { Task { await store.dismissNotificationPrimer(); dismiss() } }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(AppSpacing.large)
    }
}
