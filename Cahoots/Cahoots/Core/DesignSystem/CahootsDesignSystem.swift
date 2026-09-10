import SwiftUI
import UIKit

enum AppColors {
    private static func themed(_ keyPath: KeyPath<AppThemePalette, UIColor>) -> Color {
        Color(uiColor: UIColor { traits in
            AppColorThemeBridge.current.palette(for: traits.userInterfaceStyle)[keyPath: keyPath]
        })
    }

    /// Soft page wash in light mode; bold/near-black wash in dark mode (per active theme).
    static var page: Color { themed(\.page) }
    /// Charcoal (or theme-dark) cards so light mode keeps dark surfaces on the soft page.
    static var card: Color { themed(\.card) }
    static var raised: Color { themed(\.raised) }
    /// Page chrome / primary type on the page background.
    static var ink: Color { themed(\.ink) }
    /// Label / icon color on ink-filled controls (equals page in this invert).
    static var onInk: Color { themed(\.onInk) }
    static var secondaryInk: Color { ink.opacity(0.6) }
    /// Soft fill for small page-level chips that should not read as full cards.
    static var chip: Color { themed(\.chip) }
    static var brand: Color { ink }
    static var accent: Color { ink }
    static var accentSoft: Color { ink.opacity(0.14) }
    /// Semantic success (completion chips, positive status).
    static let success = Color(uiColor: UIColor(hex: 0x22C55E))
    /// Semantic warning (offline, deadline nudges).
    static let warning = Color(uiColor: UIColor(hex: 0xF59E0B))
    /// Semantic danger (errors, destructive emphasis).
    static let danger = Color(uiColor: UIColor(hex: 0xEF4444))
}

enum AppSpacing {
    static let micro: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
    static let page: CGFloat = 20
}

enum AppRadius {
    static let card: CGFloat = 22
    static let control: CGFloat = 16
    static let small: CGFloat = 12
}

enum AppShadow {
    static let color = Color.black.opacity(0.06)
    static let radius: CGFloat = 16
    static let y: CGFloat = 6
}

enum AppMotion {
    static let responsive = Animation.spring(duration: 0.28, bounce: 0.15)
    static let calm = Animation.easeInOut(duration: 0.22)
}

enum AppTypography {
    static let heroMetric = Font.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit()
    static let resultMetric = Font.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit()
    static let screenTitle = Font.largeTitle.bold()
    static let cardTitle = Font.title3.bold()
    static let metric = Font.title.bold().monospacedDigit()
    static let label = Font.subheadline.weight(.semibold)
}

struct CahootsCard<Content: View>: View {
    let elevated: Bool
    @ViewBuilder let content: Content

    init(elevated: Bool = false, @ViewBuilder content: () -> Content) {
        self.elevated = elevated
        self.content = content()
    }

    var body: some View {
        // Force dark-scheme tokens inside cards so light mode gets mint type on charcoal surfaces.
        content
            .padding(AppSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.colorScheme, .dark)
            .background(elevated ? AppColors.raised : AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .shadow(color: elevated ? AppShadow.color : .clear, radius: AppShadow.radius, y: AppShadow.y)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(AppColors.onInk)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, AppSpacing.medium)
            .background(AppColors.ink.opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.38), in: Capsule())
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppMotion.responsive, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(AppColors.ink.opacity(isEnabled ? 1 : 0.35))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, AppSpacing.medium)
            .background(AppColors.card.opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.55), in: Capsule())
            .environment(\.colorScheme, .dark)
            .scaleEffect(!reduceMotion && configuration.isPressed && isEnabled ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppMotion.responsive, value: configuration.isPressed)
    }
}

/// Quiet CTA for when a filled dark button already owns the screen (e.g. Sign in with Apple).
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(AppColors.ink.opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.35))
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, AppSpacing.medium)
            .background(AppColors.ink.opacity(configuration.isPressed ? 0.08 : 0.04), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(AppColors.ink.opacity(isEnabled ? 0.28 : 0.12), lineWidth: 1.5)
            )
            .scaleEffect(!reduceMotion && configuration.isPressed && isEnabled ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppMotion.responsive, value: configuration.isPressed)
    }
}

/// Soft page-level text field chrome — mint chip surface, not charcoal cards.
struct CahootsField<Content: View>: View {
    let title: String
    var isFocused: Bool = false
    @ViewBuilder let content: Content

    init(title: String, isFocused: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isFocused = isFocused
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryInk)
            }
            content
                .cahootsFieldChrome(focused: isFocused)
        }
    }
}

extension View {
    /// Soft chip field surface for inputs sitting on `AppColors.page`.
    func cahootsFieldChrome(focused: Bool = false) -> some View {
        padding(.horizontal, AppSpacing.medium)
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .leading)
            .foregroundStyle(AppColors.ink)
            .tint(AppColors.ink)
            .background(AppColors.chip, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .strokeBorder(AppColors.ink.opacity(focused ? 0.4 : 0.1), lineWidth: focused ? 1.5 : 1)
            )
    }

    /// Continuous page-colored footer for sheet CTAs (avoids the mint/white bar split).
    func cahootsSheetFooter() -> some View {
        padding(.horizontal, AppSpacing.page)
            .padding(.top, AppSpacing.medium)
            .padding(.bottom, AppSpacing.page)
            .background(
                AppColors.page
                    .shadow(color: AppColors.ink.opacity(0.05), radius: 20, y: -10)
                    .mask(Rectangle().padding(.top, -32))
            )
    }
}

enum AvatarMark: Hashable, Sendable {
    case leaf, flame, wave, star, mountain, bolt, moon, sun

    var symbolName: String {
        switch self {
        case .leaf: "leaf.fill"
        case .flame: "flame.fill"
        case .wave: "water.waves"
        case .star: "star.fill"
        case .mountain: "mountain.2.fill"
        case .bolt: "bolt.fill"
        case .moon: "moon.fill"
        case .sun: "sun.max.fill"
        }
    }

    static let all: [AvatarMark] = [.leaf, .flame, .wave, .star, .mountain, .bolt, .moon, .sun]

    static func forUser(_ userID: UUID) -> AvatarMark {
        all[stableIndex(for: userID, modulo: all.count)]
    }

    static func paletteColor(for userID: UUID) -> Color {
        let palette: [(Double, Double, Double)] = [
            (0.18, 0.55, 0.42),
            (0.22, 0.42, 0.62),
            (0.55, 0.32, 0.48),
            (0.52, 0.40, 0.22),
            (0.28, 0.48, 0.55),
            (0.42, 0.28, 0.58),
            (0.20, 0.50, 0.50),
            (0.48, 0.35, 0.30)
        ]
        let rgb = palette[stableIndex(for: userID, modulo: palette.count)]
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private static func stableIndex(for userID: UUID, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        var hasher = Hasher()
        hasher.combine(userID)
        let hash = hasher.finalize()
        return abs(hash) % modulo
    }
}

enum FriendFacingCopy {
    static func syncLabel(for state: SyncState) -> String {
        switch state {
        case .synced: String(localized: "Synced")
        case .waiting, .failed: String(localized: "Saved on this phone")
        case .rejected: String(localized: "Check-in wasn’t accepted")
        }
    }

    static func syncExplanation(for state: SyncState) -> String {
        switch state {
        case .synced: String(localized: "Your streak and position are updated.")
        case .waiting: String(localized: "Syncing to your crew now…")
        case .failed: String(localized: "Couldn’t reach the crew yet. Tap Retry.")
        case .rejected: String(localized: "This check-in didn’t meet the round rules.")
        }
    }

    static let missedWindow = String(localized: "Missed today’s window")
    static let savedOnPhone = String(localized: "Saved on this phone")
}

enum WeekDayTokenState: Equatable, Sendable {
    case today
    case done
    case missed
    case rest
    case recovery
    case upcoming
}

struct WeekDayToken: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let weekdayLabel: String
    let state: WeekDayTokenState
}

enum WeekStripBuilder {
    static func tokens(
        challenge: CahootsChallenge,
        userID: UUID,
        submissions: [Submission],
        recoveries: [RecoveryDayUsage],
        now: Date = .now
    ) -> [WeekDayToken] {
        guard let calendar = ScheduleEngine.calendar(for: challenge) else { return [] }
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else { return [] }

        let accepted = submissions.filter {
            $0.challengeID == challenge.id && $0.userID == userID && $0.syncState != .rejected &&
            ScoringEngine.points(completedQuantity: $0.quantity, minimumQuantity: challenge.minimumQuantity) > 0
        }
        let completedDays = Set(accepted.compactMap { ScheduleEngine.requirementDay(for: $0.requirementDate, challenge: challenge) })
        let recoveryDays = Set(
            recoveries
                .filter { $0.challengeID == challenge.id && $0.userID == userID }
                .compactMap { ScheduleEngine.requirementDay(for: $0.requirementDate, challenge: challenge) }
        )

        return (0..<7).compactMap { offset -> WeekDayToken? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let label = String(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: day) - 1].prefix(1))
            let state = tokenState(
                day: day,
                today: today,
                challenge: challenge,
                completedDays: completedDays,
                recoveryDays: recoveryDays,
                now: now
            )
            return WeekDayToken(date: day, weekdayLabel: label, state: state)
        }
    }

    private static func tokenState(
        day: Date,
        today: Date,
        challenge: CahootsChallenge,
        completedDays: Set<Date>,
        recoveryDays: Set<Date>,
        now: Date
    ) -> WeekDayTokenState {
        if day > today { return ScheduleEngine.isScheduled(on: day, challenge: challenge) ? .upcoming : .rest }
        if recoveryDays.contains(day) { return .recovery }
        if completedDays.contains(day) { return .done }
        if day == today {
            return ScheduleEngine.isScheduled(on: day, challenge: challenge) ? .today : .rest
        }
        guard ScheduleEngine.isScheduled(on: day, challenge: challenge) else { return .rest }
        if let deadline = ScheduleEngine.deadline(for: day, challenge: challenge), deadline < now {
            return .missed
        }
        return .upcoming
    }
}

struct WeekStrip: View {
    let tokens: [WeekDayToken]

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            ForEach(tokens) { token in
                VStack(spacing: 6) {
                    Text(token.weekdayLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryInk)
                    Circle()
                        .fill(fill(for: token.state))
                        .frame(width: 28, height: 28)
                        .overlay {
                            if token.state == .done {
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(AppColors.onInk)
                            } else if token.state == .recovery {
                                Image(systemName: "moon.fill")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.accent)
                            } else if token.state == .today {
                                Circle()
                                    .stroke(AppColors.accent, lineWidth: 2)
                                    .padding(2)
                            } else if token.state == .missed {
                                Image(systemName: "xmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(AppColors.secondaryInk)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(token.weekdayLabel), \(accessibilityLabel(for: token.state))")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func fill(for state: WeekDayTokenState) -> Color {
        switch state {
        case .done: AppColors.accent
        case .today: AppColors.accentSoft
        case .recovery: AppColors.accentSoft
        case .missed: AppColors.secondaryInk.opacity(0.18)
        case .rest: AppColors.chip.opacity(0.55)
        case .upcoming: AppColors.chip
        }
    }

    private func accessibilityLabel(for state: WeekDayTokenState) -> String {
        switch state {
        case .today: String(localized: "today")
        case .done: String(localized: "completed")
        case .missed: String(localized: "missed")
        case .rest: String(localized: "rest day")
        case .recovery: String(localized: "recovery day")
        case .upcoming: String(localized: "upcoming")
        }
    }
}

struct AvatarView: View {
    let user: CahootsUser
    var size: CGFloat = 44

    private var mark: AvatarMark { AvatarMark.forUser(user.id) }
    private var background: Color { AvatarMark.paletteColor(for: user.id) }

    var body: some View {
        // Highlight lives in an overlay so its offset cannot expand layout and clip the fill.
        Circle()
            .fill(
                LinearGradient(
                    colors: [background, background.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size * 0.55, height: size * 0.55)
                    .offset(x: -size * 0.18, y: -size * 0.16)
                    .allowsHitTesting(false)
            }
            .overlay {
                Image(systemName: mark.symbolName)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityLabel(user.displayName)
    }
}

struct AvatarStack: View {
    let users: [CahootsUser]

    var body: some View {
        HStack(spacing: -10) {
            ForEach(users.prefix(5)) { user in
                AvatarView(user: user, size: 38)
                    .overlay(Circle().stroke(AppColors.page, lineWidth: 3))
            }
            if users.count > 5 {
                Text("+\(users.count - 5)")
                    .font(.caption.bold())
                    .frame(width: 38, height: 38)
                    .background(AppColors.ink, in: Circle())
                    .foregroundStyle(AppColors.onInk)
                    .overlay(Circle().stroke(AppColors.page, lineWidth: 3))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(users.count) group members")
    }
}

/// Full-roster “who’s done today” rail — spoiler-safe (no quantities).
struct CrewTodayStatusRail: View {
    let entries: [TodayMemberStatusEntry]
    var title: String = String(localized: "Today’s crew")
    var avatarSize: CGFloat = 44
    var accessibilityID: String? = nil
    var onSelectMember: ((TodayMemberStatusEntry) -> Void)? = nil

    private var summary: String? {
        CrewAccountabilityCopy.checkInSummary(entries: entries)
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryInk)
                if let summary {
                    Text(summary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("crew.accountabilitySummary")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.medium) {
                        ForEach(entries) { entry in
                            memberCell(entry)
                        }
                    }
                    // Room for the status ring and badge so ScrollView does not clip them.
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
            }
            .modifier(OptionalAccessibilityIdentifier(accessibilityID))
        }
    }

    @ViewBuilder
    private func memberCell(_ entry: TodayMemberStatusEntry) -> some View {
        let content = VStack(spacing: 6) {
            AvatarView(user: entry.user, size: avatarSize)
                .overlay {
                    Circle()
                        .stroke(ringColor(for: entry.status), lineWidth: entry.status == .pending ? 1.5 : 2.5)
                }
                .padding(3)
                .overlay(alignment: .bottomTrailing) {
                    statusBadge(for: entry.status)
                        .offset(x: 2, y: 2)
                }
            Text(entry.isCurrentUser
                  ? String(localized: "You")
                  : (entry.user.displayName.split(separator: " ").first.map(String.init) ?? entry.user.displayName))
                .font(.caption2.bold())
                .foregroundStyle(AppColors.ink)
                .lineLimit(1)
        }
        .frame(width: max(72, avatarSize + 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.isCurrentUser ? String(localized: "You") : entry.user.displayName), \(statusLabel(for: entry.status))")

        if let onSelectMember {
            Button {
                onSelectMember(entry)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private func ringColor(for status: TodayMemberStatus) -> Color {
        switch status {
        case .done: AppColors.ink
        case .rest: AppColors.secondaryInk
        case .pending: AppColors.secondaryInk.opacity(0.35)
        }
    }

    @ViewBuilder
    private func statusBadge(for status: TodayMemberStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(AppColors.onInk)
                .background(AppColors.ink, in: Circle())
        case .rest:
            Image(systemName: "moon.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(AppColors.secondaryInk)
                .background(AppColors.page, in: Circle())
        case .pending:
            EmptyView()
        }
    }

    private func statusLabel(for status: TodayMemberStatus) -> String {
        switch status {
        case .done: String(localized: "done")
        case .rest: String(localized: "rest day")
        case .pending: String(localized: "pending")
        }
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let id: String?

    init(_ id: String?) { self.id = id }

    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

struct MetricTile: View {
    let value: String
    let label: String
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.micro) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.body.bold())
                    .foregroundStyle(AppColors.secondaryInk)
            }
            Text(value)
                .font(AppTypography.metric)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppColors.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .padding(AppSpacing.medium)
        .environment(\.colorScheme, .dark)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct StatusPill: View {
    enum Kind { case positive, neutral, warning, pending, negative }
    let text: String
    var kind: Kind = .neutral
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var color: Color {
        switch kind {
        case .positive: AppColors.accent
        case .neutral: AppColors.secondaryInk
        case .warning: AppColors.warning
        case .pending: AppColors.ink
        case .negative: AppColors.danger
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(color)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? AppRadius.small : 100, style: .continuous))
    }
}

struct CahootsSectionHeader: View {
    let title: String
    var action: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(AppTypography.cardTitle)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

struct OfflineBanner: View {
    var body: some View {
        Label("Offline · check-ins will wait to sync", systemImage: "wifi.slash")
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(Color.black)
            .background(AppColors.warning)
            .accessibilityLabel("Offline. Check-ins will wait to sync.")
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("banner.dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.small))
        .foregroundStyle(AppColors.danger)
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.micro)
        .accessibilityElement(children: .contain)
    }
}

struct NoticeBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "checkmark.circle.fill")
            Text(message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.accentSoft, in: RoundedRectangle(cornerRadius: AppRadius.small))
        .foregroundStyle(AppColors.ink)
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.micro)
    }
}

struct DemoModeBadge: View {
    var body: some View {
        Label("Demo data", systemImage: "sparkles")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel("Demo data")
    }
}

struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let horizontalAlignment: VerticalAlignment
    let verticalAlignment: HorizontalAlignment
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(
        horizontalAlignment: VerticalAlignment = .center,
        verticalAlignment: HorizontalAlignment = .leading,
        spacing: CGFloat = AppSpacing.small,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: verticalAlignment, spacing: spacing) { content }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: horizontalAlignment, spacing: spacing) { content }
                VStack(alignment: verticalAlignment, spacing: spacing) { content }
            }
        }
    }
}

struct AppBannerHost: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            if store.isOffline { OfflineBanner() }
            if let error = store.errorBanner {
                ErrorBanner(message: error) { store.errorBanner = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let notice = store.noticeBanner {
                NoticeBanner(message: notice) { store.noticeBanner = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AppMotion.calm, value: store.errorBanner)
        .animation(AppMotion.calm, value: store.noticeBanner)
        .task(id: store.noticeBanner) {
            guard store.errorBanner == nil, let notice = store.noticeBanner else { return }
            UIAccessibility.post(notification: .announcement, argument: notice)
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, store.noticeBanner == notice else { return }
            store.noticeBanner = nil
        }
        .onChange(of: store.errorBanner) { _, error in
            if let error { UIAccessibility.post(notification: .announcement, argument: error) }
        }
    }
}

/// Full-page brand loader used while the signed-in session hydrates.
struct BrandLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var spinAngle: Double = 0
    @State private var breathe = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            atmosphere

            VStack(spacing: AppSpacing.large) {
                Image("LoadingMark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(AppColors.ink)
                    .frame(width: 92, height: 92)
                    .rotationEffect(.degrees(spinAngle))
                    .scaleEffect(reduceMotion ? 1 : (breathe ? 1.05 : 0.96))
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)

                Text("Getting your crew ready")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryInk)
                    .opacity(appeared ? (reduceMotion ? 0.75 : (breathe ? 0.9 : 0.55)) : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private var atmosphere: some View {
        ZStack {
            Circle()
                .fill(AppColors.ink.opacity(colorScheme == .dark ? 0.14 : 0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 42)
                .scaleEffect(breathe ? 1.18 : 0.88)
            Circle()
                .fill(AppColors.chip.opacity(colorScheme == .dark ? 0.55 : 0.85))
                .frame(width: 120, height: 120)
                .blur(radius: 18)
                .scaleEffect(breathe ? 0.9 : 1.12)
                .opacity(0.7)
        }
        .opacity(appeared ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @MainActor
    private func play() async {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : AppMotion.calm) {
            appeared = true
        }

        guard !reduceMotion else { return }

        withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
            breathe = true
        }
        // 3-fold mark: a full turn reads as a continuous chase around the ring.
        withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
            spinAngle = 360
        }
    }
}

#if DEBUG
#Preview("Brand loading") {
    BrandLoadingView()
        .roundPage()
}
#endif

struct CahootsEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    init(symbol: String, title: String, message: String, actionTitle: String = "", action: @escaping () -> Void = {}) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(AppColors.ink)
                .frame(width: 96, height: 96)
                .environment(\.colorScheme, .dark)
                .background(AppColors.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            VStack(spacing: AppSpacing.small) {
                Text(title).font(.title.bold()).multilineTextAlignment(.center)
                Text(message).foregroundStyle(AppColors.secondaryInk).multilineTextAlignment(.center)
            }
            if !actionTitle.isEmpty { Button(actionTitle, action: action).buttonStyle(PrimaryButtonStyle()) }
        }
        .padding(AppSpacing.extraLarge)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    func roundPage() -> some View {
        background(AppColors.page.ignoresSafeArea())
    }

    /// Hides system Form/List grouped chrome so sheets match the mint/near-black page.
    func roundFormChrome() -> some View {
        scrollContentBackground(.hidden)
            .background(AppColors.page.ignoresSafeArea())
    }
}

/// Shared settings block used by Profile, Group settings, and notification sheets.
struct CahootsSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryInk)
                    .padding(.horizontal, 4)
            }
            CahootsCard {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    content
                }
            }
        }
    }
}

struct CahootsSettingsLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
