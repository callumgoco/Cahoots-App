import SwiftUI

private enum TodayRequirementState {
    case scheduledIncomplete
    case complete
    case restDay
    case recovery
    case upcoming
    case closed
}

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showCheckIn = ProcessInfo.processInfo.arguments.contains("-showCheckIn")
    @State private var confirmRecovery = false
    @State private var showBuilder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppSpacing.large) {
                    HStack(alignment: .center, spacing: AppSpacing.small) {
                        Text("Today")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: AppSpacing.small)
                        GroupSwitcherMenu()
                    }
                    if let challenge = store.currentChallenge {
                        posterCard(challenge)
                        WeekStrip(tokens: weekTokens(for: challenge))
                        captionRow(challenge)
                        if state(for: challenge) == .scheduledIncomplete {
                            checkInBar
                        }
                        pendingSyncCard
                        rejectedSyncCard
                    } else {
                        emptyChallengeState
                    }
                }
                .padding(AppSpacing.page)
                .padding(.bottom, 24)
            }
            .refreshable { await store.refresh() }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCheckIn, onDismiss: {
                store.consumePendingWorkoutSession()
            }) {
                WorkoutSessionView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(store.showCompletion)
            }
            .sheet(isPresented: $showBuilder) { ChallengeBuilderView() }
            .onChange(of: store.presentWorkoutSession) { _, shouldPresent in
                if shouldPresent { showCheckIn = true }
            }
            .confirmationDialog("Use a recovery day?", isPresented: $confirmRecovery, titleVisibility: .visible) {
                Button("Use recovery day") { Task { await store.useRecoveryDay() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This protects your streak and awards no points. You have \(store.remainingRecoveryDays) remaining.")
            }
            .roundPage()
        }
        .id(store.currentGroup?.id)
    }

    private var emptyChallengeState: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48, weight: .semibold))
                .frame(width: 96, height: 96)
                .background(AppColors.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            VStack(spacing: AppSpacing.small) {
                Text("No active round")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Start a round with your crew and check in here each day.")
                    .foregroundStyle(AppColors.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            if store.currentProposal != nil {
                Button("View open vote") { store.selectedTab = 1 }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("today.openVote")
            } else if canPropose {
                Button("Start a round") { showBuilder = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("today.startChallenge")
            }
            if canPropose || store.currentProposal != nil {
                Button("Open crew") { store.selectedTab = 1 }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("today.openCrew")
            } else {
                Button("Open crew") { store.selectedTab = 1 }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("today.openCrew")
            }
        }
        .padding(AppSpacing.extraLarge)
        .frame(maxWidth: .infinity)
    }

    private var canPropose: Bool {
        store.currentProposal == nil && !(store.snapshot?.challenges.contains {
            $0.groupID == store.currentGroup?.id && $0.status == .scheduled
        } ?? false)
    }

    private func posterCard(_ challenge: CahootsChallenge) -> some View {
        let requirementState = state(for: challenge)
        return CahootsCard(elevated: true) {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                HStack {
                    StatusPill(text: statusText(requirementState), kind: statusKind(requirementState))
                    Spacer()
                    if store.todaySubmission.map({ $0.syncState == .waiting || $0.syncState == .failed }) == true {
                        StatusPill(text: FriendFacingCopy.savedOnPhone, kind: .warning)
                    }
                }

                switch requirementState {
                case .scheduledIncomplete:
                    heroDeadlineCountdown(challenge)
                    Text(challenge.activityType)
                        .font(.title3.bold())
                    Text("Target · \(challenge.quantityLabel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryInk)
                    crewPostedStrip

                case .complete:
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                        heroMetric(
                            amount: store.todaySubmission?.quantity ?? challenge.minimumQuantity,
                            unit: challenge.measurementType.shortName,
                            label: "done today"
                        )
                    }
                    Text("\(store.todayPoints) points earned")
                        .font(.title3.bold())
                        .foregroundStyle(AppColors.accent)
                    if let sync = store.todaySubmission?.syncState, sync != .synced {
                        Text(FriendFacingCopy.syncLabel(for: sync))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                    crewPostedStrip

                case .restDay:
                    Label("Nothing scheduled today", systemImage: "moon.stars.fill")
                        .font(.title2.bold())
                    Text("Recovery is part of consistency. Your next requirement will appear when it is scheduled.")
                        .foregroundStyle(AppColors.secondaryInk)

                case .recovery:
                    Label("Recovery day", systemImage: "moon.zzz.fill")
                        .font(.title2.bold())
                        .foregroundStyle(AppColors.accent)
                    Text("Your streak is protected. No points are awarded.")
                        .foregroundStyle(AppColors.secondaryInk)

                case .upcoming:
                    Label("Challenge starts soon", systemImage: "calendar.badge.clock")
                        .font(.title2.bold())
                    Text("Starts \(challenge.startDate.formatted(date: .long, time: .omitted))")
                        .foregroundStyle(AppColors.secondaryInk)

                case .closed:
                    Label(FriendFacingCopy.missedWindow, systemImage: "lock.fill")
                        .font(.title2.bold())
                    Text("You can check in again on the next scheduled day.")
                        .foregroundStyle(AppColors.secondaryInk)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary(challenge, state: requirementState))
    }

    private func heroMetric(amount: Double, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.micro) {
            AdaptiveStack(verticalAlignment: .leading, spacing: AppSpacing.small) {
                Text(amount.formatted(.number.precision(.fractionLength(amount.rounded() == amount ? 0 : 1))))
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 48 : 72, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .font(.title2.bold())
                    .foregroundStyle(AppColors.secondaryInk)
            }
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.secondaryInk)
        }
    }

    private func heroDeadlineCountdown(_ challenge: CahootsChallenge) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let deadline = ScheduleEngine.deadline(for: context.date, challenge: challenge)
            let remaining = deadline.map { max(0, $0.timeIntervalSince(context.date)) } ?? 0
            VStack(alignment: .leading, spacing: AppSpacing.micro) {
                Text("Time left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryInk)
                Text(Self.formatCountdown(remaining))
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 42 : 64, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityIdentifier("today.deadlineCountdown")
                    .accessibilityLabel("Time left \(Self.formatCountdown(remaining))")
            }
        }
    }

    private var crewPostedStrip: some View {
        let peers = store.todayPeerCheckIns
        let spoilered = !store.canRevealTodayQuantities
        return Group {
            if !peers.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(spoilered ? "Crew posted · hidden until you go" : "Crew today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryInk)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.small) {
                            ForEach(peers) { submission in
                                if let user = store.snapshot?.users.first(where: { $0.id == submission.userID }) {
                                    VStack(spacing: 4) {
                                        AvatarView(user: user, size: 40)
                                        Text(user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName)
                                            .font(.caption2.bold())
                                            .lineLimit(1)
                                        if spoilered {
                                            Text("Hidden")
                                                .font(.caption2)
                                                .foregroundStyle(AppColors.secondaryInk)
                                        } else {
                                            if let clip = PeerClipPlayButton.playableClip(from: submission) {
                                                PeerClipPlayButton(clip: clip)
                                            }
                                            if let challenge = store.currentChallenge {
                                                Text("\(Int(submission.quantity))")
                                                    .font(.caption.bold().monospacedDigit())
                                                Text(challenge.measurementType.shortName)
                                                    .font(.caption2)
                                                    .foregroundStyle(AppColors.secondaryInk)
                                            }
                                        }
                                    }
                                    .frame(width: 72)
                                }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("today.crewStrip")
            }
        }
    }

    private func captionRow(_ challenge: CahootsChallenge) -> some View {
        let streak = currentEntry?.currentStreak ?? 0
        let rank = store.currentRank.map { "#\($0)" } ?? "—"
        return Text("\(streak)-day streak · Rank \(rank) · \(challenge.title)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(streak) day streak, rank \(rank), \(challenge.title)")
    }

    private static func formatCountdown(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private var hasPendingFinishClip: Bool {
        _ = store.pendingWorkoutSessionRevision
        guard let challenge = store.currentChallenge, let userID = store.currentUser?.id else { return false }
        return PendingWorkoutSessionStore.load(challengeID: challenge.id, userID: userID) != nil
    }

    private var checkInBar: some View {
        HStack(spacing: AppSpacing.small) {
            if store.remainingRecoveryDays > 0 {
                Button {
                    confirmRecovery = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.headline.weight(.bold))
                        Text("Rest")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(width: 54, height: 54)
                    .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .foregroundStyle(AppColors.ink)
                }
                .accessibilityLabel("Need a rest day?")
                .accessibilityIdentifier("today.rest")
            }
            Button(hasPendingFinishClip ? "Finish workout" : "Log workout") { showCheckIn = true }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("today.logWorkout")
        }
    }

    @ViewBuilder
    private var pendingSyncCard: some View {
        let pending = store.currentPendingOperations
        if !pending.isEmpty {
            let failed = pending.filter { operation in
                store.snapshot?.submissions.first(where: { $0.clientGeneratedID == operation.clientGeneratedID })?.syncState == .failed
            }.count
            CahootsCard {
                AdaptiveStack(spacing: AppSpacing.medium) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.title2).foregroundStyle(AppColors.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(FriendFacingCopy.savedOnPhone).font(.headline)
                        Text(failed > 0
                              ? String(localized: "Retry when you have a stable connection.")
                              : String(localized: "Your workout will update automatically."))
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                    Spacer()
                    if failed > 0 {
                        Button("Retry") { Task { await store.retryPending() } }
                            .font(.subheadline.bold())
                            .disabled(store.isOffline)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rejectedSyncCard: some View {
        if let rejected = store.currentRejectedSubmissions.first {
            CahootsCard {
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    Image(systemName: "exclamationmark.shield.fill").font(.title2).foregroundStyle(AppColors.danger)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(FriendFacingCopy.syncLabel(for: .rejected)).font(.headline)
                        Text(rejected.rejectionReason ?? FriendFacingCopy.syncExplanation(for: .rejected))
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                }
            }
        }
    }

    private var currentEntry: LeaderboardEntry? {
        guard let userID = store.currentUser?.id else { return nil }
        return store.currentLeaderboard.first { $0.user.id == userID }
    }

    private func weekTokens(for challenge: CahootsChallenge) -> [WeekDayToken] {
        guard let userID = store.currentUser?.id, let snapshot = store.snapshot else { return [] }
        return WeekStripBuilder.tokens(
            challenge: challenge,
            userID: userID,
            submissions: snapshot.submissions,
            recoveries: snapshot.recoveryDays,
            now: store.environment.clock.now
        )
    }

    private func state(for challenge: CahootsChallenge) -> TodayRequirementState {
        let now = store.environment.clock.now
        if now < (ScheduleEngine.startInstant(for: challenge) ?? challenge.startDate) { return .upcoming }
        guard ScheduleEngine.isScheduled(on: now, challenge: challenge) else { return .restDay }
        if store.todayPoints > 0 { return .complete }
        if store.recoveryUsedToday { return .recovery }
        if let deadline = ScheduleEngine.deadline(for: now, challenge: challenge), now > deadline { return .closed }
        return .scheduledIncomplete
    }

    private func statusText(_ state: TodayRequirementState) -> String {
        switch state {
        case .scheduledIncomplete: "Ready"
        case .complete: "Complete"
        case .restDay: "Rest day"
        case .recovery: "Recovery"
        case .upcoming: "Upcoming"
        case .closed: "Missed"
        }
    }

    private func statusKind(_ state: TodayRequirementState) -> StatusPill.Kind {
        switch state {
        case .complete, .recovery: .positive
        case .closed: .warning
        case .scheduledIncomplete: .pending
        case .restDay, .upcoming: .neutral
        }
    }

    private func accessibilitySummary(_ challenge: CahootsChallenge, state: TodayRequirementState) -> String {
        switch state {
        case .scheduledIncomplete: "\(challenge.quantityLabel) \(challenge.activityType) required today. Not yet completed."
        case .complete: "Today’s requirement completed. \(store.todayPoints) points earned."
        case .restDay: "No workout scheduled today. Rest day."
        case .recovery: "Recovery day used. Current streak protected. No points awarded."
        case .upcoming: "Challenge has not started. Starts \(challenge.startDate.formatted(date: .long, time: .omitted))."
        case .closed: FriendFacingCopy.missedWindow
        }
    }
}

private extension Date {
    func formattedTimeRemaining(until deadline: Date) -> String {
        let interval = max(0, deadline.timeIntervalSince(self))
        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60
        if hours > 0 { return String(localized: "\(hours) hr \(minutes) min") }
        return String(localized: "\(minutes) min")
    }
}
