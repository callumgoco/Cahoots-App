import SwiftUI

struct VotingView: View {
    @Environment(AppStore.self) private var store
    let proposalID: UUID
    @State private var showDuplicate = false
    @State private var showFreshBuilder = false
    @State private var showMemberStatus = false
    @State private var isVoting = false

    private var proposal: ChallengeProposal? { store.snapshot?.proposals.first { $0.id == proposalID } }
    private var votes: [Vote] { store.snapshot?.votes.filter { $0.proposalID == proposalID } ?? [] }
    private var myVote: Vote? { votes.first { $0.userID == store.currentUser?.id } }
    private var proposer: CahootsUser? { guard let id = proposal?.proposedBy else { return nil }; return store.snapshot?.users.first { $0.id == id } }

    var body: some View {
        ScrollView {
            if let proposal {
                VStack(spacing: AppSpacing.large) {
                    summary(proposal)
                    voteProgress(proposal)
                    if proposal.status != .voting { result(proposal) }
                    memberStatus(proposal)
                }
                .padding(AppSpacing.page)
            } else {
                ContentUnavailableView("Proposal unavailable", systemImage: "doc.questionmark", description: Text("It may have been removed or replaced."))
            }
        }
        .navigationTitle("Group vote")
        .navigationBarTitleDisplayMode(.inline)
        .roundPage()
        .safeAreaInset(edge: .bottom) {
            if let proposal,
               proposal.status == .voting,
               proposal.eligibleVoterIDs.contains(store.currentUser?.id ?? UUID()) {
                voteActions
                    .cahootsSheetFooter()
            }
        }
        .task { await store.handleBecameActive() }
        .sheet(isPresented: $showDuplicate) {
            if let proposal {
                ChallengeBuilderView(initialDraft: ProposalDraft(proposal: proposal, earliestStartDate: store.earliestProposalStartDate))
            }
        }
        .sheet(isPresented: $showFreshBuilder) {
            ChallengeBuilderView()
        }
    }

    private func summary(_ proposal: ChallengeProposal) -> some View {
        CahootsCard(elevated: true) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                AdaptiveStack(spacing: AppSpacing.small) {
                    StatusPill(text: proposal.status == .voting ? "Voting open" : proposal.status.rawValue.capitalized, kind: statusKind(proposal))
                    Spacer(minLength: 0)
                    Text(VotingWindowCopy.statusLine(endsAt: proposal.votingEndsAt))
                        .font(.caption.bold())
                        .foregroundStyle(AppColors.secondaryInk)
                        .multilineTextAlignment(.trailing)
                }
                Text(proposal.title).font(.largeTitle.bold())
                AdaptiveStack(spacing: AppSpacing.small) {
                    Text(proposal.minimumQuantity.formatted()).font(AppTypography.heroMetric)
                    Text(proposal.measurementType.displayName).font(.title3.bold())
                }
                Divider()
                Label(scheduleText(proposal), systemImage: "calendar")
                Label("\(proposal.durationDays) days", systemImage: "flag.checkered")
                Label("\(deadlineText(proposal)) · \(proposal.challengeTimezone.replacingOccurrences(of: "_", with: " "))", systemImage: "clock")
                if proposal.recoveryDayAllowance > 0 {
                    let recoveryLabel = proposal.recoveryDayAllowance == 1
                        ? String(localized: "1 recovery day")
                        : String(localized: "\(proposal.recoveryDayAllowance) recovery days")
                    Label(recoveryLabel, systemImage: "moon.zzz")
                }
                if let proposer { Label("Proposed by \(proposer.displayName)", systemImage: "person.fill").foregroundStyle(AppColors.secondaryInk) }
            }
        }
    }

    private func voteProgress(_ proposal: ChallengeProposal) -> some View {
        let accepts = votes.filter { $0.choice == .accept }.count
        let needed = max(2, proposal.eligibleVoterIDs.count / 2 + 1)
        let eligible = store.groupMembers.filter { proposal.eligibleVoterIDs.contains($0.id) }
        let votedIDs = Set(votes.map(\.userID))
        let outstandingSummary = CrewAccountabilityCopy.voteSummary(
            eligible: eligible,
            votedUserIDs: votedIDs,
            currentUserID: store.currentUser?.id ?? UUID()
        )
        return CahootsCard {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                AdaptiveStack(spacing: AppSpacing.small) {
                    Text("\(accepts)").font(AppTypography.heroMetric)
                    Text("of \(needed) accepts needed to pass").font(.headline)
                    Spacer()
                    Text("\(votes.count) of \(proposal.eligibleVoterIDs.count) voted").font(.caption.bold()).foregroundStyle(AppColors.secondaryInk)
                }
                ProgressView(value: Double(votes.count), total: Double(max(1, proposal.eligibleVoterIDs.count))).tint(AppColors.accent)
                if let outstandingSummary {
                    Text(outstandingSummary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.ink)
                        .accessibilityIdentifier("vote.outstandingSummary")
                }
                Text("A tie fails. Voting also closes early after every eligible member votes.").font(.caption).foregroundStyle(AppColors.secondaryInk)
            }
        }
    }

    private func memberStatus(_ proposal: ChallengeProposal) -> some View {
        let eligible = store.groupMembers.filter { proposal.eligibleVoterIDs.contains($0.id) }
        let votedIDs = Set(votes.map(\.userID))
        return CahootsCard {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                if proposal.status == .voting, myVote == nil {
                    let awaiting = eligible.filter { !votedIDs.contains($0.id) }
                    if !awaiting.isEmpty {
                        Text("Still need to vote")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.secondaryInk)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.medium) {
                                ForEach(awaiting) { member in
                                    VStack(spacing: 6) {
                                        AvatarView(user: member, size: 40)
                                        Text(member.id == store.currentUser?.id
                                             ? String(localized: "You")
                                             : (member.displayName.split(separator: " ").first.map(String.init) ?? member.displayName))
                                            .font(.caption2.bold())
                                            .lineLimit(1)
                                    }
                                    .frame(width: 56)
                                }
                            }
                        }
                        .accessibilityIdentifier("vote.awaitingStrip")
                        Text("Choices stay hidden until you vote.")
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                }
                DisclosureGroup("Member status", isExpanded: $showMemberStatus) {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        ForEach(eligible) { member in
                            AdaptiveStack(spacing: AppSpacing.small) {
                                AvatarView(user: member, size: 36)
                                Text(member.displayName).font(.subheadline.weight(.semibold))
                                Spacer(minLength: 0)
                                if myVote != nil, let vote = votes.first(where: { $0.userID == member.id }) {
                                    Label(vote.choice == .accept ? "Accept" : "Reject", systemImage: vote.choice == .accept ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.caption.weight(.semibold)).foregroundStyle(vote.choice == .accept ? AppColors.accent : AppColors.secondaryInk)
                                } else if myVote != nil {
                                    Text("Awaiting").font(.caption).foregroundStyle(AppColors.secondaryInk)
                                } else if votedIDs.contains(member.id) {
                                    Text("Voted").font(.caption).foregroundStyle(AppColors.secondaryInk)
                                } else {
                                    Text("Awaiting").font(.caption).foregroundStyle(AppColors.secondaryInk)
                                }
                            }
                        }
                    }
                    .padding(.top, AppSpacing.medium)
                }
                .font(.headline)
            }
        }
    }

    private var voteActions: some View {
        VStack(spacing: AppSpacing.small) {
            if let myVote {
                Text("You voted \(myVote.choice == .accept ? "Accept" : "Reject"). You can change it until voting closes.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.secondaryInk)
            }
            AdaptiveStack(spacing: AppSpacing.small) {
                Button {
                    Task { await cast(.reject) }
                } label: {
                    if isVoting { ProgressView().frame(maxWidth: .infinity, minHeight: 52) }
                    else { Label("Reject", systemImage: "xmark") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isVoting)
                .accessibilityIdentifier("vote.reject")
                Button {
                    Task { await cast(.accept) }
                } label: {
                    if isVoting {
                        ProgressView()
                            .tint(AppColors.onInk)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    } else {
                        Label("Accept", systemImage: "checkmark")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isVoting)
                .accessibilityIdentifier("vote.accept")
            }
        }
    }

    private func cast(_ choice: VoteChoice) async {
        guard !isVoting else { return }
        isVoting = true
        defer { isVoting = false }
        await store.castVote(choice)
    }

    private func result(_ proposal: ChallengeProposal) -> some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: proposal.status == .passed ? "checkmark.seal.fill" : "arrow.uturn.backward.circle.fill")
                .font(.system(size: 54)).foregroundStyle(proposal.status == .passed ? AppColors.accent : AppColors.secondaryInk)
            Text(proposal.status == .passed ? "Challenge scheduled" : CrewEdgeCopy.failedVoteHeadline).font(.title.bold())
            Text(proposal.status == .passed
                 ? "The group agreed. The round will start on the proposed date."
                 : CrewEdgeCopy.failedVoteBody)
                .foregroundStyle(AppColors.secondaryInk).multilineTextAlignment(.center)
            if proposal.status == .failed {
                Button("Duplicate and edit", systemImage: "doc.on.doc") { showDuplicate = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("vote.duplicate")
                Button("Start a new round") { showFreshBuilder = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("vote.startFresh")
                Button("Invite friends") { store.presentInviteFlow(groupID: proposal.groupID) }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("vote.inviteAfterFail")
            }
        }
        .padding(AppSpacing.large)
    }

    private func statusKind(_ proposal: ChallengeProposal) -> StatusPill.Kind {
        switch proposal.status {
        case .voting: .pending
        case .passed: .positive
        case .failed: .negative
        default: .neutral
        }
    }

    private func deadlineText(_ proposal: ChallengeProposal) -> String {
        var components = DateComponents(); components.hour = proposal.dailyDeadlineMinutes / 60; components.minute = proposal.dailyDeadlineMinutes % 60
        return Calendar.current.date(from: components)?.formatted(date: .omitted, time: .shortened) ?? String(localized: "Daily deadline")
    }
    private func scheduleText(_ proposal: ChallengeProposal) -> String {
        if proposal.frequencyType == .daily { return String(localized: "Every day") }
        return proposal.scheduledWeekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
}
