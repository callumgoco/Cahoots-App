import SwiftUI

/// First-launch brand moment before onboarding. Tap anywhere to skip.
struct LaunchSplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var lettersRevealed = false
    @State private var crewRevealed = false
    @State private var orbPulse = false
    @State private var exiting = false
    @State private var didFinish = false

    private let letters = Array(AppIdentity.name)
    private let marks: [(symbol: String, color: Color)] = [
        ("flame.fill", Color(red: 0.55, green: 0.32, blue: 0.48)),
        ("bolt.fill", Color(red: 0.22, green: 0.42, blue: 0.62)),
        ("leaf.fill", Color(red: 0.18, green: 0.55, blue: 0.42)),
        ("star.fill", Color(red: 0.52, green: 0.40, blue: 0.22))
    ]

    var body: some View {
        ZStack {
            AppColors.page.ignoresSafeArea()

            atmosphere

            VStack(spacing: AppSpacing.large) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: AppColors.ink.opacity(0.18), radius: 18, y: 10)
                    .scaleEffect(lettersRevealed ? 1 : 0.6)
                    .opacity(lettersRevealed ? 1 : 0)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.62, bounce: 0.45),
                        value: lettersRevealed
                    )
                    .accessibilityHidden(true)

                HStack(spacing: 1) {
                    ForEach(Array(letters.enumerated()), id: \.offset) { index, character in
                        Text(String(character))
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColors.ink)
                            .scaleEffect(lettersRevealed ? 1 : 0.35)
                            .opacity(lettersRevealed ? 1 : 0)
                            .offset(y: lettersRevealed ? 0 : 28)
                            .rotationEffect(.degrees(lettersRevealed ? 0 : Double(index.isMultiple(of: 2) ? -8 : 8)))
                            .animation(
                                reduceMotion
                                    ? .easeOut(duration: 0.2)
                                    : .spring(duration: 0.58, bounce: 0.52).delay(Double(index) * 0.055),
                                value: lettersRevealed
                            )
                    }
                }
                .accessibilityAddTraits(.isHeader)

                HStack(spacing: -14) {
                    ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                        splashAvatar(symbol: mark.symbol, color: mark.color)
                            .overlay(Circle().stroke(AppColors.page, lineWidth: 3))
                            .scaleEffect(crewRevealed ? 1 : 0.4)
                            .opacity(crewRevealed ? 1 : 0)
                            .offset(y: crewRevealed ? 0 : 16)
                            .animation(
                                reduceMotion
                                    ? .easeOut(duration: 0.2)
                                    : .spring(duration: 0.5, bounce: 0.55).delay(0.08 + Double(index) * 0.06),
                                value: crewRevealed
                            )
                            .zIndex(Double(marks.count - index))
                    }
                }

                Text("the rest are in cahoots")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryInk)
                    .opacity(crewRevealed ? 1 : 0)
                    .offset(y: crewRevealed ? 0 : 8)
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : AppMotion.calm.delay(0.35), value: crewRevealed)
            }
            .scaleEffect(exiting ? 1.12 : 1)
            .opacity(exiting ? 0 : 1)
            .blur(radius: exiting && !reduceMotion ? 8 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish(animated: true) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cahoots")
        .accessibilityHint("Shows briefly on first launch")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { finish(animated: false) }
        .task { await play() }
    }

    private var atmosphere: some View {
        ZStack {
            Circle()
                .fill(AppColors.ink.opacity(colorScheme == .dark ? 0.12 : 0.07))
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(x: -90, y: -160)
                .scaleEffect(orbPulse ? 1.12 : 0.88)
            Circle()
                .fill(AppColors.ink.opacity(colorScheme == .dark ? 0.1 : 0.05))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .offset(x: 110, y: 180)
                .scaleEffect(orbPulse ? 0.9 : 1.15)
            Circle()
                .fill(AppColors.chip.opacity(0.9))
                .frame(width: 140, height: 140)
                .offset(x: 40, y: -40)
                .scaleEffect(orbPulse ? 1.2 : 0.85)
                .opacity(0.55)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
            value: orbPulse
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func splashAvatar(symbol: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }

    @MainActor
    private func play() async {
        if reduceMotion {
            lettersRevealed = true
            crewRevealed = true
            try? await Task.sleep(for: .milliseconds(500))
            finish(animated: false)
            return
        }

        orbPulse = true
        lettersRevealed = true
        try? await Task.sleep(for: .milliseconds(420))
        guard !didFinish else { return }
        crewRevealed = true
        try? await Task.sleep(for: .milliseconds(1150))
        guard !didFinish else { return }
        finish(animated: true)
    }

    @MainActor
    private func finish(animated: Bool) {
        guard !didFinish else { return }
        didFinish = true
        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.42)) { exiting = true }
            Task {
                try? await Task.sleep(for: .milliseconds(420))
                onFinished()
            }
        } else {
            onFinished()
        }
    }
}
