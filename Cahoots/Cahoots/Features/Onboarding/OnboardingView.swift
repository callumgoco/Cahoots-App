import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var authMode: EmailAuthView.Mode?
    @State private var selectedFeature = 0
    @State private var appeared = false
    @State private var showSplash = Self.shouldPlaySplash

    private static var shouldPlaySplash: Bool {
        guard !AppDefaults.isRunningUITests else { return false }
        return !UserDefaults.standard.bool(forKey: AppDefaults.splashPlayed)
    }

    var body: some View {
        ZStack {
            onboardingContent
                .opacity(showSplash ? 0 : 1)
                .allowsHitTesting(!showSplash)

            if showSplash {
                LaunchSplashView {
                    UserDefaults.standard.set(true, forKey: AppDefaults.splashPlayed)
                    withAnimation(reduceMotion ? nil : AppMotion.calm) {
                        showSplash = false
                    }
                    revealOnboarding()
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .roundPage()
        .sheet(item: $authMode) { mode in
            EmailAuthView(mode: mode)
        }
        .onAppear {
            if !showSplash { revealOnboarding() }
        }
    }

    private var onboardingContent: some View {
        GeometryReader { proxy in
            let cardHeight = preferredCardHeight(for: proxy.size.height)
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    featureColumn(cardHeight: cardHeight)
                }

                authCluster
                    .padding(.horizontal, AppSpacing.page)
                    .padding(.top, AppSpacing.small)
                    .padding(.bottom, AppSpacing.large)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 8)
            }
        }
    }

    private func preferredCardHeight(for availableHeight: CGFloat) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 190 }
        if availableHeight < 700 { return 216 }
        if availableHeight > 860 { return 268 }
        return 248
    }

    private func featureColumn(cardHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            if store.mode == .demo {
                HStack {
                    DemoModeBadge()
                    Spacer(minLength: 0)
                }
            }

            if let code = store.pendingJoinCode {
                Label("Sign in to review invitation \(code)", systemImage: "envelope.open.fill")
                    .font(.subheadline.weight(.semibold))
            }

            WelcomeFeatureCarousel(selection: $selectedFeature, cardHeight: cardHeight)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, dynamicTypeSize.isAccessibilitySize ? AppSpacing.small : 28)
        .padding(.bottom, AppSpacing.medium)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 10)
    }

    private var authCluster: some View {
        VStack(spacing: 0) {
            if store.mode == .demo {
                Button("Explore the demo") { Task { await store.startDemo() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding.demo")
                    .padding(.bottom, 12)

                Text("No account needed")
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryInk)
                    .padding(.bottom, AppSpacing.small)

                Text("or")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, AppSpacing.medium)
            }

            SignInWithAppleButton(.signUp) { request in
                request.requestedScopes = [.fullName, .email]
                request.nonce = store.beginAppleSignIn()
            } onCompletion: { result in
                Task { await store.handleAppleAuthorization(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 56)
            .clipShape(Capsule())
            .accessibilityIdentifier("onboarding.apple")

            if store.mode == .live {
                Button("Continue with email") { authMode = .signUp }
                    .buttonStyle(OutlineButtonStyle())
                    .accessibilityIdentifier("onboarding.signUp")
                    .padding(.top, 11)

                existingAccountLine
                    .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var existingAccountLine: some View {
        HStack(spacing: 4) {
            Text("Already have an account?")
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryInk)
            Button("Sign in") { authMode = .signIn }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.ink)
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.signIn")
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
    }

    private func revealOnboarding() {
        guard !appeared else { return }
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(AppMotion.calm.delay(0.05)) { appeared = true }
        }
    }
}

extension EmailAuthView.Mode: Identifiable {
    var id: Self { self }
}
