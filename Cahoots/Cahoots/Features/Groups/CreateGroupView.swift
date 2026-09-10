import SwiftUI

struct CreateGroupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "⚡️"
    @State private var memberLimit = 12
    @State private var createdInvite: GroupInvite?
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if let invite = createdInvite, let group = store.snapshot?.groups.first(where: { $0.id == invite.groupID }) {
                    InviteShareView(group: group, invite: invite) {
                        dismiss()
                        store.finishGroupCreation()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.large) {
                            CahootsSettingsSection("Group identity") {
                                TextField("Group name", text: $name)
                                    .textInputAutocapitalization(.words)
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("createGroup.name")
                                Divider()
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: AppSpacing.small) {
                                        ForEach(["⚡️", "💪", "🏃", "🌿", "🔥", "⭐️"], id: \.self) { choice in
                                            Button(choice) { emoji = choice }
                                                .font(.title2)
                                                .frame(minWidth: 44, minHeight: 44)
                                                .background(emoji == choice ? AppColors.accentSoft : AppColors.raised, in: RoundedRectangle(cornerRadius: AppRadius.control))
                                                .accessibilityLabel("Use \(choice) as the group emoji")
                                        }
                                    }
                                }
                                TextField("Or enter a custom emoji", text: $emoji)
                                    .font(.title3)
                                    .frame(minHeight: 44)
                                Text("Choose a name people will recognise. Groups stay private.")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.secondaryInk)
                            }

                            CahootsSettingsSection("Group options") {
                                Stepper("Up to \(memberLimit) people", value: $memberLimit, in: 2...20)
                                    .frame(minHeight: 44)
                            }

                            Button {
                                Task {
                                    isCreating = true
                                    createdInvite = await store.createGroup(name: name, emoji: emoji, memberLimit: memberLimit)
                                    isCreating = false
                                }
                            } label: {
                                if isCreating {
                                    ProgressView()
                                } else {
                                    Text("Create private group")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(TextSanitizer.clean(name).count < 2 || isCreating)
                            .accessibilityIdentifier("createGroup.submit")
                        }
                        .padding(AppSpacing.page)
                        .padding(.bottom, 24)
                    }
                    .roundPage()
                    .interactiveKeyboardDismiss()
                    .keyboardDoneToolbar()
                }
            }
            .navigationTitle(createdInvite == nil ? "Create group" : "Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if createdInvite == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isCreating) }
                }
            }
        }
    }
}
