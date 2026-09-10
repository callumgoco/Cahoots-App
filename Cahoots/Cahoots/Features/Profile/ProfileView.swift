import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var showEditName = false
    @State private var showSignOut = false
    @State private var showDelete = false
    @State private var showAddGroup = false
    @State private var showCreateGroup = false
    @State private var showJoinGroup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppSpacing.large) {
                    HStack(alignment: .center, spacing: AppSpacing.small) {
                        Text("You")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: AppSpacing.small)
                        // Match Crew's trailing control height so the title row lands on the same baseline.
                        Color.clear.frame(width: 44, height: 44)
                    }

                    profileHeader

                    settingsSection(title: "Your crews") {
                        ForEach(store.activeGroups) { group in
                            groupRow(group)
                            if group.id != store.activeGroups.last?.id {
                                Divider()
                            }
                        }
                        Divider()
                        Button("Add group", systemImage: "plus.circle") { showAddGroup = true }
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                    }

                    settingsSection(title: "Preferences") {
                        NavigationLink { NotificationSettingsView() } label: {
                            settingsLabel("Notifications", systemImage: "bell.fill")
                        }
                        Divider()
                        Picker(selection: appearanceBinding) {
                            ForEach(AppearancePreference.allCases) { Text($0.displayName).tag($0) }
                        } label: {
                            Label("Appearance", systemImage: "circle.lefthalf.filled")
                        }
                        Divider()
                        themePicker
                    }

                    settingsSection(title: "Safety & privacy") {
                        NavigationLink { BlockedMembersView() } label: {
                            settingsLabel("Blocked members", systemImage: "hand.raised.slash.fill")
                        }
                        Divider()
                        NavigationLink { PrivacySummaryView() } label: {
                            settingsLabel("Privacy summary", systemImage: "hand.raised.fill")
                        }
                        Divider()
                        NavigationLink { GuidelinesView() } label: {
                            settingsLabel("Community guidelines", systemImage: "person.2.badge.gearshape")
                        }
                        if let privacyURL = AppIdentity.privacyURL {
                            Divider()
                            Link(destination: privacyURL) { settingsLabel("Privacy policy", systemImage: "safari") }
                        }
                        if let termsURL = AppIdentity.termsURL {
                            Divider()
                            Link(destination: termsURL) { settingsLabel("Terms of use", systemImage: "doc.text") }
                        }
                        Divider()
                        Link(destination: URL(string: "mailto:\(AppIdentity.supportEmail)") ?? URL(fileURLWithPath: "/")) {
                            settingsLabel("Support", systemImage: "questionmark.circle")
                        }
                    }

                    settingsSection(title: "Account") {
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { showSignOut = true }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("profile.signOut")
                        Divider()
                        Button("Delete account", systemImage: "trash", role: .destructive) { showDelete = true }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("profile.deleteAccount")
                    }
                }
                .padding(AppSpacing.page)
                .padding(.bottom, 24)
            }
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .roundPage()
            .sheet(isPresented: $showEditName) { EditNameView() }
            .sheet(isPresented: $showCreateGroup) { CreateGroupView() }
            .sheet(isPresented: $showJoinGroup) { JoinGroupView() }
            .confirmationDialog("Add group", isPresented: $showAddGroup, titleVisibility: .visible) {
                Button("Create a group") { showCreateGroup = true }
                Button("Join with a code") { showJoinGroup = true }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Sign out of Cahoots?", isPresented: $showSignOut) { Button("Sign out", role: .destructive) { Task { await store.signOutAsync() } } }
            .alert("Delete your account?", isPresented: $showDelete) {
                Button("Delete account", role: .destructive) { Task { await store.deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This starts permanent deletion of your profile and private group data. This cannot be undone.") }
        }
    }

    private var profileHeader: some View {
        CahootsCard(elevated: true) {
            AdaptiveStack(spacing: AppSpacing.medium) {
                if let user = store.currentUser { AvatarView(user: user, size: 72) }
                VStack(alignment: .leading, spacing: AppSpacing.micro) {
                    Text(store.currentUser?.displayName ?? "Cahoots member").font(.title.bold())
                    Text(friendlyTimezoneLabel(store.currentUser?.timezoneIdentifier))
                        .font(.subheadline)
                        .foregroundStyle(AppColors.secondaryInk)
                    if store.mode == .demo { DemoModeBadge() }
                    Button("Edit name") { showEditName = true }.font(.subheadline.bold()).frame(minHeight: 44)
                }
            }
        }
    }

    private func friendlyTimezoneLabel(_ identifier: String?) -> String {
        let id = identifier ?? TimeZone.current.identifier
        let city = id.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? id
        return "\(city) time"
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        CahootsSettingsSection(title) { content() }
    }

    private func settingsLabel(_ title: String, systemImage: String) -> some View {
        CahootsSettingsLabel(title: title, systemImage: systemImage)
    }

    private func groupRow(_ group: CahootsGroup) -> some View {
        let membershipRole = role(group)
        let isSelected = group.id == store.currentGroup?.id
        return Button {
            store.selectGroup(group.id)
        } label: {
            AdaptiveStack(spacing: AppSpacing.small) {
                Text(group.emoji)
                Text(group.name).foregroundStyle(AppColors.ink)
                Spacer(minLength: 0)
                StatusPill(text: membershipRole.rawValue.capitalized)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("profile.group.\(group.id.uuidString)")
    }
    private func role(_ group: CahootsGroup) -> GroupRole { store.snapshot?.memberships.first { $0.groupID == group.id && $0.userID == store.currentUser?.id && $0.status == .active }?.role ?? .member }
    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(get: { store.snapshot?.appearance ?? .system }, set: { value in Task { await store.setAppearance(value) } })
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Label("Theme", systemImage: "paintpalette.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: AppSpacing.small)], spacing: AppSpacing.small) {
                ForEach(AppColorTheme.allCases) { theme in
                    Button {
                        store.setColorTheme(theme)
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(theme.swatchSoft)
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(theme.swatchBold)
                                    .padding(10)
                                    .offset(x: 6, y: 6)
                            }
                            .frame(height: 56)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        store.colorTheme == theme ? AppColors.ink : AppColors.ink.opacity(0.12),
                                        lineWidth: store.colorTheme == theme ? 2.5 : 1
                                    )
                            }
                            Text(theme.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(store.colorTheme == theme ? AppColors.ink : AppColors.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.displayName)
                    .accessibilityAddTraits(store.colorTheme == theme ? [.isSelected] : [])
                    .accessibilityIdentifier("profile.theme.\(theme.rawValue)")
                }
            }
        }
    }
}

private struct EditNameView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppSpacing.large) {
                    CahootsSettingsSection("Display name") {
                        TextField("Display name", text: $name)
                            .textInputAutocapitalization(.words)
                            .frame(minHeight: 44)
                    }
                }
                .padding(AppSpacing.page)
                .padding(.bottom, 24)
            }
            .roundPage()
            .interactiveKeyboardDismiss()
            .navigationTitle("Edit name").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                isSaving = true
                                defer { isSaving = false }
                                await store.updateDisplayName(name)
                                dismiss()
                            }
                        }
                        .disabled(TextSanitizer.clean(name).count < 2)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .keyboardDoneToolbar()
            .onAppear { name = store.currentUser?.displayName ?? "" }
        }
    }
}

struct NotificationSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var settings: UserNotificationSettings?
    @State private var savedStatus: String?
    @State private var autosaveFailed = false
    @State private var confirmLeaveAfterFailure = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.large) {
                if settings != nil {
                    CahootsSettingsSection("Default reminder") {
                        DatePicker("Reminder time", selection: minutesBinding(\.defaultReminderMinutes), displayedComponents: .hourAndMinute)
                            .frame(minHeight: 44)
                        Divider()
                        authorizationControl
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                        if let savedStatus {
                            Divider()
                            Label(savedStatus, systemImage: autosaveFailed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(autosaveFailed ? AppColors.danger : AppColors.accent)
                                .accessibilityIdentifier("notifications.saved")
                        }
                    }
                    ForEach(store.activeGroups) { group in
                        CahootsSettingsSection("\(group.emoji) \(group.name)") {
                            if let deadlineLabel = dailyDeadlineLabel(for: group.id) {
                                Text("Daily check-in deadline · \(deadlineLabel)")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.secondaryInk)
                                Divider()
                            }
                            Toggle("Scheduled reminders", isOn: groupBinding(group.id, \.personalRemindersEnabled))
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("notifications.reminders.\(group.id.uuidString)")
                            Divider()
                            Toggle("Votes & round updates", isOn: groupBinding(group.id, \.challengeUpdatesEnabled))
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("notifications.challengeUpdates.\(group.id.uuidString)")
                            Text("Vote opened, vote closing soon, and round starting alerts for this crew.")
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryInk)
                            Divider()
                            Picker("Friend activity", selection: groupBinding(group.id, \.friendActivityMode)) {
                                Text("Immediate").tag(NotificationLevel.immediate)
                                Text("Daily digest").tag(NotificationLevel.digest)
                                Text("Off").tag(NotificationLevel.off)
                            }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("notifications.friendActivity.\(group.id.uuidString)")
                            Text("When someone posts a check-in. Separate from votes and round updates.")
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryInk)
                            if reminderIsAfterDeadline(for: group.id) {
                                Divider()
                                Label("Reminder time is after this crew’s daily deadline. You may get nudged after the window closes.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.warning)
                                    .accessibilityIdentifier("notifications.deadlineWarning.\(group.id.uuidString)")
                            }
                        }
                    }
                    CahootsSettingsSection("Quiet hours") {
                        DatePicker("Starts", selection: minutesBinding(\.quietHoursStart), displayedComponents: .hourAndMinute)
                            .frame(minHeight: 44)
                        Divider()
                        DatePicker("Ends", selection: minutesBinding(\.quietHoursEnd), displayedComponents: .hourAndMinute)
                            .frame(minHeight: 44)
                        Divider()
                        Text("Cahoots never includes detailed workout quantities in lock-screen notifications.")
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                }
            }
            .padding(AppSpacing.page)
            .padding(.bottom, 24)
        }
        .roundPage()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(autosaveFailed)
        .toolbar {
            if autosaveFailed {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { confirmLeaveAfterFailure = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let savedStatus {
                    Text(savedStatus)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(autosaveFailed ? AppColors.danger : AppColors.accent)
                        .accessibilityIdentifier("notifications.autosaveStatus")
                }
            }
        }
        .confirmationDialog("Leave without saving?", isPresented: $confirmLeaveAfterFailure, titleVisibility: .visible) {
            Button("Leave without saving", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Cahoots couldn’t save your latest notification changes. Keep editing to try again.")
        }
        .onAppear {
            if let existing = store.snapshot?.notificationSettings {
                settings = existing
            } else if let user = store.currentUser {
                settings = .defaults(userID: user.id, groups: store.activeGroups)
            }
        }
    }

    @ViewBuilder
    private var authorizationControl: some View {
        switch store.notificationAuthorizationState {
        case .undetermined:
            Button("Enable notifications") { Task { await store.requestNotifications() } }
                .buttonStyle(PrimaryButtonStyle())
        case .denied:
            Button("Open iOS Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                .buttonStyle(SecondaryButtonStyle())
        case .authorized, .provisional:
            Label("Notifications enabled", systemImage: "checkmark.circle.fill").foregroundStyle(AppColors.accent)
        }
    }

    private func groupBinding<Value>(_ groupID: UUID, _ keyPath: WritableKeyPath<GroupNotificationSettings, Value>) -> Binding<Value> {
        Binding {
            guard let setting = settings?.groups.first(where: { $0.groupID == groupID }) else {
                return GroupNotificationSettings.defaults(groupID: groupID)[keyPath: keyPath]
            }
            return setting[keyPath: keyPath]
        } set: { value in
            guard var current = settings else { return }
            if let index = current.groups.firstIndex(where: { $0.groupID == groupID }) {
                current.groups[index][keyPath: keyPath] = value
            } else {
                var group = GroupNotificationSettings.defaults(groupID: groupID)
                group[keyPath: keyPath] = value
                current.groups.append(group)
            }
            settings = current
            persistAfterDebounce(current)
        }
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<UserNotificationSettings, Int>) -> Binding<Date> {
        Binding {
            let minutes = settings?[keyPath: keyPath] ?? 0
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        } set: { value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            settings?[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if let settings { persistAfterDebounce(settings) }
        }
    }

    private func challenge(for groupID: UUID) -> CahootsChallenge? {
        store.snapshot?.challenges
            .filter { $0.groupID == groupID && ($0.status == .active || $0.status == .scheduled) }
            .sorted {
                if $0.status != $1.status { return $0.status == .active }
                return $0.startDate < $1.startDate
            }
            .first
    }

    private func dailyDeadlineLabel(for groupID: UUID) -> String? {
        guard let challenge = challenge(for: groupID) else { return nil }
        var components = DateComponents()
        components.hour = challenge.dailyDeadlineMinutes / 60
        components.minute = challenge.dailyDeadlineMinutes % 60
        return Calendar.current.date(from: components)?.formatted(date: .omitted, time: .shortened)
    }

    private func effectiveReminderMinutes(for groupID: UUID) -> Int {
        if let groupMinutes = settings?.groups.first(where: { $0.groupID == groupID })?.reminderMinutes {
            return groupMinutes
        }
        return settings?.defaultReminderMinutes ?? 18 * 60
    }

    private func reminderIsAfterDeadline(for groupID: UUID) -> Bool {
        guard let challenge = challenge(for: groupID) else { return false }
        let remindersEnabled = settings?.groups.first(where: { $0.groupID == groupID })?.personalRemindersEnabled ?? true
        guard remindersEnabled else { return false }
        return effectiveReminderMinutes(for: groupID) > challenge.dailyDeadlineMinutes
    }

    private func persistAfterDebounce(_ updated: UserNotificationSettings) {
        autosaveFailed = false
        savedStatus = String(localized: "Saving…")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard settings == updated else { return }
            let saved = await store.updateNotificationSettings(updated)
            guard settings == updated else { return }
            autosaveFailed = !saved
            savedStatus = saved ? String(localized: "Saved") : String(localized: "Couldn’t save changes")
            if saved {
                try? await Task.sleep(for: .seconds(2))
                if settings == updated { savedStatus = nil }
            }
        }
    }
}

private struct BlockedMembersView: View {
    @Environment(AppStore.self) private var store

    private var members: [CahootsUser] {
        guard let snapshot = store.snapshot else { return [] }
        let blockedIDs = Set(snapshot.blockedUsers.filter { $0.blockerID == snapshot.currentUser.id }.map(\.blockedUserID))
        return snapshot.users.filter { blockedIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.medium) {
                ForEach(members) { member in
                    CahootsCard {
                        VStack(alignment: .leading, spacing: AppSpacing.medium) {
                            HStack(spacing: AppSpacing.medium) {
                                AvatarView(user: member)
                                Text(member.displayName).font(.headline)
                                Spacer(minLength: 0)
                            }
                            Button("Unblock") { Task { await store.unblock(userID: member.id) } }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
            }
            .padding(AppSpacing.page)
            .padding(.bottom, 24)
        }
        .roundPage()
        .navigationTitle("Blocked members")
        .overlay {
            if members.isEmpty {
                ContentUnavailableView("No blocked members", systemImage: "hand.raised.slash", description: Text("People you block will appear here."))
            }
        }
    }
}

struct PrivacySummaryView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.large) {
                CahootsSettingsSection("Private by default") {
                    Label("Invite-only groups", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                    Divider()
                    Label("No public discovery", systemImage: "eye.slash.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                    Divider()
                    Label("No location sharing", systemImage: "location.slash.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                    Divider()
                    Label("Private group workout clips only", systemImage: "video.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                CahootsSettingsSection("Workout privacy") {
                    Text("Friends see who posted and when. Quantities, points, and clips stay hidden until you check in, use a recovery day, or the daily deadline passes. Clips are kept until about two days after that day’s deadline, until you check in on a newer day, or until the round ends.")
                }
                CahootsSettingsSection("Control") {
                    Text("You can leave groups, mute friend activity, block or report members, and delete your account.")
                }
            }
            .padding(AppSpacing.page)
            .padding(.bottom, 24)
        }
        .roundPage()
        .navigationTitle("Privacy")
    }
}

struct GuidelinesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text("Friendly accountability").font(.largeTitle.bold())
                Text("Encourage reasonable consistency. Respect recovery, privacy and different ability levels. Never pressure someone to disclose health information or complete unsafe volume.")
                Text("Reports are reviewed under the group safety process. Immediate danger should be reported to the relevant local service.").foregroundStyle(AppColors.secondaryInk)
            }
            .padding(AppSpacing.page)
        }
        .navigationTitle("Guidelines")
        .navigationBarTitleDisplayMode(.inline)
    }
}
