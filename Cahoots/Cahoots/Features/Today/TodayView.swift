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
    @State private var clipUnlockHint: String?
    @State private var railPlaybackClip: WorkoutClip?

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
                        CrewTodayStatusRail(
                            entries: store.todayMemberStatuses,
                            accessibilityID: "today.crewStrip",
                            onSelectMember: handleCrewMemberTap
                        )
                        if let clipUnlockHint {
                            Text(clipUnlockHint)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.secondaryInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("today.clipUnlockHint")
                        }
                        revealedPeerDetailStrip
                        pendingSyncCard
                    } else {
                        emptyChallengeState
                    }
                }
                .padding(AppSpacing.page)
                .padding(.bottom, showsStickyCheckIn ? 100 : 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsStickyCheckIn {
                    checkInBar
                        .padding(.horizontal, AppSpacing.page)
                        .padding(.top, AppSpacing.small)
                        .padding(.bottom, AppSpacing.small)
                        .background(
                            AppColors.page
                                .shadow(color: AppColors.ink.opacity(0.06), radius: 16, y: -8)
                                .mask(Rectangle().padding(.top, -24))
                        )
                }
            }
            .refreshable { await store.refresh() }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showCheckIn, onDismiss: {
                store.consumePendingWorkoutSession()
            }) {
                WorkoutSessionView()
                    .interactiveDismissDisabled(store.showCompletion)
            }
            .sheet(isPresented: $showBuilder) { ChallengeBuilderView() }
            .background {
                PeerClipPlaybackPresenter(clip: $railPlaybackClip)
            }
            .onChange(of: store.presentWorkoutSession) { _, shouldPresent in
                if shouldPresent { showCheckIn = true }
            }
            .alert("Use a recovery day?", isPresented: $confirmRecovery) {
                Button("Use recovery day") { Task { await store.useRecoveryDay() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This protects your streak and awards no points. You have \(store.remainingRecoveryDays) remaining.")
            }
            .roundPage()
        }
        .id(store.currentGroup?.id)
    }

    private var showsStickyCheckIn: Bool {
        guard let challenge = store.currentChallenge else { return false }
        return state(for: challenge) == .scheduledIncomplete
    }

    private var emptyChallengeState: some View {
        let memberCount = store.groupMembers.count
        let hasFailed = store.latestFailedProposal != nil
        return VStack(spacing: AppSpacing.large) {
            Image(systemName: memberCount < 2 ? "person.badge.plus" : "calendar.badge.plus")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(AppColors.ink)
                .frame(width: 96, height: 96)
                .environment(\.colorScheme, .dark)
                .background(AppColors.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            VStack(spacing: AppSpacing.small) {
                Text(CrewEdgeCopy.emptyTodayTitle(memberCount: memberCount, hasFailedProposal: hasFailed))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(CrewEdgeCopy.emptyTodayMessage(memberCount: memberCount, hasFailedProposal: hasFailed))
                    .foregroundStyle(AppColors.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            if store.currentProposal != nil {
                Button("View open vote") { store.presentVote() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("today.openVote")
            } else if hasFailed, canPropose {
                Button("Try another round") { showBuilder = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("today.retryRound")
                if let failed = store.latestFailedProposal {
                    Button("Review last vote") {
                        store.presentVote(groupID: failed.groupID, proposalID: failed.id)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("today.reviewFailedVote")
                }
            } else if memberCount < 2 {
                Button("Invite friends") { store.presentInviteFlow() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("today.inviteFriends")
                if canPropose {
                    Button("Start now solo") { showBuilder = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("today.startChallenge")
                }
            } else if canPropose {
                Button("Start a round") { showBuilder = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("today.startChallenge")
            }
            Button("Open crew") { store.selectedTab = 1 }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("today.openCrew")
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
                    StatusPill(text: statusText(requirementState, challenge: challenge), kind: statusKind(requirementState))
                    Spacer()
                    if store.todaySubmission.map({ $0.syncState == .waiting || $0.syncState == .failed }) == true {
                        StatusPill(text: FriendFacingCopy.savedOnPhone, kind: .warning)
                    }
                }

                switch requirementState {
                case .scheduledIncomplete:
                    heroDeadlineCountdown(challenge)
                    VStack(alignment: .leading, spacing: AppSpacing.micro) {
                        Text(challenge.activityType)
                            .font(.title2.bold())
                        Text("Target · \(challenge.quantityLabel)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                    rejectionStrip

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
                    Label(
                        CrewEdgeCopy.scheduledStartsLabel(
                            startDate: challenge.startDate,
                            now: store.environment.clock.now
                        ),
                        systemImage: "calendar.badge.clock"
                    )
                    .font(.title2.bold())
                    Text(challenge.title)
                        .font(.title3.bold())
                    Text(CrewEdgeCopy.scheduledSupportingCopy(
                        title: challenge.activityType,
                        durationDays: RoundProgress.dayOfRound(challenge: challenge, now: challenge.startDate)?.total
                            ?? max(1, (Calendar.current.dateComponents([.day], from: challenge.startDate, to: challenge.endDate).day ?? 0) + 1)
                    ))
                        .foregroundStyle(AppColors.secondaryInk)

                case .closed:
                    Label(FriendFacingCopy.missedWindow, systemImage: "lock.fill")
                        .font(.title2.bold())
                    Text("You can check in again on the next scheduled day.")
                        .foregroundStyle(AppColors.secondaryInk)
                    rejectionStrip
                }

                MetricShelf(items: metricShelfItems(for: challenge, state: requirementState))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary(challenge, state: requirementState))
    }

    private func metricShelfItems(for challenge: CahootsChallenge, state: TodayRequirementState) -> [MetricShelfItem] {
        let streak = currentEntry?.currentStreak ?? 0
        let rank = store.currentRank.map { "#\($0)" } ?? "—"
        let third: MetricShelfItem
        if state == .complete {
            third = MetricShelfItem(id: "points", value: "\(store.todayPoints)", caption: String(localized: "points"))
        } else {
            third = MetricShelfItem(
                id: "recovery",
                value: "\(store.remainingRecoveryDays)",
                caption: String(localized: "recovery left")
            )
        }
        return [
            MetricShelfItem(id: "rank", value: rank, caption: String(localized: "rank")),
            MetricShelfItem(id: "streak", value: "\(streak)", caption: String(localized: "day streak")),
            third,
        ]
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

    /// Quantity/clip detail for peers after the viewer can reveal — rail already shows full roster status.
    private var revealedPeerDetailStrip: some View {
        let peers = store.todayPeerCheckIns
        return Group {
            if store.canRevealTodayQuantities, !peers.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Crew check-ins")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryInk)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.small) {
                            ForEach(peers) { submission in
                                if let user = store.snapshot?.users.first(where: { $0.id == submission.userID }) {
                                    peerCheckInCell(user: user, submission: submission)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func peerCheckInCell(user: CahootsUser, submission: Submission) -> some View {
        let clip = PeerClipPlayButton.playableClip(from: submission)
        let content = VStack(spacing: 4) {
            AvatarView(user: user, size: 40)
            Text(user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName)
                .font(.caption2.bold())
                .lineLimit(1)
            if clip != nil {
                HStack(spacing: 2) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                    Text("Play")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(AppColors.ink)
            }
            if let challenge = store.currentChallenge {
                Text("\(Int(submission.quantity))")
                    .font(.caption.bold().monospacedDigit())
                Text(challenge.measurementType.shortName)
                    .font(.caption2)
                    .foregroundStyle(AppColors.secondaryInk)
            }
        }
        .frame(width: 80)
        .padding(.vertical, 4)

        if let clip {
            PeerClipPlaybackTrigger(
                clip: clip,
                accessibilityPlayLabel: String(localized: "Play \(user.displayName)’s clip")
            ) {
                content
            }
        } else {
            content
        }
    }

    private func handleCrewMemberTap(_ entry: TodayMemberStatusEntry) {
        clipUnlockHint = nil
        guard entry.status == .done, !entry.isCurrentUser else { return }

        if store.canRevealTodayQuantities {
            if let submission = store.todayPeerCheckIns.first(where: { $0.userID == entry.user.id }),
               let clip = PeerClipPlayButton.playableClip(from: submission) {
                railPlaybackClip = clip
            } else {
                clipUnlockHint = String(localized: "No clip available for \(entry.user.displayName).")
            }
            return
        }

        let firstName = entry.user.displayName.split(separator: " ").first.map(String.init) ?? entry.user.displayName
        if let group = store.currentGroup {
            clipUnlockHint = FriendPostedCopy.lockScreenBody(
                actorName: firstName,
                groupName: group.name,
                viewerHasCompleted: false
            )
        } else {
            clipUnlockHint = String(localized: "\(firstName) posted — log yours to see it.")
        }
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
        VStack(spacing: AppSpacing.small) {
            Button(hasPendingFinishClip ? "Finish workout" : "Log workout") { showCheckIn = true }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("today.logWorkout")
            if store.remainingRecoveryDays > 0 {
                Button("Need a rest day?") {
                    confirmRecovery = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("Need a rest day?")
                .accessibilityIdentifier("today.rest")
            }
        }
    }

    @ViewBuilder
    private var pendingSyncCard: some View {
        let pending = store.currentPendingOperations
        if !pending.isEmpty {
            let failed = store.hasFailedPendingSync
            let detail = store.currentPendingSyncError
                ?? (failed
                    ? FriendFacingCopy.syncExplanation(for: .failed)
                    : FriendFacingCopy.syncExplanation(for: .waiting))
            CahootsCard {
                AdaptiveStack(spacing: AppSpacing.medium) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.title2).foregroundStyle(AppColors.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(FriendFacingCopy.savedOnPhone).font(.headline)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Retry") { Task { await store.retryPending() } }
                        .font(.subheadline.bold())
                        .disabled(store.isOffline)
                        .accessibilityIdentifier("today.syncRetry")
                }
            }
        }
    }

    @ViewBuilder
    private var rejectionStrip: some View {
        if let rejected = store.currentRejectedSubmissions.first {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.body.bold())
                    .foregroundStyle(AppColors.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text(FriendFacingCopy.syncLabel(for: .rejected))
                        .font(.subheadline.weight(.semibold))
                    Text(rejected.rejectionReason ?? FriendFacingCopy.syncExplanation(for: .rejected))
                        .font(.caption)
                        .foregroundStyle(AppColors.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.danger.opacity(0.16), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
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
        // Check-in only after reconcile has activated the challenge (start date met).
        if challenge.status != .active { return .upcoming }
        guard ScheduleEngine.isScheduled(on: now, challenge: challenge) else { return .restDay }
        if store.todayPoints > 0 { return .complete }
        if store.recoveryUsedToday { return .recovery }
        if let deadline = ScheduleEngine.deadline(for: now, challenge: challenge), now > deadline { return .closed }
        return .scheduledIncomplete
    }

    private func statusText(_ state: TodayRequirementState, challenge: CahootsChallenge) -> String {
        switch state {
        case .scheduledIncomplete: "Ready"
        case .complete: "Complete"
        case .restDay: "Rest day"
        case .recovery: "Recovery"
        case .upcoming:
            CrewEdgeCopy.scheduledStartsLabel(
                startDate: challenge.startDate,
                now: store.environment.clock.now
            )
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
