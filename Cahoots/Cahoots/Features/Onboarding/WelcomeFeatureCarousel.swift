import SwiftUI

enum WelcomeFeatureKind: Hashable, Sendable {
    case crewChallenge
    case checkInAccountability
    case consistencyLeaderboard
}

struct WelcomeFeature: Identifiable, Hashable, Sendable {
    let id: Int
    let kind: WelcomeFeatureKind
    let title: String
    let description: String

    static let all: [WelcomeFeature] = [
        .init(
            id: 0,
            kind: .crewChallenge,
            title: "Challenge your crew",
            description: "Invite your friends, agree on the rules, and take on a challenge together."
        ),
        .init(
            id: 1,
            kind: .checkInAccountability,
            title: "Show up for each other",
            description: "Check in on workout days. Your friends’ results stay hidden until you show up too."
        ),
        .init(
            id: 2,
            kind: .consistencyLeaderboard,
            title: "Win by showing up",
            description: "Earn points for consistency and climb the leaderboard with your friends."
        )
    ]
}

struct WelcomeFeatureCarousel: View {
    @Binding var selection: Int
    var cardHeight: CGFloat = 248

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let features = WelcomeFeature.all

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(features) { feature in
                            WelcomeFeaturePage(
                                feature: feature,
                                cardHeight: cardHeight,
                                showCard: !dynamicTypeSize.isAccessibilitySize
                            )
                            .frame(width: proxy.size.width, alignment: .topLeading)
                            .id(feature.id)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(feature.title). \(feature.description)")
                            .accessibilityAddTraits(selection == feature.id ? .isSelected : [])
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: Binding(
                    get: { selection },
                    set: { selection = $0 ?? selection }
                ))
            }
            // Hug: text band + spacing + card. No TabView clipping.
            .frame(height: carouselContentHeight)
            .clipped()

            WelcomePageIndicator(count: features.count, selection: selection)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Feature \(selection + 1) of \(features.count)")
                .accessibilityAddTraits(.updatesFrequently)
                .animation(reduceMotion ? nil : AppMotion.responsive, value: selection)
        }
    }

    private var carouselContentHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 200
        }
        let textBand: CGFloat = 148
        let spacing: CGFloat = 16
        return textBand + spacing + cardHeight
    }
}

private struct WelcomeFeaturePage: View {
    let feature: WelcomeFeature
    var cardHeight: CGFloat
    var showCard: Bool

    /// Fixed band so every page’s card starts at the same Y and never overlaps copy.
    private var textBandHeight: CGFloat { 148 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(feature.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(AppColors.ink)
                    .lineSpacing(-4)
                    .minimumScaleFactor(0.8)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                Text(feature.description)
                    .font(.title3)
                    .foregroundStyle(AppColors.secondaryInk)
                    .lineSpacing(3)
                    .minimumScaleFactor(0.85)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: textBandHeight)

            if showCard {
                WelcomeFeatureCard(kind: feature.kind)
                    .frame(maxWidth: .infinity)
                    .frame(height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct WelcomeFeatureCard: View {
    let kind: WelcomeFeatureKind

    private let mintAccent = Color(red: 0.55, green: 0.95, blue: 0.70)

    var body: some View {
        Group {
            switch kind {
            case .crewChallenge:
                crewChallengeCard
            case .checkInAccountability:
                checkInCard
            case .consistencyLeaderboard:
                leaderboardCard
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
        .accessibilityHidden(true)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255),
                        Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var crewChallengeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Sunday Crew")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                Spacer(minLength: 0)
                Text("Private")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("3 workouts this week")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.white)

                HStack(spacing: 6) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                        let active = day == "M" || day == "W" || day == "F"
                        // Week strip is decorative; M/W/F are the scheduled days in this preview.
                        Text(day)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.white.opacity(active ? 0.95 : 0.35))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(active ? 0.16 : 0.06))
                            )
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                avatarStack(marks: [
                    ("flame.fill", Color(red: 0.55, green: 0.32, blue: 0.48)),
                    ("bolt.fill", Color(red: 0.22, green: 0.42, blue: 0.62)),
                    ("leaf.fill", Color(red: 0.18, green: 0.55, blue: 0.42)),
                    ("star.fill", Color(red: 0.52, green: 0.40, blue: 0.22))
                ])
                Text("4 friends")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer(minLength: 0)
                Label("4/4 agreed", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(mintAccent)
            }
        }
    }

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(mintAccent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: Capsule())
                Spacer(minLength: 0)
                Label("Proof clip", systemImage: "video.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            HStack(spacing: 12) {
                welcomeAvatar(symbol: "flame.fill", color: Color(red: 0.55, green: 0.32, blue: 0.48), size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Workout complete")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white)
                    Text("You checked in")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(mintAccent)
            }
            .padding(.vertical, 4)

            VStack(spacing: 8) {
                spoilerRow(name: "Maya", symbol: "star.fill", color: Color(red: 0.52, green: 0.40, blue: 0.22))
                spoilerRow(name: "James", symbol: "bolt.fill", color: Color(red: 0.22, green: 0.42, blue: 0.62))
            }

            Spacer(minLength: 0)

            Text("Check in to reveal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.72))
        }
    }

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This round")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer(minLength: 0)
                Text("+1 for today’s check-in")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(mintAccent)
            }

            VStack(spacing: 8) {
                leaderboardRow(rank: 1, name: "Maya", points: "8 pts", symbol: "star.fill", color: Color(red: 0.52, green: 0.40, blue: 0.22), emphasized: false)
                leaderboardRow(rank: 2, name: "You", points: "7 pts", symbol: "flame.fill", color: Color(red: 0.55, green: 0.32, blue: 0.48), emphasized: true)
                leaderboardRow(rank: 3, name: "James", points: "6 pts", symbol: "bolt.fill", color: Color(red: 0.22, green: 0.42, blue: 0.62), emphasized: false)
            }

            Spacer(minLength: 0)
        }
    }

    private func spoilerRow(name: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            welcomeAvatar(symbol: symbol, color: color, size: 30)
                .opacity(0.35)
                .overlay {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .overlay {
                            Image(systemName: "eye.slash.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                }
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            Spacer(minLength: 0)
            Text("Hidden")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.35))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
    }

    private func leaderboardRow(
        rank: Int,
        name: String,
        points: String,
        symbol: String,
        color: Color,
        emphasized: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 16, alignment: .leading)
            welcomeAvatar(symbol: symbol, color: color, size: 34)
            Text(name)
                .font(.body.weight(emphasized ? .bold : .semibold))
                .foregroundStyle(Color.white)
            Spacer(minLength: 0)
            Text(points)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(emphasized ? mintAccent : Color.white.opacity(0.7))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, emphasized ? 10 : 4)
        .background {
            if emphasized {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
    }

    private func avatarStack(marks: [(String, Color)]) -> some View {
        HStack(spacing: -11) {
            ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                welcomeAvatar(symbol: mark.0, color: mark.1, size: 34)
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 2))
                    .zIndex(Double(marks.count - index))
            }
        }
    }

    private func welcomeAvatar(symbol: String, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct WelcomePageIndicator: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(AppColors.ink.opacity(index == selection ? 0.9 : 0.22))
                    .frame(width: index == selection ? 18 : 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}
