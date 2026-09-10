import SwiftUI

struct GroupSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = ""
    @State private var memberLimit = 12
    @State private var replacementInvite: GroupInvite?
    @State private var confirmRevoke = false
    @State private var confirmRegenerate = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var isSaving = false

    private var isOwner: Bool { store.currentMembership?.role == .owner }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.large) {
                CahootsSettingsSection("Group") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    Divider()
                    TextField("Emoji", text: $emoji)
                        .frame(minHeight: 44)
                    Divider()
                    Stepper("Up to \(memberLimit) people", value: $memberLimit, in: activeMemberCount...20)
                        .frame(minHeight: 44)
                }
                .disabled(!isOwner)

                CahootsSettingsSection("Invitation") {
                    if let invite = replacementInvite ?? currentInvite {
                        LabeledContent("Code", value: invite.code)
                            .frame(minHeight: 44)
                        Divider()
                        LabeledContent("Expires", value: invite.expiresAt.formatted(date: .abbreviated, time: .omitted))
                            .frame(minHeight: 44)
                    } else {
                        Text("No active invitation")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                    }
                    if store.currentMembership?.role == .owner || store.currentMembership?.role == .admin {
                        Divider()
                        Button("Generate new invitation") { confirmRegenerate = true }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                        if currentInvite != nil {
                            Divider()
                            Button("Revoke invitation", role: .destructive) { confirmRevoke = true }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 44)
                        }
                    }
                }

                CahootsSettingsSection("") {
                    if isOwner {
                        Button("Delete group", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                        Text("Deletes this group for everyone, including rounds and activity. This cannot be undone.")
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryInk)
                    } else {
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
            .padding(.bottom, 24)
        }
        .roundPage()
        .interactiveKeyboardDismiss()
        .navigationTitle("Group settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            if isOwner {
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                isSaving = true
                                defer { isSaving = false }
                                if await store.updateCurrentGroup(name: name, emoji: emoji, memberLimit: memberLimit) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .keyboardDoneToolbar()
        .confirmationDialog("Revoke this invitation?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Revoke", role: .destructive) { Task { await store.revokeCurrentInvite() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Generate a new invitation?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("Generate new invitation") { Task { replacementInvite = await store.regenerateCurrentInvite() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The previous code and QR link will stop working immediately.") }
        .confirmationDialog("Leave this group?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave group", role: .destructive) { Task { if await store.leaveCurrentGroup() { dismiss() } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You will lose access to this group’s rounds and activity.") }
        .confirmationDialog("Delete this group?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete group", role: .destructive) { Task { if await store.deleteCurrentGroup() { dismiss() } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All members will lose access. Rounds, votes, and activity for this group will be permanently removed.") }
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
