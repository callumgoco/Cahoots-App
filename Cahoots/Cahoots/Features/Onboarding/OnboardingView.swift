import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var authMode: EmailAuthView.Mode?

    private let proofPoints: [(symbol: String, text: String)] = [
        ("person.3.fill", "Create a private group and invite people you know"),
        ("checkmark.circle.fill", "Agree on one clear daily check-in"),
        ("equal.circle.fill", "Earn points for showing up, not for grinding")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.extraLarge) {
                    Text(AppIdentity.name)
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)

                    if !dynamicTypeSize.isAccessibilitySize {
                        welcomeHero
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        Text("Set one goal with friends")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Create a private group, pick a daily check-in, and keep each other honest.")
                            .font(.title3)
                            .foregroundStyle(AppColors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)

                        if let code = store.pendingJoinCode {
                            Label("Sign in to review invitation \(code)", systemImage: "envelope.open.fill")
                                .font(.body.weight(.semibold))
                        }
                        if store.mode == .demo {
                            DemoModeBadge()
                        }
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        ForEach(proofPoints, id: \.symbol) { point in
                            Label(point.text, systemImage: point.symbol)
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppColors.ink)
                                .labelStyle(.titleAndIcon)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, AppSpacing.medium)
                .padding(.bottom, AppSpacing.large)
            }
            .interactiveKeyboardDismiss()

            VStack(spacing: AppSpacing.medium) {
                if store.mode == .demo {
                    Button("Explore the demo") { Task { await store.startDemo() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("onboarding.demo")
                    Text("No account or external services required")
                        .font(.caption)
                        .foregroundStyle(AppColors.secondaryInk)
                        .multilineTextAlignment(.center)
                }

                SignInWithAppleButton(.signUp) { request in
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = store.beginAppleSignIn()
                } onCompletion: { result in
                    Task { await store.handleAppleAuthorization(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 54)
                .clipShape(Capsule())
                .accessibilityIdentifier("onboarding.apple")

                if store.mode == .live {
                    Button("Create account with email") { authMode = .signUp }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("onboarding.signUp")

                    Button {
                        authMode = .signIn
                    } label: {
                        Text("Already have an account? Sign in")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.signIn")
                }
            }
            .padding(AppSpacing.page)
        }
        .roundPage()
        .sheet(item: $authMode) { mode in
            EmailAuthView(mode: mode)
        }
    }

    private var welcomeHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(AppColors.accentSoft)
                .frame(height: 200)
            Circle()
                .fill(AppColors.accent.opacity(0.18))
                .frame(width: 160, height: 160)
                .offset(x: -48, y: -36)
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(AppColors.accent)
                .symbolRenderingMode(.hierarchical)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

extension EmailAuthView.Mode: Identifiable {
    var id: Self { self }
}
