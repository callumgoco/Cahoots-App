import SwiftUI
import UIKit

enum AppColors {
    private static let nearBlack = UIColor(red: 5 / 255, green: 5 / 255, blue: 5 / 255, alpha: 1)
    private static let mint = UIColor(red: 215 / 255, green: 255 / 255, blue: 224 / 255, alpha: 1)
    private static let darkCard = UIColor(red: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1)
    private static let darkRaised = UIColor(red: 26 / 255, green: 26 / 255, blue: 26 / 255, alpha: 1)
    /// Slightly deeper mint so cards lift off the light page.
    private static let lightCard = UIColor(red: 197 / 255, green: 242 / 255, blue: 210 / 255, alpha: 1)
    private static let lightRaised = UIColor(red: 186 / 255, green: 235 / 255, blue: 201 / 255, alpha: 1)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let page = adaptive(light: mint, dark: nearBlack)
    static let card = adaptive(light: lightCard, dark: darkCard)
    static let raised = adaptive(light: lightRaised, dark: darkRaised)
    static let ink = adaptive(light: nearBlack, dark: mint)
    /// Label / icon color on ink-filled controls (equals page in this invert).
    static let onInk = adaptive(light: mint, dark: nearBlack)
    static let secondaryInk = ink.opacity(0.6)
    static let brand = ink
    static let accent = ink
    static let accentSoft = ink.opacity(0.14)
    static let warning = Color.orange
    static let danger = Color.red
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
        content
            .padding(AppSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            .background(AppColors.ink.opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.28), in: Capsule())
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
            .scaleEffect(!reduceMotion && configuration.isPressed && isEnabled ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppMotion.responsive, value: configuration.isPressed)
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
        case .waiting, .failed: String(localized: "Your workout is saved and will update when you’re back online.")
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
        case .missed: AppColors.secondaryInk.opacity(0.12)
        case .rest, .upcoming: AppColors.card
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
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [background, background.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: size * 0.55, height: size * 0.55)
                .offset(x: -size * 0.18, y: -size * 0.16)
            Image(systemName: mark.symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
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
                    .overlay(Circle().stroke(AppColors.card, lineWidth: 3))
            }
            if users.count > 5 {
                Text("+\(users.count - 5)")
                    .font(.caption.bold())
                    .frame(width: 38, height: 38)
                    .background(AppColors.ink, in: Circle())
                    .foregroundStyle(AppColors.onInk)
                    .overlay(Circle().stroke(AppColors.card, lineWidth: 3))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(users.count) group members")
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
            .background(Color.orange)
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

struct LoadingSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 0.35

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            RoundedRectangle(cornerRadius: AppRadius.card).frame(height: 220)
            HStack {
                RoundedRectangle(cornerRadius: AppRadius.control).frame(height: 96)
                RoundedRectangle(cornerRadius: AppRadius.control).frame(height: 96)
            }
        }
        .foregroundStyle(AppColors.secondaryInk.opacity(opacity))
        .padding(AppSpacing.page)
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { opacity = 0.12 }
        }
        .accessibilityLabel("Loading")
    }
}

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
                .frame(width: 96, height: 96)
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
