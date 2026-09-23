import SwiftUI

enum CrewDestination: Hashable {
    case invite, members, settings
}

struct GroupView: View {
    @Environment(AppStore.self) private var store
    @State private var path = NavigationPath()
    @State private var showBuilder = false
    @State private var showVote = ProcessInfo.processInfo.arguments.contains("-showVote")
    @State private var showGroupSwitcher = false
    @State private var showCreateGroup = false
    @State private var showJoinGroup = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: AppSpacing.large) {
                    HStack(alignment: .center, spacing: AppSpacing.small) {
                        Text("Crew")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: AppSpacing.small)
                        Menu {
                            Button("Members", systemImage: "person.3") { path.append(CrewDestination.members) }
                            if canEditSettings {
                                Button("Group settings", systemImage: "gearshape") { path.append(CrewDestination.settings) }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body.bold())
                                .foregroundStyle(AppColors.ink)
                                .frame(width: 44, height: 44)
                                .environment(\.colorScheme, .dark)
                                .background(AppColors.raised, in: Circle())
                                .shadow(color: AppShadow.color, radius: 8, y: 3)
                        }
                        .accessibilityLabel("Group actions")
                        .accessibilityIdentifier("group.menu")
                    }
                    groupHeader
                    if let challenge = store.currentChallenge, challenge.status == .active {
                        crewShowedUpCard
                    }
                    if let challenge = store.currentChallenge { activeChallengeCard(challenge) }
                    proposeAccessCard
                    if let proposal = store.currentProposal { proposalCard(proposal) }
                    else if let proposal = store.latestFailedProposal { failedProposalCard(proposal) }
                    membersCard
                    activityCard
                }
                .padding(AppSpacing.page)
            }
            .refreshable { await store.refresh() }
            .navigationTitle("Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showVote) {
                if let proposalID = store.pendingOpenVoteProposalID
                    ?? store.currentProposal?.id
                    ?? store.latestFailedProposal?.id {
                    VotingView(proposalID: proposalID)
                }
            }
            .navigationDestination(for: CrewDestination.self) { destination in
                switch destination {
                case .invite:
                    if let group = store.currentGroup,
                       let invite = store.snapshot?.invites.first(where: {
                           $0.groupID == group.id && $0.revokedAt == nil && $0.expiresAt > .now
                       }) {
                        InviteShareView(group: group, invite: invite) { path.removeLast() }
                            .navigationTitle("Invite")
                            .navigationBarTitleDisplayMode(.inline)
                    } else {
                        ContentUnavailableView {
                            Label("No active invitation", systemImage: "link.badge.plus")
                        } description: {
                            Text("Generate a new private invitation from Group settings.")
                        } actions: {
                            Button("Open settings") {
                                path.removeLast()
                                path.append(CrewDestination.settings)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                case .members:
                    MemberManagementView()
                case .settings:
                    GroupSettingsView()
                }
            }
            .roundPage()
            .sheet(isPresented: $showBuilder) { ChallengeBuilderView() }
            .groupSwitcherPresentation(
                isPresented: $showGroupSwitcher,
                showCreate: $showCreateGroup,
                showJoin: $showJoinGroup
            )
        }
        .id(store.currentGroup?.id)
        .onChange(of: store.selectedTab) { _, newTab in
            guard newTab != 1 else { return }
            path = NavigationPath()
            showBuilder = false
            showVote = false
        }
        .onChange(of: store.presentOpenVote) { _, shouldPresent in
            guard shouldPresent else { return }
            showVote = store.pendingOpenVoteProposalID != nil
                || store.currentProposal != nil
                || store.latestFailedProposal != nil
            store.consumePresentOpenVote()
        }
        .onChange(of: store.presentInvite) { _, shouldPresent in
            guard shouldPresent else { return }
            showVote = false
            path.append(CrewDestination.invite)
            store.consumePresentInvite()
        }
        .onAppear {
            if store.presentOpenVote {
                showVote = store.pendingOpenVoteProposalID != nil
                    || store.currentProposal != nil
                    || store.latestFailedProposal != nil
                store.consumePresentOpenVote()
            }
            if store.presentInvite {
                path.append(CrewDestination.invite)
                store.consumePresentInvite()
            }
        }
    }

    private var canSwitchGroups: Bool {
        store.activeGroups.count > 1
    }

    private var groupHeader: some View {
        AdaptiveStack(spacing: AppSpacing.medium) {
            groupIdentity
            Spacer(minLength: 0)
            if store.currentMembership.map({ GroupPermissionRules.canManageInvites($0.role) }) == true {
                Button("Invite") { path.append(CrewDestination.invite) }
                    .font(.subheadline.bold())
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var groupIdentity: some View {
        let content = HStack(alignment: .center, spacing: AppSpacing.medium) {
            Text(store.currentGroup?.emoji ?? "⚡️").font(.largeTitle)
            VStack(alignment: .leading, spacing: AppSpacing.micro) {
                HStack(alignment: .center, spacing: AppSpacing.small) {
                    Text(store.currentGroup?.name ?? "Crew")
                        .font(.title2.bold())
                        .foregroundStyle(AppColors.ink)
                        .accessibilityIdentifier("group.header.name")
                    if canSwitchGroups {
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(AppColors.secondaryInk)
                            .accessibilityHidden(true)
                    }
                }
                Text("\(store.groupMembers.count) members · Private")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryInk)
            }
        }

        if canSwitchGroups {
            Button {
                showGroupSwitcher = true
            } label: {
                content
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Switch crew. Current crew \(store.currentGroup?.name ?? "none")")
            .accessibilityIdentifier("group.header.switcher")
        } else {
            content
        }
    }

    @ViewBuilder
    private var proposeAccessCard: some View {
        let demoted = store.currentChallenge != nil
        if store.currentProposal == nil, canPropose {
            Button {
                showBuilder = true
            } label: {
                proposeRow(
                    demoted: demoted,
                    symbol: "flag.badge.ellipsis",
                    title: store.currentChallenge == nil ? "Start a round" : "Propose a round",
                    subtitle: "Set a goal for this crew to vote on or begin."
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("group.propose")
        }
    }

    private func proposeRow(demoted: Bool, symbol: String, title: String, subtitle: String) -> some View {
        let content = HStack(spacing: AppSpacing.medium) {
            Image(systemName: symbol)
                .font(demoted ? .body.bold() : .title2)
                .foregroundStyle(demoted ? AppColors.secondaryInk : AppColors.accent)
                .frame(width: demoted ? 28 : nil)
            VStack(alignment: .leading, spacing: AppSpacing.micro) {
                Text(title)
                    .font(demoted ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(AppColors.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryInk)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.secondaryInk)
        }

        return Group {
            if demoted {
                content
                    .padding(.vertical, AppSpacing.small)
                    .padding(.horizontal, AppSpacing.medium)
                    .background(AppColors.chip, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            } else {
                CahootsCard { content }
            }
        }
    }

    private var crewShowedUpCard: some View {
        let entries = store.todayMemberStatuses
        let showedUp = entries.filter { $0.status == .done || $0.status == .rest }.count
        let total = entries.count
        let headline: String = {
            if total == 0 { return String(localized: "Waiting on the crew") }
            if showedUp == total { return String(localized: "Everyone showed up") }
            return String(localized: "\(showedUp) of \(total) showed up")
        }()
        let detail = CrewAccountabilityCopy.checkInSummary(entries: entries)
            ?? String(localized: "Private crew progress for today.")

        return CahootsCard(emphasis: true) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(String(localized: "Crew today"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.onInk.opacity(0.7))
                Text(headline)
                    .font(.title2.bold())
                    .foregroundStyle(AppColors.onInk)
                Text(detail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.onInk.opacity(0.72))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("group.crewShowedUp")
    }

    private func activeChallengeCard(_ challenge: CahootsChallenge) -> some View {
        let dayLabel = RoundProgress.dayLabel(challenge: challenge, now: store.environment.clock.now)
        return NavigationLink {
            ChallengeDetailsView(challenge: challenge)
        } label: {
            CahootsCard(elevated: true) {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    CahootsSectionHeader(title: challenge.status == .scheduled ? "Next round" : "Current round")
                    AdaptiveStack(spacing: AppSpacing.small) {
                        Text(challenge.quantityLabel).font(AppTypography.heroMetric)
                        Text(challenge.activityType).font(.title2.bold())
                    }
                    if challenge.status == .scheduled {
                        Text(CrewEdgeCopy.scheduledStartsLabel(
                            startDate: challenge.startDate,
                            now: store.environment.clock.now
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryInk)
                    } else if let dayLabel {
                        Text(dayLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                    Text(challenge.title).font(.headline)
                    AdaptiveStack(spacing: AppSpacing.small) {
                        StatusPill(
                            text: challenge.status == .scheduled
                                ? String(localized: "Scheduled")
                                : challenge.status.rawValue.capitalized,
                            kind: challenge.status == .scheduled ? .pending : .positive
                        )
                        if challenge.status == .scheduled {
                            Text(challenge.startDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryInk)
                        } else {
                            Text("Ends \(challenge.endDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(AppColors.secondaryInk)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func proposalCard(_ proposal: ChallengeProposal) -> some View {
        NavigationLink {
            VotingView(proposalID: proposal.id)
        } label: {
            CahootsCard {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    HStack { StatusPill(text: "Proposal · Vote open", kind: .pending); Spacer(); Image(systemName: "chevron.right") }
                    Text(proposal.title).font(.title2.bold()).foregroundStyle(AppColors.ink)
                    Text("\(store.snapshot?.votes.filter { $0.proposalID == proposal.id }.count ?? 0) of \(proposal.eligibleVoterIDs.count) voted")
                        .font(.subheadline).foregroundStyle(AppColors.secondaryInk)
                    if let summary = CrewAccountabilityCopy.voteSummary(
                        eligible: store.groupMembers.filter { proposal.eligibleVoterIDs.contains($0.id) },
                        votedUserIDs: Set((store.snapshot?.votes ?? []).filter { $0.proposalID == proposal.id }.map(\.userID)),
                        currentUserID: store.currentUser?.id ?? UUID()
                    ) {
                        Text(summary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                    Text(VotingWindowCopy.statusLine(endsAt: proposal.votingEndsAt))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryInk)
                    Text("Vote now").font(.headline).foregroundStyle(AppColors.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("group.openVote")
    }

    private func failedProposalCard(_ proposal: ChallengeProposal) -> some View {
        NavigationLink { VotingView(proposalID: proposal.id) } label: {
            CahootsCard {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        StatusPill(text: "Vote finished", kind: .negative)
                        Text(proposal.title).font(.headline).foregroundStyle(AppColors.ink)
                        Text(CrewEdgeCopy.failedCrewCardSubtitle)
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(AppColors.secondaryInk)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("group.failedVote")
    }

    private var membersCard: some View {
        CahootsCard {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                CahootsSectionHeader(title: "Members", action: "View all") { path.append(CrewDestination.members) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.medium) {
                        ForEach(store.groupMembers.prefix(8)) { user in
                            VStack(spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    AvatarView(user: user, size: 52)
                                    if user.id == store.currentGroup?.ownerID {
                                        Image(systemName: "crown.fill")
                                            .font(.caption2.bold())
                                            .foregroundStyle(AppColors.warning)
                                            .padding(4)
                                            .background(AppColors.raised, in: Circle())
                                            .offset(x: 4, y: -4)
                                            .accessibilityLabel("Owner")
                                    }
                                }
                                Text(user.id == store.currentUser?.id
                                      ? String(localized: "You")
                                      : (user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName))
                                    .font(.caption2.bold())
                                    .foregroundStyle(AppColors.ink)
                                    .lineLimit(1)
                            }
                            .frame(width: 64)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(user.id == store.currentUser?.id ? "You" : user.displayName)
                        }
                    }
                }
            }
        }
    }

    private var activityCard: some View {
        CahootsCard {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                NavigationLink { ActivityFeedView() } label: {
                    HStack { Text("Recent activity").font(AppTypography.cardTitle); Spacer(); Text("See all").font(.subheadline.bold()) }
                }
                .buttonStyle(.plain)
                ForEach(store.currentActivity.prefix(3)) { item in ActivityRow(item: item) }
            }
        }
    }

    private var canEditSettings: Bool {
        guard let role = store.currentMembership?.role else { return false }
        return GroupPermissionRules.canManageInvites(role)
    }

    private var canPropose: Bool {
        store.currentProposal == nil && !(store.snapshot?.challenges.contains {
            $0.groupID == store.currentGroup?.id && $0.status == .scheduled
        } ?? false)
    }
}
