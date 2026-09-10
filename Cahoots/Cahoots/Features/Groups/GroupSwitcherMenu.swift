import SwiftUI

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
            .foregroundStyle(AppColors.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .environment(\.colorScheme, .dark)
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
