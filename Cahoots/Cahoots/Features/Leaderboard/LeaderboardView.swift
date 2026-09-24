import SwiftUI

enum LeaderboardScope: String, CaseIterable, Identifiable {
    case round = "Current round"
    case allTime = "All-time"
    var id: String { rawValue }
}

/// Pure layout helpers so small crews (1–2 members) still render standings rows.
enum LeaderboardStandingsLayout {
    static func showsPodium(entryCount: Int, isAccessibilitySize: Bool) -> Bool {
        entryCount >= 3 && !isAccessibilitySize
    }

    static func showsDuel(entryCount: Int, isAccessibilitySize: Bool) -> Bool {
        entryCount == 2 && !isAccessibilitySize
    }

    static func listEntries<Entry>(from entries: [Entry], showPodium: Bool, showDuel: Bool = false) -> [Entry] {
        if showDuel { return [] }
        return showPodium ? Array(entries.dropFirst(3)) : entries
    }
}

struct LeaderboardView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppSpacing.large) {
                    AdaptiveStack(spacing: AppSpacing.small) {
                        Text("Leaderboard")
                            .font(.largeTitle.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: AppSpacing.small)
                        GroupSwitcherMenu()
                            .layoutPriority(-1)
                    }

                    CrewStandingsSection()
                }
                .padding(AppSpacing.page)
                .cahootsTabBarClearance()
            }
            .refreshable { await store.refresh() }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .roundPage()
        }
        .id(store.currentGroup?.id)
    }
}

struct CrewStandingsSection: View {
    @Environment(AppStore.self) private var store
    @State private var scope: LeaderboardScope = .round
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var entries: [LeaderboardEntry] { scope == .round ? store.currentLeaderboard : store.allTimeLeaderboard }
    private var showPodium: Bool {
        LeaderboardStandingsLayout.showsPodium(
            entryCount: entries.count,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
    }
    private var showDuel: Bool {
        LeaderboardStandingsLayout.showsDuel(
            entryCount: entries.count,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
    }
    private var listEntries: [LeaderboardEntry] {
        LeaderboardStandingsLayout.listEntries(from: entries, showPodium: showPodium, showDuel: showDuel)
    }
    private var allPointsZero: Bool {
        !entries.isEmpty && entries.allSatisfy { $0.points == 0 }
    }

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            LeaderboardScopeControl(selection: $scope)
                .accessibilityIdentifier("leaderboard.scope")

            if let context = roundContextLine {
                Text(context)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if allPointsZero {
                Text("Round just started — first check-in takes the lead.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if entries.isEmpty {
                CahootsCard {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text("No standings yet")
                            .font(.headline)
                        Text(emptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                }
            } else {
                if showDuel {
                    DuelStandingsView(
                        first: entries[0],
                        second: entries[1],
                        currentUserID: store.currentUser?.id,
                        firstProvisional: provisional(entries[0]),
                        secondProvisional: provisional(entries[1])
                    )
                }

                if showPodium {
                    podium(Array(entries.prefix(3)))
                    if let currentIndex = entries.firstIndex(where: { $0.user.id == store.currentUser?.id }), currentIndex >= 3 {
                        CahootsCard {
                            VStack(alignment: .leading, spacing: AppSpacing.small) {
                                Text("Your position").font(.caption.weight(.semibold)).foregroundStyle(AppColors.secondaryInk)
                                LeaderboardRow(
                                    rank: currentIndex + 1,
                                    entry: entries[currentIndex],
                                    isCurrentUser: true,
                                    isProvisional: provisional(entries[currentIndex])
                                )
                            }
                        }
                    }
                }

                if !listEntries.isEmpty {
                    CahootsCard {
                        LazyVStack(spacing: 0) {
                            ForEach(listEntries) { entry in
                                let index = entries.firstIndex(where: { $0.id == entry.id }) ?? 0
                                LeaderboardRow(
                                    rank: index + 1,
                                    entry: entry,
                                    isCurrentUser: entry.user.id == store.currentUser?.id,
                                    isProvisional: provisional(entry)
                                )
                                if entry.id != listEntries.last?.id { Divider().padding(.leading, 64) }
                            }
                        }
                    }
                }
            }

            if let previous = store.currentCahootsResults.first {
                NavigationLink { ChallengeResultsView(summary: previous) } label: {
                    CahootsCard {
                        HStack {
                            Image(systemName: "flag.checkered").font(.title2)
                            VStack(alignment: .leading) {
                                Text("Previous round").font(.headline)
                                Text(previous.title).font(.subheadline).foregroundStyle(AppColors.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var roundContextLine: String? {
        guard let challenge = store.currentChallenge else { return nil }
        if scope == .allTime {
            return String(localized: "All-time · \(challenge.quantityLabel) \(challenge.activityType)")
        }
        let day = RoundProgress.dayLabel(challenge: challenge, now: store.environment.clock.now)
        if let day {
            return "\(challenge.quantityLabel) \(challenge.activityType) · \(day)"
        }
        return "\(challenge.quantityLabel) \(challenge.activityType)"
    }

    private var emptyMessage: String {
        if store.currentChallenge == nil {
            String(localized: "Start a round with your crew and standings will show up here.")
        } else {
            String(localized: "Check-ins will appear here once this round begins.")
        }
    }

    private func podium(_ entries: [LeaderboardEntry]) -> some View {
        HStack(alignment: .bottom, spacing: AppSpacing.small) {
            PodiumCard(entry: entries[1], rank: 2)
            PodiumCard(entry: entries[0], rank: 1)
            PodiumCard(entry: entries[2], rank: 3)
        }
        .accessibilityElement(children: .contain)
    }

    private func provisional(_ entry: LeaderboardEntry) -> Bool {
        scope == .round && entry.user.id == store.currentUser?.id && store.hasProvisionalLeaderboardPoints
    }
}

/// Chip-track scope control — matches crew switcher capsules instead of stock segmented chrome.
struct LeaderboardScopeControl: View {
    @Binding var selection: LeaderboardScope
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LeaderboardScope.allCases) { scope in
                let isSelected = selection == scope
                Button {
                    guard selection != scope else { return }
                    if reduceMotion {
                        selection = scope
                    } else {
                        withAnimation(AppMotion.responsive) { selection = scope }
                    }
                } label: {
                    Text(scope.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? AppColors.onInk : AppColors.ink.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(AppColors.ink)
                                    .matchedGeometryEffect(id: "leaderboard.scope.selection", in: selectionNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppColors.chip, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Leaderboard period")
    }
}

struct PodiumCard: View {
    let entry: LeaderboardEntry
    let rank: Int
    @Environment(AppStore.self) private var store

    private var isFirst: Bool { rank == 1 }
    /// Explicit ink/onInk for #1 (emphasis). Ranks 2–3 use charcoal with light labels —
    /// do not drive colors via `.environment(\.colorScheme)` because `AppColors` follows the window trait.
    private var fill: Color { isFirst ? AppColors.ink : AppColors.card }
    private var label: Color { isFirst ? AppColors.onInk : Color.white }
    private var secondaryLabel: Color { isFirst ? AppColors.onInk.opacity(0.7) : Color.white.opacity(0.65) }

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            ZStack(alignment: .topTrailing) {
                AvatarView(user: entry.user, size: isFirst ? 58 : 48)
                    .overlay {
                        if entry.user.id == store.currentUser?.id {
                            Circle().stroke(fill, lineWidth: 3)
                        }
                    }
                Text("\(rank)")
                    .font(.caption.bold())
                    .frame(width: 24, height: 24)
                    .background(isFirst ? AppColors.onInk : AppColors.ink, in: Circle())
                    .foregroundStyle(isFirst ? AppColors.ink : AppColors.onInk)
                    .offset(x: 5, y: -4)
            }
            Text(entry.user.id == store.currentUser?.id ? "You" : entry.user.displayName)
                .font(.subheadline.bold())
                .foregroundStyle(label)
                .multilineTextAlignment(.center)
            Text(entry.points.formatted())
                .font(.headline.monospacedDigit())
                .foregroundStyle(label)
            Text("points")
                .font(.caption2)
                .foregroundStyle(secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isFirst ? AppSpacing.large : AppSpacing.medium)
        .background(fill, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(entry.user.displayName), \(entry.points) points")
        .accessibilityIdentifier(entry.user.id == store.currentUser?.id ? "leaderboard.currentUser" : "leaderboard.podium.\(rank)")
    }
}

struct DuelStandingsView: View {
    let first: LeaderboardEntry
    let second: LeaderboardEntry
    let currentUserID: UUID?
    var firstProvisional = false
    var secondProvisional = false

    var body: some View {
        CahootsCard(elevated: true) {
            HStack(alignment: .center, spacing: AppSpacing.small) {
                duelColumn(entry: first, rank: 1, isProvisional: firstProvisional)
                gapLabel
                    .frame(width: 72)
                duelColumn(entry: second, rank: 2, isProvisional: secondProvisional)
            }
        }
    }

    private var gapLabel: some View {
        let gap = abs(first.points - second.points)
        return VStack(spacing: AppSpacing.micro) {
            Text("vs")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.secondaryInk)
            if gap == 0 {
                Text("Tied")
                    .font(.subheadline.weight(.bold))
            } else if let currentUserID {
                let you = first.user.id == currentUserID ? first : second
                let them = first.user.id == currentUserID ? second : first
                let ahead = you.points >= them.points
                Text(ahead
                      ? String(localized: "\(gap) pts ahead")
                      : String(localized: "\(gap) pts behind"))
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.secondaryInk)
            } else {
                Text("\(gap) pts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryInk)
            }
        }
    }

    private func duelColumn(entry: LeaderboardEntry, rank: Int, isProvisional: Bool) -> some View {
        let isYou = entry.user.id == currentUserID
        return VStack(spacing: AppSpacing.small) {
            Text("#\(rank)")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.secondaryInk)
            AvatarView(user: entry.user, size: 64)
                .overlay {
                    Circle()
                        .stroke(isYou ? AppColors.page : Color.clear, lineWidth: 3)
                }
            Text(isYou ? String(localized: "You") : entry.user.displayName)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("\(entry.points.formatted()) pts\(isProvisional ? " · \(FriendFacingCopy.savedOnPhone.lowercased())" : "")")
                .font(.headline.monospacedDigit())
                .multilineTextAlignment(.center)
            Text("\(entry.currentStreak)-day streak")
                .font(.caption2)
                .foregroundStyle(AppColors.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.small)
        .background(
            isYou ? AppColors.page.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(isYou ? "You" : entry.user.displayName), \(entry.points) points")
        .accessibilityIdentifier(isYou ? "leaderboard.currentUser" : "leaderboard.row.\(rank)")
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isCurrentUser: Bool
    var isProvisional = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                compactLayout
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, isCurrentUser ? 8 : 0)
        .background(isCurrentUser ? AppColors.page.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(isCurrentUser ? "You" : entry.user.displayName), \(entry.points) points\(isProvisional ? ", saved on this phone" : ""), \(entry.completedRequirements) requirements completed, \(entry.currentStreak) day streak")
        .accessibilityIdentifier(isCurrentUser ? "leaderboard.currentUser" : "leaderboard.row.\(rank)")
    }

    private var compactLayout: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(rank)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppColors.secondaryInk)
                .frame(width: 18, alignment: .leading)
            avatar
            VStack(alignment: .leading, spacing: 1) {
                Text(isCurrentUser ? "You" : entry.user.displayName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(pointsLine)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                rankMovement
            }
            .layoutPriority(1)
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(rank)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 28, alignment: .leading)
                avatar
                Text(isCurrentUser ? "You" : entry.user.displayName)
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(detailLine)
                .font(.body)
                .foregroundStyle(AppColors.secondaryInk)
            Text(pointsLine)
                .font(.headline.monospacedDigit())
            rankMovement
        }
    }

    private var avatar: some View {
        AvatarView(user: entry.user, size: 36)
            .overlay {
                if isCurrentUser {
                    Circle().stroke(AppColors.page, lineWidth: 2)
                }
            }
    }

    private var detailLine: String {
        "\(entry.completedRequirements) \(entry.completedRequirements == 1 ? "completion" : "completions") · \(entry.currentStreak)-day streak"
    }

    private var pointsLine: String {
        "\(entry.points.formatted()) pts\(isProvisional ? " · \(FriendFacingCopy.savedOnPhone.lowercased())" : "")"
    }

    @ViewBuilder
    private var rankMovement: some View {
        if let previous = entry.previousRank {
            let movement = previous - rank
            if movement == 0 {
                Text("Same")
                    .font(.caption2.bold())
                    .foregroundStyle(AppColors.secondaryInk)
                    .accessibilityLabel("No rank change")
            } else {
                Label("\(abs(movement))", systemImage: movement > 0 ? "arrow.up" : "arrow.down")
                    .font(.caption2.bold())
                    .foregroundStyle(movement > 0 ? AppColors.success : AppColors.secondaryInk)
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("Moved \(movement > 0 ? "up" : "down") \(abs(movement)) places")
            }
        }
    }
}

struct ChallengeResultsView: View {
    @Environment(AppStore.self) private var store
    let summary: CahootsResult
    @State private var showBuilder = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.large) {
                VStack(spacing: AppSpacing.small) {
                    Image(systemName: "trophy.fill").font(.system(size: 54)).foregroundStyle(AppColors.warning)
                    Text(summary.winnerName).font(.largeTitle.bold())
                    Text("won \(summary.title)").foregroundStyle(AppColors.secondaryInk)
                }
                CahootsCard(elevated: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(summary.topThree.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(rank: index + 1, entry: entry, isCurrentUser: entry.user.id == store.currentUser?.id)
                            if index < summary.topThree.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                }
                AdaptiveStack(spacing: AppSpacing.small) {
                    MetricTile(value: summary.totalCompletions.formatted(), label: "group completions", symbol: "checkmark.circle.fill")
                    MetricTile(value: "\(summary.personalBest)", label: "personal best", symbol: "star.fill")
                }
                CahootsCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        CahootsSectionHeader(title: "Everyone’s round")
                        ForEach(summary.members) { member in
                            HStack(spacing: 10) {
                                AvatarView(user: member.user, size: 32)
                                Text(member.user.displayName)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(
                                    (Double(member.completionRate) / 100),
                                    format: .percent.precision(.fractionLength(0))
                                )
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .layoutPriority(1)
                                .accessibilityLabel(
                                    "\((Double(member.completionRate) / 100).formatted(.percent.precision(.fractionLength(0)))) complete"
                                )
                            }
                        }
                    }
                }
                Text("Every member’s consistency helped finish the round.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryInk)
                    .multilineTextAlignment(.center)
                Button("Start another round", systemImage: "flag.badge.plus") { showBuilder = true }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(AppSpacing.page)
            .cahootsTabBarClearance()
        }
        .navigationTitle("Challenge results")
        .cahootsDrillInBar()
        .roundPage()
        .sheet(isPresented: $showBuilder) { ChallengeBuilderView() }
    }
}
