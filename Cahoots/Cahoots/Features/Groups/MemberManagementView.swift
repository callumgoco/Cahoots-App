import SwiftUI

struct MemberManagementView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reportUser: CahootsUser?
    @State private var transferUser: CahootsUser?
    @State private var removeUser: CahootsUser?
    @State private var blockUser: CahootsUser?
    @State private var confirmLeave = false
    @State private var pendingRole: PendingRoleChange?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.large) {
                CahootsSettingsSection("Active members") {
                    ForEach(Array(store.groupMembers.enumerated()), id: \.element.id) { index, user in
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
                                            Button("Make member", systemImage: "person") { pendingRole = PendingRoleChange(user: user, role: .member) }
                                        } else {
                                            Button("Make admin", systemImage: "person.badge.shield.checkmark") { pendingRole = PendingRoleChange(user: user, role: .admin) }
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
                        .frame(minHeight: 44)
                        if index < store.groupMembers.count - 1 {
                            Divider()
                        }
                    }
                }

                if store.currentMembership?.role == .member {
                    CahootsSettingsSection("") {
                        Button("Leave group", role: .destructive) { confirmLeave = true }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                        Text("You will lose access to this group’s rounds and activity.")
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                }
            }
            .padding(AppSpacing.page)
            .cahootsTabBarClearance()
        }
        .roundPage()
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .cahootsDrillInBar()
        .sheet(item: $reportUser) { ReportMemberView(user: $0) }
        .alert("Transfer ownership to \(transferUser?.displayName ?? "this member")?", isPresented: Binding(
            get: { transferUser != nil }, set: { if !$0 { transferUser = nil } }
        )) {
            Button("Transfer ownership") {
                if let transferUser { Task { await store.transferOwnership(to: transferUser.id); self.transferUser = nil } }
            }
            Button("Cancel", role: .cancel) { transferUser = nil }
        } message: { Text("You will become an admin and the new owner will control group roles and settings.") }
        .alert("Remove \(removeUser?.displayName ?? "this member")?", isPresented: Binding(
            get: { removeUser != nil }, set: { if !$0 { removeUser = nil } }
        )) {
            Button("Remove from group", role: .destructive) {
                if let user = removeUser { Task { await store.removeMember(user.id); removeUser = nil } }
            }
            Button("Cancel", role: .cancel) { removeUser = nil }
        } message: { Text("They will lose access to this group and its current round.") }
        .alert("Block \(blockUser?.displayName ?? "this member")?", isPresented: Binding(
            get: { blockUser != nil }, set: { if !$0 { blockUser = nil } }
        )) {
            Button("Block member", role: .destructive) {
                if let user = blockUser { Task { await store.block(user); blockUser = nil } }
            }
            Button("Cancel", role: .cancel) { blockUser = nil }
        } message: { Text("Their activity will be hidden. You can unblock them later in Safety & privacy.") }
        .sheet(isPresented: $confirmLeave) {
            CahootsConfirmationSheet(
                title: "Leave this group?",
                message: "You will lose access to this group’s rounds and activity.",
                confirmTitle: "Leave group",
                onConfirm: {
                    confirmLeave = false
                    Task { if await store.leaveCurrentGroup() { dismiss() } }
                },
                onCancel: { confirmLeave = false }
            )
        }
        .sheet(item: $pendingRole) { change in
            CahootsConfirmationSheet(
                title: change.role == .admin ? "Make \(change.user.displayName) an admin?" : "Change \(change.user.displayName) to a member?",
                message: change.role == .admin
                    ? "Admins can invite people, remove members, and manage the invitation."
                    : "They will lose admin permissions for this crew.",
                confirmTitle: change.role == .admin ? "Make admin" : "Make member",
                isDestructive: change.role != .admin,
                onConfirm: {
                    let userID = change.user.id
                    let role = change.role
                    pendingRole = nil
                    Task { await store.setRole(role, for: userID) }
                },
                onCancel: { pendingRole = nil }
            )
        }
    }

    private func role(for user: CahootsUser) -> GroupRole {
        store.snapshot?.memberships.first { $0.groupID == store.currentGroup?.id && $0.userID == user.id }?.role ?? .member
    }

    private func canRemove(_ user: CahootsUser) -> Bool {
        guard user.id != store.currentUser?.id, user.id != store.currentGroup?.ownerID else { return false }
        if store.currentMembership?.role == .owner { return true }
        return store.currentMembership?.role == .admin && role(for: user) == .member
    }
}

private struct PendingRoleChange: Identifiable {
    let user: CahootsUser
    let role: GroupRole
    var id: UUID { user.id }
}

struct ReportMemberView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let user: CahootsUser
    @State private var category = "Unsafe pressure"
    @State private var details = ""

    private let categories = ["Unsafe pressure", "Harassment", "Spam", "Other"]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppSpacing.large) {
                    CahootsSettingsSection("Reason") {
                        Picker("Reason", selection: $category) {
                            ForEach(categories, id: \.self) { Text($0) }
                        }
                        .frame(minHeight: 44)
                    }

                    CahootsSettingsSection("Optional details") {
                        TextField("What happened?", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                            .frame(minHeight: 88, alignment: .top)
                    }

                    CahootsSettingsSection("") {
                        Text("Reports use neutral account and group context. Workout quantities are not included.")
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryInk)
                    }

                    Button("Submit") {
                        let reason = details.isEmpty ? category : "\(category): \(details)"
                        Task { await store.report(user, reason: reason); dismiss() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(AppSpacing.page)
                .padding(.bottom, 24)
            }
            .roundPage()
            .interactiveKeyboardDismiss()
            .navigationTitle("Report \(user.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .keyboardDoneToolbar()
        }
    }
}
