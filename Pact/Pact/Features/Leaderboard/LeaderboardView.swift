import SwiftUI

enum LeaderboardScope: String, CaseIterable, Identifiable {
    case round = "Current round"
    case allTime = "All-time"
    var id: String { rawValue }
}

struct CrewStandingsSection: View {
    @Environment(AppStore.self) private var store
    @State private var scope: LeaderboardScope = .round
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var entries: [LeaderboardEntry] { scope == .round ? store.currentLeaderboard : store.allTimeLeaderboard }

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            RoundSectionHeader(title: "Standings")
            Picker("Leaderboard period", selection: $scope) {
                ForEach(LeaderboardScope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("leaderboard.scope")

            if entries.isEmpty {
                Text("Check-ins will appear here once this round begins.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if entries.count >= 3 && !dynamicTypeSize.isAccessibilitySize {
                    podium(Array(entries.prefix(3)))
                    if let currentIndex = entries.firstIndex(where: { $0.user.id == store.currentUser?.id }), currentIndex >= 3 {
                        RoundCard {
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

                let visibleEntries = dynamicTypeSize.isAccessibilitySize ? entries : Array(entries.dropFirst(min(3, entries.count)))
                if !visibleEntries.isEmpty {
                    RoundCard {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleEntries) { entry in
                                let index = entries.firstIndex(where: { $0.id == entry.id }) ?? 0
                                LeaderboardRow(
                                    rank: index + 1,
                                    entry: entry,
                                    isCurrentUser: entry.user.id == store.currentUser?.id,
                                    isProvisional: provisional(entry)
                                )
                                if entry.id != visibleEntries.last?.id { Divider().padding(.leading, 58) }
                            }
                        }
                    }
                }
            }

            if let previous = store.currentRoundResults.first {
                NavigationLink { RoundResultsView(summary: previous) } label: {
                    RoundCard {
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

struct PodiumCard: View {
    let entry: LeaderboardEntry
    let rank: Int
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            ZStack(alignment: .topTrailing) {
                AvatarView(user: entry.user, size: rank == 1 ? 58 : 48)
                Text("\(rank)")
                    .font(.caption.bold())
                    .frame(width: 24, height: 24)
                    .background(rank == 1 ? AppColors.accent : AppColors.ink, in: Circle())
                    .foregroundStyle(.white)
                    .offset(x: 5, y: -4)
            }
            Text(entry.user.id == store.currentUser?.id ? "You" : entry.user.displayName)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
            Text(entry.points.formatted()).font(.headline.monospacedDigit())
            Text("points")
                .font(.caption2)
                .foregroundStyle(rank == 1 ? Color(uiColor: .systemBackground).opacity(0.7) : AppColors.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, rank == 1 ? AppSpacing.large : AppSpacing.medium)
        .background(rank == 1 ? AppColors.ink : AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .foregroundStyle(rank == 1 ? Color(uiColor: .systemBackground) : AppColors.ink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(entry.user.displayName), \(entry.points) points")
        .accessibilityIdentifier(entry.user.id == store.currentUser?.id ? "leaderboard.currentUser" : "leaderboard.podium.\(rank)")
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isCurrentUser: Bool
    var isProvisional = false

    var body: some View {
        AdaptiveStack(spacing: AppSpacing.small) {
            Text("\(rank)").font(.headline.monospacedDigit()).frame(width: 28)
            AvatarView(user: entry.user, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(isCurrentUser ? "You" : entry.user.displayName).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                Text("\(entry.completedRequirements) \(entry.completedRequirements == 1 ? "completion" : "completions") · \(entry.currentStreak)-day streak")
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryInk)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(entry.points.formatted()) pts\(isProvisional ? " · \(FriendFacingCopy.savedOnPhone.lowercased())" : "")")
                    .font(.headline.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                if let previous = entry.previousRank {
                    let movement = previous - rank
                    Label(movement == 0 ? "—" : "\(abs(movement))", systemImage: movement > 0 ? "arrow.up" : movement < 0 ? "arrow.down" : "minus")
                        .font(.caption2.bold())
                        .foregroundStyle(AppColors.secondaryInk)
                        .accessibilityLabel(movement == 0 ? "No rank change" : "Moved \(movement > 0 ? "up" : "down") \(abs(movement)) places")
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isCurrentUser ? 8 : 0)
        .background(isCurrentUser ? AppColors.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(isCurrentUser ? "You" : entry.user.displayName), \(entry.points) points\(isProvisional ? ", saved on this phone" : ""), \(entry.completedRequirements) requirements completed, \(entry.currentStreak) day streak")
        .accessibilityIdentifier(isCurrentUser ? "leaderboard.currentUser" : "leaderboard.row.\(rank)")
    }
}

struct RoundResultsView: View {
    @Environment(AppStore.self) private var store
    let summary: RoundResult
    @State private var showBuilder = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.large) {
                VStack(spacing: AppSpacing.small) {
                    Image(systemName: "trophy.fill").font(.system(size: 54)).foregroundStyle(AppColors.warning)
                    Text(summary.winnerName).font(.largeTitle.bold())
                    Text("won \(summary.title)").foregroundStyle(AppColors.secondaryInk)
                }
                RoundCard(elevated: true) {
                    VStack(spacing: AppSpacing.medium) {
                        ForEach(Array(summary.topThree.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(rank: index + 1, entry: entry, isCurrentUser: entry.user.id == store.currentUser?.id)
                        }
                    }
                }
                AdaptiveStack(spacing: AppSpacing.small) {
                    MetricTile(value: summary.totalCompletions.formatted(), label: "group completions", symbol: "checkmark.circle.fill")
                    MetricTile(value: "\(summary.personalBest)", label: "personal best", symbol: "star.fill")
                }
                RoundCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        RoundSectionHeader(title: "Everyone’s round")
                        ForEach(summary.members) { member in
                            AdaptiveStack(spacing: AppSpacing.small) {
                                AvatarView(user: member.user, size: 36)
                                Text(member.user.displayName).font(.subheadline.bold())
                                Spacer()
                                Text("\(member.completionRate)%").font(.headline.monospacedDigit())
                                    .accessibilityLabel("\(member.completionRate) percent complete")
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
        }
        .navigationTitle("Round results")
        .navigationBarTitleDisplayMode(.inline)
        .roundPage()
        .sheet(isPresented: $showBuilder) { ChallengeBuilderView() }
    }
}
