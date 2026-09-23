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
                Text(store.currentGroup?.name ?? "Crew")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down").font(.caption2.bold())
            }
            .font(.subheadline.bold())
            .foregroundStyle(AppColors.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(-1)
            .environment(\.colorScheme, .dark)
            .background(AppColors.raised, in: Capsule())
            .shadow(color: AppShadow.color, radius: 8, y: 3)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .accessibilityLabel("Switch crew. Current crew \(store.currentGroup?.name ?? "none")")
        .accessibilityIdentifier("group.switcher")
        .groupSwitcherPresentation(
            isPresented: $isPresented,
            showCreate: $showCreate,
            showJoin: $showJoin
        )
    }
}

/// Shared centered alert + create/join sheets for switching the active crew.
struct GroupSwitcherPresentationModifier: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var isPresented: Bool
    @Binding var showCreate: Bool
    @Binding var showJoin: Bool

    func body(content: Content) -> some View {
        content
            .alert("Switch crew", isPresented: $isPresented) {
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
            } message: {
                Text("Choose which crew to view.")
            }
            .sheet(isPresented: $showCreate) { CreateGroupView() }
            .sheet(isPresented: $showJoin) { JoinGroupView() }
    }
}

extension View {
    func groupSwitcherPresentation(
        isPresented: Binding<Bool>,
        showCreate: Binding<Bool>,
        showJoin: Binding<Bool>
    ) -> some View {
        modifier(GroupSwitcherPresentationModifier(
            isPresented: isPresented,
            showCreate: showCreate,
            showJoin: showJoin
        ))
    }
}
