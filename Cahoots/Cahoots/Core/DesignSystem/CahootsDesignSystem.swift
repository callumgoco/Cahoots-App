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
    /// Full-ink community highlight (Pushr-style inverted emphasis on the soft page).
    let emphasis: Bool
    @ViewBuilder let content: Content

    init(elevated: Bool = false, emphasis: Bool = false, @ViewBuilder content: () -> Content) {
        self.elevated = elevated
        self.emphasis = emphasis
        self.content = content()
    }

    var body: some View {
        // Non-emphasis cards force dark-scheme tokens so light mode gets soft type on charcoal.
        // Emphasis uses real appearance tokens (ink fill + onInk type) so light mode stays readable.
        Group {
            if emphasis {
                content
                    .padding(AppSpacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(AppColors.onInk)
            } else {
                content
                    .padding(AppSpacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(AppColors.ink)
                    .environment(\.colorScheme, .dark)
            }
        }
        .background(backgroundFill, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay {
            if elevated && !emphasis {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColors.ink.opacity(0.14), lineWidth: 1)
            }
        }
        .shadow(
            color: elevated || emphasis ? (emphasis ? Color.black.opacity(0.18) : AppShadow.color) : .clear,
            radius: emphasis ? 20 : AppShadow.radius,
            y: emphasis ? 8 : AppShadow.y
        )
    }

    private var backgroundFill: Color {
        if emphasis { return AppColors.ink }
        return elevated ? AppColors.raised : AppColors.card
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

/// Quiet outline CTA under a filled primary (Create/Join, Record/Skip, Start now/Put to vote).
/// Matches `OutlineButtonStyle` so charcoal-filled secondaries never read as a second primary.
struct SecondaryButtonStyle: ButtonStyle {
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

/// Quiet outline CTA for paywall Restore and similar actions (same treatment as `SecondaryButtonStyle`).
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

    /// Docked page footer used by Log workout and other sticky screen actions.
    /// The fill continues through the tab bar to the bottom edge of the screen.
    func cahootsStickyActionBar() -> some View {
        padding(.horizontal, AppSpacing.page)
            .padding(.top, AppSpacing.small)
            .padding(.bottom, AppSpacing.small)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                AppColors.page
                    .frame(maxWidth: .infinity, minHeight: 420, alignment: .top)
                    .shadow(color: AppColors.ink.opacity(0.06), radius: 16, y: -8)
                    .mask(Rectangle().padding(.top, -24))
                    .ignoresSafeArea(edges: .bottom)
            }
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
                        .font(.caption2.weight(labelWeight(for: token.state)))
                        .foregroundStyle(labelColor(for: token.state))
                    Capsule(style: .continuous)
                        .fill(fill(for: token.state))
                        .frame(width: 28, height: 40)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(stroke(for: token.state), style: strokeStyle(for: token.state))
                        }
                        .overlay {
                            mark(for: token.state)
                        }
                }
                .frame(maxWidth: .infinity)
                .opacity(opacity(for: token.state))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(token.weekdayLabel), \(accessibilityLabel(for: token.state))")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func mark(for state: WeekDayTokenState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .foregroundStyle(AppColors.onInk)
        case .missed:
            Image(systemName: "xmark")
                .font(.caption2.bold())
                .foregroundStyle(AppColors.danger)
        case .recovery:
            Image(systemName: "moon.fill")
                .font(.caption2)
                .foregroundStyle(AppColors.ink)
        case .today:
            Circle()
                .fill(AppColors.ink)
                .frame(width: 6, height: 6)
        case .rest, .upcoming:
            EmptyView()
        }
    }

    private func fill(for state: WeekDayTokenState) -> Color {
        switch state {
        case .done: AppColors.ink
        case .today: AppColors.ink.opacity(0.18)
        case .recovery: AppColors.ink.opacity(0.14)
        case .missed: AppColors.danger.opacity(0.22)
        case .rest: AppColors.ink.opacity(0.08)
        case .upcoming: .clear
        }
    }

    private func stroke(for state: WeekDayTokenState) -> Color {
        switch state {
        case .today: AppColors.ink.opacity(0.9)
        case .upcoming: AppColors.ink.opacity(0.28)
        case .missed: AppColors.danger.opacity(0.45)
        case .done, .recovery, .rest: .clear
        }
    }

    private func strokeStyle(for state: WeekDayTokenState) -> StrokeStyle {
        switch state {
        case .upcoming:
            StrokeStyle(lineWidth: 1.5, dash: [3, 3])
        default:
            StrokeStyle(lineWidth: state == .today || state == .missed ? 1.5 : 0)
        }
    }

    private func labelColor(for state: WeekDayTokenState) -> Color {
        switch state {
        case .done, .today: AppColors.ink
        case .missed: AppColors.danger.opacity(0.9)
        case .recovery: AppColors.ink.opacity(0.85)
        case .rest: AppColors.secondaryInk.opacity(0.7)
        case .upcoming: AppColors.secondaryInk.opacity(0.55)
        }
    }

    private func labelWeight(for state: WeekDayTokenState) -> Font.Weight {
        switch state {
        case .done, .today, .missed: .bold
        default: .semibold
        }
    }

    private func opacity(for state: WeekDayTokenState) -> Double {
        switch state {
        case .upcoming: 0.72
        case .rest: 0.55
        default: 1
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

struct MetricShelfItem: Identifiable, Equatable, Sendable {
    let id: String
    let value: String
    let caption: String

    init(id: String? = nil, value: String, caption: String) {
        self.id = id ?? caption
        self.value = value
        self.caption = caption
    }
}

/// Quiet metric row under a hero (target / rank / streak / recovery).
struct MetricShelf: View {
    let items: [MetricShelfItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(AppColors.secondaryInk.opacity(0.18))
                        .frame(width: 1, height: 28)
                }
                VStack(spacing: AppSpacing.micro) {
                    Text(item.value)
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppColors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(item.caption)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryInk)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map { "\($0.value) \($0.caption)" }.joined(separator: ", "))
    }
}

enum CircularIconButtonStyle {
    case material
    case solid
    case ink
}

/// Soft-shadowed circular chrome for back / add / flip / close.
struct CircularIconButton: View {
    let systemName: String
    var style: CircularIconButtonStyle = .solid
    var accessibilityLabel: String
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.bold())
                .foregroundStyle(foreground)
                .frame(width: 44, height: 44)
                .background(background)
                .clipShape(Circle())
                .shadow(color: AppShadow.color, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .modifier(OptionalAccessibilityIdentifier(accessibilityIdentifier))
    }

    private var foreground: Color {
        switch style {
        case .material, .solid: .white
        case .ink: AppColors.ink
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .material:
            Circle().fill(.ultraThinMaterial)
        case .solid:
            Circle().fill(Color.black.opacity(0.35))
        case .ink:
            Circle().fill(AppColors.page)
        }
    }
}

/// Horizontal tick ruler for minutes-from-midnight (`0..<1440`), snapping to 5-minute steps.
struct SlidingTimeDial: View {
    @Binding var minutesFromMidnight: Int
    var stepMinutes: Int = 5

    private let totalMinutes = 24 * 60
    private let tickSpacing: CGFloat = 8
    @State private var dragOriginMinutes: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var snappedMinutes: Int {
        let clamped = min(max(minutesFromMidnight, 0), totalMinutes - stepMinutes)
        return (clamped / stepMinutes) * stepMinutes
    }

    private var displayDate: Date {
        Calendar.current.date(
            bySettingHour: snappedMinutes / 60,
            minute: snappedMinutes % 60,
            second: 0,
            of: .now
        ) ?? .now
    }

    private var stepCount: Int { totalMinutes / stepMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(displayDate.formatted(date: .omitted, time: .shortened))
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(AppColors.ink)
                .frame(maxWidth: .infinity)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .accessibilityHidden(true)

            GeometryReader { geo in
                let centerX = geo.size.width / 2
                ZStack {
                    HStack(spacing: 0) {
                        ForEach(0..<stepCount, id: \.self) { index in
                            let minutes = index * stepMinutes
                            let isHour = minutes % 60 == 0
                            let isHalfHour = minutes % 30 == 0
                            Capsule(style: .continuous)
                                .fill(AppColors.ink.opacity(isHour ? 0.85 : (isHalfHour ? 0.45 : 0.22)))
                                .frame(width: 2, height: isHour ? 28 : (isHalfHour ? 20 : 12))
                                .frame(width: tickSpacing, height: 36)
                        }
                    }
                    .offset(x: centerX - tickSpacing / 2 - CGFloat(snappedMinutes / stepMinutes) * tickSpacing)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragOriginMinutes == nil { dragOriginMinutes = snappedMinutes }
                                let origin = dragOriginMinutes ?? snappedMinutes
                                let deltaSteps = Int(round(-value.translation.width / tickSpacing))
                                let next = origin + deltaSteps * stepMinutes
                                minutesFromMidnight = min(max(next, 0), totalMinutes - stepMinutes)
                            }
                            .onEnded { _ in
                                dragOriginMinutes = nil
                                minutesFromMidnight = snappedMinutes
                            }
                    )

                    Capsule(style: .continuous)
                        .fill(AppColors.ink)
                        .frame(width: 3, height: 36)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Daily deadline"))
            .accessibilityValue(displayDate.formatted(date: .omitted, time: .shortened))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    minutesFromMidnight = min(snappedMinutes + stepMinutes, totalMinutes - stepMinutes)
                case .decrement:
                    minutesFromMidnight = max(snappedMinutes - stepMinutes, 0)
                @unknown default:
                    break
                }
            }
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
            CahootsCard {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    CahootsSectionHeader(title: title)
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

/// Full-page brand loader used while the signed-in session hydrates or refreshes.
/// Spinner only — no caption — so cold start and reload feel the same.
struct BrandLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinAngle: Double = 0
    @State private var appeared = false

    var body: some View {
        Image("LoadingMark")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: 72, height: 72)
            .rotationEffect(.degrees(spinAngle))
            .opacity(appeared ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await play() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }

    @MainActor
    private func play() async {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : AppMotion.calm) {
            appeared = true
        }

        guard !reduceMotion else { return }

        // 3-fold mark: a full turn reads as a continuous chase around the ring.
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
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

    /// Opaque nav chrome so drill-in content does not slide under the back button / title.
    func cahootsDrillInBar() -> some View {
        toolbarBackground(AppColors.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
    }

    /// Bottom inset so the last card clears the floating tab bar.
    func cahootsTabBarClearance() -> some View {
        padding(.bottom, 88)
    }
}

/// Centered confirmation for irreversible account and crew changes.
struct CahootsConfirmationSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    var isDestructive: Bool = true
    var isWorking: Bool = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(title)
                    .font(.title.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.body)
                    .foregroundStyle(AppColors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: AppSpacing.small) {
                confirmButton
                .disabled(isWorking)
                Button("Cancel", action: onCancel)
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(isWorking)
            }
        }
        .padding(AppSpacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .roundPage()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isWorking)
    }

    @ViewBuilder
    private var confirmButton: some View {
        let label = Button(action: onConfirm) {
            if isWorking {
                ProgressView()
                    .tint(isDestructive ? Color.white : AppColors.onInk)
                    .frame(maxWidth: .infinity, minHeight: 54)
            } else {
                Text(confirmTitle)
            }
        }
        if isDestructive {
            label.buttonStyle(DestructiveButtonStyle())
        } else {
            label.buttonStyle(PrimaryButtonStyle())
        }
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.7))
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, AppSpacing.medium)
            .background(
                AppColors.danger.opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.38),
                in: Capsule()
            )
            .scaleEffect(!reduceMotion && configuration.isPressed && isEnabled ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppMotion.responsive, value: configuration.isPressed)
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
