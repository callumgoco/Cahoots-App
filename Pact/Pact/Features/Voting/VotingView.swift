import SwiftUI

struct VotingView: View {
    @Environment(AppStore.self) private var store
    let proposalID: UUID
    @State private var showDuplicate = false
    @State private var showMemberStatus = false

    private var proposal: ChallengeProposal? { store.snapshot?.proposals.first { $0.id == proposalID } }
    private var votes: [Vote] { store.snapshot?.votes.filter { $0.proposalID == proposalID } ?? [] }
    private var myVote: Vote? { votes.first { $0.userID == store.currentUser?.id } }
    private var proposer: RoundUser? { guard let id = proposal?.proposedBy else { return nil }; return store.snapshot?.users.first { $0.id == id } }

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
                    .padding(AppSpacing.page)
                    .background(.bar)
            }
        }
        .task { await store.handleBecameActive() }
        .sheet(isPresented: $showDuplicate) {
            if let proposal {
                ChallengeBuilderView(initialDraft: ProposalDraft(proposal: proposal, earliestStartDate: store.earliestProposalStartDate))
            }
        }
    }

    private func summary(_ proposal: ChallengeProposal) -> some View {
        RoundCard(elevated: true) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                AdaptiveStack(spacing: AppSpacing.small) {
                    StatusPill(text: proposal.status == .voting ? "Voting open" : proposal.status.rawValue.capitalized, kind: statusKind(proposal))
                    Spacer(minLength: 0)
                    Text(timeRemaining(proposal)).font(.caption.bold()).foregroundStyle(AppColors.secondaryInk)
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
        return RoundCard {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                AdaptiveStack(spacing: AppSpacing.small) {
                    Text("\(accepts)").font(AppTypography.heroMetric)
                    Text("of \(needed) accepts needed to pass").font(.headline)
                    Spacer()
                    Text("\(votes.count) of \(proposal.eligibleVoterIDs.count) voted").font(.caption.bold()).foregroundStyle(AppColors.secondaryInk)
                }
                ProgressView(value: Double(votes.count), total: Double(proposal.eligibleVoterIDs.count)).tint(AppColors.accent)
                Text("A tie fails. Voting also closes early after every eligible member votes.").font(.caption).foregroundStyle(AppColors.secondaryInk)
            }
        }
    }

    private func memberStatus(_ proposal: ChallengeProposal) -> some View {
        RoundCard {
            DisclosureGroup("Member status", isExpanded: $showMemberStatus) {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    ForEach(store.groupMembers.filter { proposal.eligibleVoterIDs.contains($0.id) }) { member in
                        AdaptiveStack(spacing: AppSpacing.small) {
                            AvatarView(user: member, size: 36)
                            Text(member.displayName).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            if myVote != nil, let vote = votes.first(where: { $0.userID == member.id }) {
                                Label(vote.choice == .accept ? "Accept" : "Reject", systemImage: vote.choice == .accept ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(vote.choice == .accept ? AppColors.accent : AppColors.secondaryInk)
                            } else if myVote != nil {
                                Text("Awaiting").font(.caption).foregroundStyle(AppColors.secondaryInk)
                            } else {
                                Text("Vote hidden").font(.caption).foregroundStyle(AppColors.secondaryInk)
                            }
                        }
                    }
                }
                .padding(.top, AppSpacing.medium)
            }
            .font(.headline)
        }
    }

    private var voteActions: some View {
        VStack(spacing: AppSpacing.small) {
            if let myVote { Text("You voted \(myVote.choice.rawValue). You can change it until voting closes.").font(.footnote).foregroundStyle(AppColors.secondaryInk) }
            AdaptiveStack(spacing: AppSpacing.small) {
                Button("Reject", systemImage: "xmark") { Task { await store.castVote(.reject) } }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("vote.reject")
                Button("Accept", systemImage: "checkmark") { Task { await store.castVote(.accept) } }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("vote.accept")
            }
        }
    }

    private func result(_ proposal: ChallengeProposal) -> some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: proposal.status == .passed ? "checkmark.seal.fill" : "arrow.uturn.backward.circle.fill")
                .font(.system(size: 54)).foregroundStyle(proposal.status == .passed ? AppColors.accent : AppColors.secondaryInk)
            Text(proposal.status == .passed ? "Round scheduled" : "Proposal did not pass").font(.title.bold())
            Text(proposal.status == .passed ? "The group agreed. The round will start on the proposed date." : "The proposal can be duplicated and edited for another vote.")
                .foregroundStyle(AppColors.secondaryInk).multilineTextAlignment(.center)
            if proposal.status == .failed {
                Button("Duplicate and edit", systemImage: "doc.on.doc") { showDuplicate = true }
                    .buttonStyle(PrimaryButtonStyle())
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

    private func timeRemaining(_ proposal: ChallengeProposal) -> String {
        if proposal.votingEndsAt <= .now { return String(localized: "Voting closed") }
        let relative = proposal.votingEndsAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return String(localized: "Voting ends \(relative)")
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
