import SwiftUI

struct EmptyAccountView: View {
    @Environment(AppStore.self) private var store
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showSignOut = false
    @State private var showDelete = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.extraLarge) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.largeTitle.weight(.bold))
                        .frame(minWidth: 88, minHeight: 88)
                        .foregroundStyle(AppColors.onInk)
                        .background(AppColors.ink, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    VStack(spacing: AppSpacing.small) {
                        Text("Your first round starts with a group")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Cahoots groups are private and invite-only. Create one for friends or join with a six-character code.")
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
                .cahootsSheetFooter()
            }
            .navigationTitle(AppIdentity.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { showSignOut = true }
                            .accessibilityIdentifier("account.signOut")
                        Button("Delete account", systemImage: "trash", role: .destructive) { showDelete = true }
                            .accessibilityIdentifier("account.delete")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityIdentifier("empty.accountMenu")
                }
            }
            .roundPage()
            .sheet(isPresented: $showCreate) { CreateGroupView() }
            .sheet(isPresented: $showJoin) { JoinGroupView() }
            .sheet(isPresented: $showSignOut) {
                CahootsConfirmationSheet(
                    title: "Sign out of Cahoots?",
                    message: "You’ll need to sign in again to get back to your crews.",
                    confirmTitle: "Sign out",
                    onConfirm: { showSignOut = false; Task { await store.signOutAsync() } },
                    onCancel: { showSignOut = false }
                )
            }
            .sheet(isPresented: $showDelete) {
                CahootsConfirmationSheet(
                    title: "Delete your account?",
                    message: "This starts permanent deletion of your profile and private group data. This cannot be undone.",
                    confirmTitle: "Delete account",
                    isWorking: isDeleting,
                    onConfirm: {
                        Task {
                            isDeleting = true
                            await store.deleteAccount()
                            isDeleting = false
                            showDelete = false
                        }
                    },
                    onCancel: { showDelete = false }
                )
            }
        }
    }
}
