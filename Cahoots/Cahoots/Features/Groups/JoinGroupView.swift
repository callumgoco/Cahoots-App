import SwiftUI

struct JoinGroupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var validationMessage: String?
    @State private var isJoining = false
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
                    CahootsField(title: "Invite code", isFocused: focused) {
                        TextField("ABC123", text: $code)
                            .font(.title.bold().monospaced())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .onChange(of: code) { _, newValue in code = normalized(newValue) }
                            .accessibilityIdentifier("joinGroup.code")
                    }
                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.danger)
                    }
                    if let metadata = inviteMetadata {
                        CahootsCard {
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
                Button {
                    Task { await join() }
                } label: {
                    if isJoining {
                        ProgressView()
                            .tint(AppColors.onInk)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    } else {
                        Text("Join this group")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(code.count != 6 || isJoining)
                .accessibilityIdentifier("joinGroup.submit")
                .cahootsSheetFooter()
            }
            .interactiveDismissDisabled(isJoining)
            .roundPage()
            .navigationTitle("Join group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isJoining)
                }
            }
            .keyboardDoneToolbar()
            .onAppear { focused = true }
        }
    }

    private func normalized(_ input: String) -> String {
        let tail = input.split(separator: "/").last.map(String.init) ?? input
        return String(tail.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }

    private func join() async {
        guard !isJoining else { return }
        isJoining = true
        defer { isJoining = false }
        validationMessage = await store.joinGroup(code: code)
        if validationMessage == nil {
            store.clearPendingJoinRoute()
            dismiss()
        }
    }

    private var inviteMetadata: (group: CahootsGroup, inviter: CahootsUser)? {
        guard let snapshot = store.snapshot,
              let invite = snapshot.invites.first(where: { $0.code == code }),
              let group = snapshot.groups.first(where: { $0.id == invite.groupID }),
              let inviter = snapshot.users.first(where: { $0.id == invite.createdBy }) else { return nil }
        return (group, inviter)
    }
}
