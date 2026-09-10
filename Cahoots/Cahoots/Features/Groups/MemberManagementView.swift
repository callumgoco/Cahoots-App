import SwiftUI

struct MemberManagementView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reportUser: CahootsUser?
    @State private var transferUser: CahootsUser?
    @State private var removeUser: CahootsUser?
    @State private var blockUser: CahootsUser?
    @State private var confirmLeave = false

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
                        .frame(minHeight: 44)
                        if index < store.groupMembers.count - 1 {
                            Divider()
                        }
                    }
                }

                CahootsSettingsSection("") {
                    Button("Leave group", role: .destructive) { confirmLeave = true }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                    Text("Owners must transfer ownership before leaving a group with other members.")
                        .font(.caption)
                        .foregroundStyle(AppColors.secondaryInk)
                }
            }
            .padding(AppSpacing.page)
            .padding(.bottom, 24)
        }
        .roundPage()
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

    private func role(for user: CahootsUser) -> GroupRole {
        store.snapshot?.memberships.first { $0.groupID == store.currentGroup?.id && $0.userID == user.id }?.role ?? .member
    }

    private func canRemove(_ user: CahootsUser) -> Bool {
        guard user.id != store.currentUser?.id, user.id != store.currentGroup?.ownerID else { return false }
        if store.currentMembership?.role == .owner { return true }
        return store.currentMembership?.role == .admin && role(for: user) == .member
    }
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
