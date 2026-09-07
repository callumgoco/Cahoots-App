import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct EmptyAccountView: View {
    @State private var showCreate = false
    @State private var showJoin = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.extraLarge) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.largeTitle.weight(.bold))
                        .frame(minWidth: 88, minHeight: 88)
                        .foregroundStyle(Color.white)
                        .background(AppColors.ink, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    VStack(spacing: AppSpacing.small) {
                        Text("Your first round starts with a group")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Round groups are private and invite-only. Create one for friends or join with a six-character code.")
                            .foregroundStyle(AppColors.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(AppSpacing.page)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.small) {
                    Button("Create a group") { showCreate = true }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("empty.createGroup")
                    Button("Join with a code") { showJoin = true }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("empty.joinGroup")
                }
                .padding(AppSpacing.page)
                .background(.bar)
            }
            .navigationTitle(AppIdentity.name)
            .roundPage()
            .sheet(isPresented: $showCreate) { CreateGroupView() }
            .sheet(isPresented: $showJoin) { JoinGroupView() }
        }
    }
}

struct CreateGroupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "⚡️"
    @State private var memberLimit = 12
    @State private var createdInvite: GroupInvite?

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if let invite = createdInvite, let group = store.snapshot?.groups.first(where: { $0.id == invite.groupID }) {
                    InviteShareView(group: group, invite: invite) {
                        dismiss()
                        store.finishGroupCreation()
                    }
                } else {
                    Form {
                        Section {
                            TextField("Group name", text: $name)
                                .textInputAutocapitalization(.words)
                                .accessibilityIdentifier("createGroup.name")
                            ScrollView(.horizontal) {
                                HStack(spacing: AppSpacing.small) {
                                    ForEach(["⚡️", "💪", "🏃", "🌿", "🔥", "⭐️"], id: \.self) { choice in
                                        Button(choice) { emoji = choice }
                                            .font(.title2)
                                            .frame(minWidth: 44, minHeight: 44)
                                            .background(emoji == choice ? AppColors.accentSoft : AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.control))
                                            .accessibilityLabel("Use \(choice) as the group emoji")
                                    }
                                }
                            }
                            TextField("Or enter a custom emoji", text: $emoji).font(.title3)
                        } header: {
                            Text("Group identity")
                        } footer: {
                            Text("Choose a name people will recognise. Groups stay private.")
                        }
                        DisclosureGroup("Group options") {
                            Stepper("Up to \(memberLimit) people", value: $memberLimit, in: 2...20)
                                .padding(.vertical, AppSpacing.small)
                        }
                        Section {
                            Button("Create private group") {
                                Task { createdInvite = await store.createGroup(name: name, emoji: emoji, memberLimit: memberLimit) }
                            }
                            .disabled(TextSanitizer.clean(name).count < 2)
                            .accessibilityIdentifier("createGroup.submit")
                        }
                    }
                    .interactiveKeyboardDismiss()
                    .keyboardDoneToolbar()
                }
            }
            .navigationTitle(createdInvite == nil ? "Create group" : "Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if createdInvite == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
    }
}

struct JoinGroupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var validationMessage: String?
    @FocusState private var focused: Bool

    init(initialCode: String = "") {
        let tail = initialCode.split(separator: "/").last.map(String.init) ?? initialCode
        _code = State(initialValue: String(tail.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text("Enter your invite").font(.largeTitle.bold())
                        Text("Paste an invite link or type the six-character code from a group member.")
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                    TextField("ABC123", text: $code)
                        .font(.title.bold().monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onChange(of: code) { _, newValue in code = normalized(newValue) }
                        .padding(AppSpacing.medium)
                        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.control))
                        .accessibilityIdentifier("joinGroup.code")
                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.danger)
                    }
                    if let metadata = inviteMetadata {
                        RoundCard {
                            AdaptiveStack(spacing: AppSpacing.medium) {
                                Text(metadata.group.emoji).font(.largeTitle)
                                VStack(alignment: .leading, spacing: AppSpacing.micro) {
                                    Text(metadata.group.name).font(.headline)
                                    Text("Invitation from \(metadata.inviter.displayName)")
                                        .font(.subheadline)
                                        .foregroundStyle(AppColors.secondaryInk)
                                }
                            }
                        }
                    }
                }
                .padding(AppSpacing.page)
            }
            .interactiveKeyboardDismiss()
            .safeAreaInset(edge: .bottom) {
                Button("Join this group") {
                    Task {
                        validationMessage = await store.joinGroup(code: code)
                        if validationMessage == nil { store.clearPendingJoinRoute(); dismiss() }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(code.count != 6)
                .accessibilityIdentifier("joinGroup.submit")
                .padding(AppSpacing.page)
                .background(.bar)
            }
            .roundPage()
            .navigationTitle("Join group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .keyboardDoneToolbar()
            .onAppear { focused = true }
        }
    }

    private func normalized(_ input: String) -> String {
        let tail = input.split(separator: "/").last.map(String.init) ?? input
        return String(tail.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }

    private var inviteMetadata: (group: RoundGroup, inviter: RoundUser)? {
        guard let snapshot = store.snapshot,
              let invite = snapshot.invites.first(where: { $0.code == code }),
              let group = snapshot.groups.first(where: { $0.id == invite.groupID }),
              let inviter = snapshot.users.first(where: { $0.id == invite.createdBy }) else { return nil }
        return (group, inviter)
    }
}

struct InviteShareView: View {
    let group: RoundGroup
    let invite: GroupInvite
    let done: () -> Void
    @State private var copied = false

    private var link: String { "https://\(AppIdentity.inviteHost)/join/\(invite.code)" }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.large) {
                VStack(spacing: AppSpacing.small) {
                    Text(group.emoji).font(.system(size: 56))
                    Text("Invite friends to \(group.name)").font(.title.bold()).multilineTextAlignment(.center)
                    Text("Anyone with this code can join this group until it expires.").foregroundStyle(AppColors.secondaryInk).multilineTextAlignment(.center)
                }
                RoundCard(elevated: true) {
                    VStack(spacing: AppSpacing.medium) {
                        QRCodeView(text: link).frame(width: 164, height: 164)
                        Text(invite.code).font(.system(size: 36, weight: .heavy, design: .rounded).monospaced())
                        Text("Expires \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(AppColors.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                }
                AdaptiveStack(spacing: AppSpacing.small) {
                    Button(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = invite.code
                        copied = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    ShareLink(item: link, subject: Text("Join \(group.name) on \(AppIdentity.name)"), message: Text("Use code \(invite.code) to join our private workout round.")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Button("Done", action: done)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("invite.done")
                    .padding(.top, AppSpacing.small)
            }
            .padding(AppSpacing.page)
        }
        .roundPage()
    }
}

private struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = makeImage() {
            Image(uiImage: image).interpolation(.none).resizable().accessibilityLabel("Invitation QR code")
        } else {
            Image(systemName: "qrcode").resizable().accessibilityLabel("QR code unavailable")
        }
    }

    private func makeImage() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private enum CrewDestination: Hashable {
    case invite, members, settings
}

struct GroupView: View {
    @Environment(AppStore.self) private var store
    @State private var path = NavigationPath()
    @State private var showBuilder = false
    @State private var showVote = ProcessInfo.processInfo.arguments.contains("-showVote")

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
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                                .foregroundStyle(AppColors.accent)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Group actions")
                        .accessibilityIdentifier("group.menu")
                    }
                    groupHeader
                    proposeAccessCard
                    if let challenge = store.currentChallenge { activeChallengeCard(challenge) }
                    if let proposal = store.currentProposal { proposalCard(proposal) }
                    else if let proposal = store.latestFailedProposal { failedProposalCard(proposal) }
                    CrewStandingsSection()
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
                if let proposal = store.currentProposal {
                    VotingView(proposalID: proposal.id)
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
                            .buttonStyle(.borderedProminent)
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
        }
        .id(store.currentGroup?.id)
        .onChange(of: store.selectedTab) { _, newTab in
            guard newTab != 1 else { return }
            path = NavigationPath()
            showBuilder = false
            showVote = false
        }
    }

    private var groupHeader: some View {
        RoundCard(elevated: true) {
            AdaptiveStack(spacing: AppSpacing.medium) {
                Text(store.currentGroup?.emoji ?? "⚡️").font(.largeTitle)
                VStack(alignment: .leading, spacing: AppSpacing.micro) {
                    Text(store.currentGroup?.name ?? "Crew")
                        .font(.title2.bold())
                        .accessibilityIdentifier("group.header.name")
                    Text("\(store.groupMembers.count) members · Private")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.secondaryInk)
                }
                Spacer(minLength: 0)
                if store.currentMembership.map({ GroupPermissionRules.canManageInvites($0.role) }) == true {
                    Button("Invite") { path.append(CrewDestination.invite) }.font(.subheadline.bold()).buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var proposeAccessCard: some View {
        if let proposal = store.currentProposal {
            Button {
                showVote = true
            } label: {
                RoundCard {
                    HStack(spacing: AppSpacing.medium) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(AppColors.accent)
                        VStack(alignment: .leading, spacing: AppSpacing.micro) {
                            Text("A vote is already open")
                                .font(.headline)
                                .foregroundStyle(AppColors.ink)
                            Text(proposal.title)
                                .font(.subheadline)
                                .foregroundStyle(AppColors.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("group.voteInProgress")
        } else if canPropose {
            Button {
                showBuilder = true
            } label: {
                RoundCard {
                    HStack(spacing: AppSpacing.medium) {
                        Image(systemName: "flag.badge.ellipsis")
                            .font(.title2)
                            .foregroundStyle(AppColors.accent)
                        VStack(alignment: .leading, spacing: AppSpacing.micro) {
                            Text(store.currentChallenge == nil ? "Start a round" : "Propose a round")
                                .font(.headline)
                                .foregroundStyle(AppColors.ink)
                            Text("Set a goal for this crew to vote on or begin.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("group.propose")
        }
    }

    private func activeChallengeCard(_ challenge: RoundChallenge) -> some View {
        NavigationLink {
            RoundDetailsView(challenge: challenge)
        } label: {
            RoundCard {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    RoundSectionHeader(title: "Current round")
                    AdaptiveStack(spacing: AppSpacing.small) {
                        Text(challenge.quantityLabel).font(AppTypography.heroMetric)
                        Text(challenge.activityType).font(.title3.bold())
                    }
                    Text(challenge.title).font(.headline)
                    AdaptiveStack(spacing: AppSpacing.small) {
                        StatusPill(text: challenge.status.rawValue.capitalized, kind: .positive)
                        Text("Ends \(challenge.endDate.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(AppColors.secondaryInk)
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
            RoundCard {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    HStack { StatusPill(text: "Proposal · Vote open", kind: .pending); Spacer(); Image(systemName: "chevron.right") }
                    Text(proposal.title).font(.title2.bold()).foregroundStyle(AppColors.ink)
                    Text("\(store.snapshot?.votes.filter { $0.proposalID == proposal.id }.count ?? 0) of \(proposal.eligibleVoterIDs.count) voted")
                        .font(.subheadline).foregroundStyle(AppColors.secondaryInk)
                    Text("Vote now").font(.headline).foregroundStyle(AppColors.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("group.openVote")
    }

    private func failedProposalCard(_ proposal: ChallengeProposal) -> some View {
        NavigationLink { VotingView(proposalID: proposal.id) } label: {
            RoundCard {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        StatusPill(text: "Vote finished", kind: .neutral)
                        Text(proposal.title).font(.headline).foregroundStyle(AppColors.ink)
                        Text("Did not pass · duplicate and edit").font(.caption).foregroundStyle(AppColors.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(AppColors.secondaryInk)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var membersCard: some View {
        RoundCard {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                RoundSectionHeader(title: "Members", action: "View all") { path.append(CrewDestination.members) }
                ForEach(store.groupMembers.prefix(6)) { user in
                    HStack(spacing: AppSpacing.medium) {
                        AvatarView(user: user)
                        Text(user.displayName).font(.headline)
                        if user.id == store.currentUser?.id { Text("You").font(.caption).foregroundStyle(AppColors.secondaryInk) }
                        Spacer()
                        if user.id == store.currentGroup?.ownerID { Image(systemName: "crown.fill").foregroundStyle(AppColors.warning).accessibilityLabel("Owner") }
                    }
                }
            }
        }
    }

    private var activityCard: some View {
        RoundCard {
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

struct RoundDetailsView: View {
    let challenge: RoundChallenge

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.large) {
                RoundCard(elevated: true) {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        StatusPill(text: challenge.status.rawValue.capitalized, kind: .positive)
                        Text(challenge.title).font(.largeTitle.bold())
                        AdaptiveStack(spacing: AppSpacing.small) {
                            Text(challenge.quantityLabel).font(AppTypography.heroMetric)
                            Text(challenge.activityType).font(.title3.bold())
                        }
                    }
                }
                RoundCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        RoundSectionHeader(title: "Schedule")
                        detailRow("Starts", challenge.startDate.formatted(date: .long, time: .omitted))
                        detailRow("Ends", challenge.endDate.formatted(date: .long, time: .omitted))
                        detailRow("Days", challenge.frequencyType == .daily ? "Every day" : "Selected weekdays")
                    }
                }
                RoundCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        RoundSectionHeader(title: "Rules")
                        detailRow("Daily deadline", deadlineLabel)
                        detailRow("Timezone", challenge.challengeTimezone.replacingOccurrences(of: "_", with: " "))
                        detailRow("Recovery allowance", "\(challenge.recoveryDayAllowance)")
                    }
                }
            }
            .padding(AppSpacing.page)
        }
        .navigationTitle("Round details")
        .navigationBarTitleDisplayMode(.inline)
        .roundPage()
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(AppColors.secondaryInk)
            Spacer()
            Text(value).font(.body.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }

    private var deadlineLabel: String {
        let hour = challenge.dailyDeadlineMinutes / 60
        let minute = challenge.dailyDeadlineMinutes % 60
        return DateComponents(calendar: .current, hour: hour, minute: minute).date?.formatted(date: .omitted, time: .shortened) ?? "—"
    }
}

struct MemberManagementView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reportUser: RoundUser?
    @State private var transferUser: RoundUser?
    @State private var removeUser: RoundUser?
    @State private var blockUser: RoundUser?
    @State private var confirmLeave = false

    var body: some View {
        List {
                Section("Active members") {
                    ForEach(store.groupMembers) { user in
                        HStack {
                            AvatarView(user: user)
                            VStack(alignment: .leading) {
                                Text(user.displayName).font(.headline)
                                Text(role(for: user).rawValue.capitalized).font(.caption).foregroundStyle(AppColors.secondaryInk)
                            }
                            Spacer()
                            if user.id != store.currentUser?.id {
                                Menu {
                                    if store.currentMembership?.role == .owner {
                                        Button("Transfer ownership", systemImage: "crown") { transferUser = user }
                                        if role(for: user) == .admin {
                                            Button("Make member", systemImage: "person") { Task { await store.setRole(.member, for: user.id) } }
                                        } else {
                                            Button("Make admin", systemImage: "person.badge.shield.checkmark") { Task { await store.setRole(.admin, for: user.id) } }
                                        }
                                    }
                                    if canRemove(user) {
                                        Button("Remove from group", systemImage: "person.fill.xmark", role: .destructive) { removeUser = user }
                                    }
                                    Button("Report user", systemImage: "exclamationmark.bubble") { reportUser = user }
                                    Button("Block user", systemImage: "hand.raised", role: .destructive) { blockUser = user }
                                } label: { Image(systemName: "ellipsis") }
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                        }
                    }
                }
                Section {
                    Button("Leave group", role: .destructive) { confirmLeave = true }
                } footer: { Text("Owners must transfer ownership before leaving a group with other members.") }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $reportUser) { ReportMemberView(user: $0) }
            .confirmationDialog("Transfer ownership to \(transferUser?.displayName ?? "this member")?", isPresented: Binding(
                get: { transferUser != nil }, set: { if !$0 { transferUser = nil } }
            ), titleVisibility: .visible) {
                Button("Transfer ownership") {
                    if let transferUser { Task { await store.transferOwnership(to: transferUser.id); self.transferUser = nil } }
                }
                Button("Cancel", role: .cancel) { transferUser = nil }
            } message: { Text("You will become an admin and the new owner will control group roles and settings.") }
            .confirmationDialog("Remove \(removeUser?.displayName ?? "this member")?", isPresented: Binding(
                get: { removeUser != nil }, set: { if !$0 { removeUser = nil } }
            ), titleVisibility: .visible) {
                Button("Remove from group", role: .destructive) {
                    if let user = removeUser { Task { await store.removeMember(user.id); removeUser = nil } }
                }
                Button("Cancel", role: .cancel) { removeUser = nil }
            } message: { Text("They will lose access to this group and its current round.") }
            .confirmationDialog("Block \(blockUser?.displayName ?? "this member")?", isPresented: Binding(
                get: { blockUser != nil }, set: { if !$0 { blockUser = nil } }
            ), titleVisibility: .visible) {
                Button("Block member", role: .destructive) {
                    if let user = blockUser { Task { await store.block(user); blockUser = nil } }
                }
                Button("Cancel", role: .cancel) { blockUser = nil }
            } message: { Text("Their activity will be hidden. You can unblock them later in Safety & privacy.") }
            .confirmationDialog("Leave this group?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave group", role: .destructive) { Task { if await store.leaveCurrentGroup() { dismiss() } } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("You will lose access to this group’s rounds and activity.") }
    }

    private func role(for user: RoundUser) -> GroupRole {
        store.snapshot?.memberships.first { $0.groupID == store.currentGroup?.id && $0.userID == user.id }?.role ?? .member
    }

    private func canRemove(_ user: RoundUser) -> Bool {
        guard user.id != store.currentUser?.id, user.id != store.currentGroup?.ownerID else { return false }
        if store.currentMembership?.role == .owner { return true }
        return store.currentMembership?.role == .admin && role(for: user) == .member
    }
}

private struct ReportMemberView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let user: RoundUser
    @State private var category = "Unsafe pressure"
    @State private var details = ""

    private let categories = ["Unsafe pressure", "Harassment", "Spam", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }
                Section("Optional details") {
                    TextField("What happened?", text: $details, axis: .vertical).lineLimit(3...6)
                }
                Section { Text("Reports use neutral account and group context. Workout quantities are not included.").font(.caption).foregroundStyle(AppColors.secondaryInk) }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle("Report \(user.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        let reason = details.isEmpty ? category : "\(category): \(details)"
                        Task { await store.report(user, reason: reason); dismiss() }
                    }
                }
            }
            .keyboardDoneToolbar()
        }
    }
}

private struct GroupSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = ""
    @State private var memberLimit = 12
    @State private var replacementInvite: GroupInvite?
    @State private var confirmRevoke = false
    @State private var confirmRegenerate = false

    var body: some View {
        Form {
                Section("Group") {
                    TextField("Name", text: $name)
                    TextField("Emoji", text: $emoji)
                    Stepper("Up to \(memberLimit) people", value: $memberLimit, in: activeMemberCount...20)
                }
                .disabled(store.currentMembership?.role != .owner)
                Section("Invitation") {
                    if let invite = replacementInvite ?? currentInvite {
                        LabeledContent("Code", value: invite.code)
                        LabeledContent("Expires", value: invite.expiresAt.formatted(date: .abbreviated, time: .omitted))
                    } else {
                        Text("No active invitation")
                    }
                    if store.currentMembership?.role == .owner || store.currentMembership?.role == .admin {
                        Button("Generate new invitation") { confirmRegenerate = true }
                        if currentInvite != nil { Button("Revoke invitation", role: .destructive) { confirmRevoke = true } }
                    }
                }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle("Group settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if store.currentMembership?.role == .owner {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { if await store.updateCurrentGroup(name: name, emoji: emoji, memberLimit: memberLimit) { dismiss() } } }
                    }
                }
            }
            .keyboardDoneToolbar()
            .confirmationDialog("Revoke this invitation?", isPresented: $confirmRevoke, titleVisibility: .visible) {
                Button("Revoke", role: .destructive) { Task { await store.revokeCurrentInvite() } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Generate a new invitation?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
                Button("Generate new invitation") { Task { replacementInvite = await store.regenerateCurrentInvite() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The previous code and QR link will stop working immediately.") }
            .onAppear {
                name = store.currentGroup?.name ?? ""
                emoji = store.currentGroup?.emoji ?? "⚡️"
                memberLimit = store.currentGroup?.memberLimit ?? 12
            }
    }

    private var activeMemberCount: Int { max(2, store.groupMembers.count) }
    private var currentInvite: GroupInvite? {
        store.snapshot?.invites.first { $0.groupID == store.currentGroup?.id && $0.revokedAt == nil && $0.expiresAt > .now }
    }
}

struct ActivityFeedView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List(store.currentActivity) { item in ActivityRow(item: item).listRowBackground(Color.clear) }
            .listStyle(.plain)
            .navigationTitle("Activity")
            .overlay {
                if store.currentActivity.isEmpty {
                    ContentUnavailableView("No group activity yet", systemImage: "waveform.path.ecg", description: Text("Private, quantity-free updates will appear here."))
                }
            }
            .roundPage()
    }
}

struct GroupSwitcherMenu: View {
    @Environment(AppStore.self) private var store
    @State private var isPresented = false
    @State private var showCreate = false
    @State private var showJoin = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 5) {
                Text(store.currentGroup?.emoji ?? "⚡️")
                Text(store.currentGroup?.name ?? "Crew").lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.bold())
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(AppColors.raised, in: Capsule())
            .shadow(color: AppShadow.color, radius: 8, y: 3)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .accessibilityLabel("Switch crew. Current crew \(store.currentGroup?.name ?? "none")")
        .accessibilityIdentifier("group.switcher")
        .confirmationDialog("Switch crew", isPresented: $isPresented, titleVisibility: .visible) {
            ForEach(store.activeGroups) { group in
                Button(group.id == store.currentGroup?.id ? "✓ \(group.emoji) \(group.name)" : "\(group.emoji) \(group.name)") {
                    store.selectGroup(group.id)
                }
                .accessibilityIdentifier("group.switch.\(group.id.uuidString)")
            }
            Button("Create a group") { showCreate = true }
                .accessibilityIdentifier("group.switcher.create")
            Button("Join with a code") { showJoin = true }
                .accessibilityIdentifier("group.switcher.join")
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCreate) { CreateGroupView() }
        .sheet(isPresented: $showJoin) { JoinGroupView() }
    }
}

struct ActivityRow: View {
    let item: ActivityFeedItem

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: symbol)
                .font(.body.bold())
                .frame(width: 38, height: 38)
                .background(AppColors.card, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(item.message).font(.subheadline.weight(.medium))
                Text(item.createdAt, style: .relative).font(.caption).foregroundStyle(AppColors.secondaryInk)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch item.eventType {
        case .completion: "checkmark"
        case .recovery: "moon.zzz.fill"
        case .proposal: "doc.badge.plus"
        case .voteCompleted: "checkmark.seal.fill"
        case .challengeStarted: "flag.fill"
        case .roundFinished: "trophy.fill"
        case .memberJoined: "person.badge.plus"
        }
    }
}
