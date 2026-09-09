import SwiftUI

struct EmailAuthView: View {
    enum Mode: Hashable {
        case signIn
        case signUp
        case resetPassword
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var email: String
    @State private var password = ""
    @State private var displayName = ""
    @State private var showPassword = false
    @State private var isWorking = false
    @FocusState private var field: Field?

    private enum Field: Hashable {
        case displayName, email, password
    }

    init(mode: Mode, email: String = "") {
        _mode = State(initialValue: mode)
        _email = State(initialValue: email)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(title)
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(AppColors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: AppSpacing.medium) {
                        if mode == .signUp {
                            authField(title: "Display name") {
                                TextField("Your name", text: $displayName)
                                    .textContentType(.name)
                                    .textInputAutocapitalization(.words)
                                    .submitLabel(.next)
                                    .focused($field, equals: .displayName)
                                    .onSubmit { field = .email }
                                    .accessibilityIdentifier("auth.displayName")
                            }
                        }

                        authField(title: "Email") {
                            TextField("you@example.com", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(mode == .resetPassword ? .go : .next)
                                .focused($field, equals: .email)
                                .onSubmit {
                                    if mode == .resetPassword {
                                        Task { await submit() }
                                    } else {
                                        field = .password
                                    }
                                }
                                .accessibilityIdentifier("auth.email")
                        }

                        if mode != .resetPassword {
                            authField(title: "Password") {
                                HStack(spacing: AppSpacing.small) {
                                    Group {
                                        if showPassword {
                                            TextField("Password", text: $password)
                                        } else {
                                            SecureField("Password", text: $password)
                                        }
                                    }
                                    .textContentType(mode == .signUp ? .newPassword : .password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.go)
                                    .focused($field, equals: .password)
                                    .onSubmit { Task { await submit() } }
                                    .accessibilityIdentifier("auth.password")

                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundStyle(AppColors.secondaryInk)
                                            .frame(minWidth: 44, minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                                }
                            }
                        }

                        if mode == .signUp {
                            passwordHint
                        }

                        if let error = store.errorBanner {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("auth.error")
                        }
                    }
                }
                .padding(AppSpacing.page)
            }
            .interactiveKeyboardDismiss()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.medium) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isWorking {
                            ProgressView()
                                .tint(AppColors.onInk)
                                .frame(maxWidth: .infinity, minHeight: 54)
                        } else {
                            Text(primaryButtonTitle)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit || isWorking)
                    .accessibilityIdentifier(primaryIdentifier)

                    if mode == .signIn {
                        Button {
                            withAnimation(AppMotion.calm) {
                                store.errorBanner = nil
                                mode = .resetPassword
                                field = .email
                            }
                        } label: {
                            Text("Forgot password?")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                        .accessibilityIdentifier("auth.forgotPassword")
                    }

                    Button {
                        withAnimation(AppMotion.calm) {
                            store.errorBanner = nil
                            password = ""
                            showPassword = false
                            switch mode {
                            case .signUp:
                                mode = .signIn
                                field = .email
                            case .signIn, .resetPassword:
                                mode = .signUp
                                field = .displayName
                            }
                        }
                    } label: {
                        Text(mode == .signUp
                             ? "Already have an account? Sign in"
                             : "Need an account? Create one")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityIdentifier("auth.switchMode")
                }
                .padding(AppSpacing.page)
                .background(.bar)
            }
            .roundPage()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.errorBanner = nil
                        dismiss()
                    }
                }
            }
            .keyboardDoneToolbar()
            .onAppear {
                store.errorBanner = nil
                field = mode == .signUp ? .displayName : .email
            }
            .onChange(of: store.noticeBanner) { _, notice in
                if mode == .resetPassword, notice != nil { dismiss() }
            }
        }
    }

    private var title: String {
        switch mode {
        case .signUp: "Create your account"
        case .signIn: "Welcome back"
        case .resetPassword: "Reset password"
        }
    }

    private var subtitle: String {
        switch mode {
        case .signUp: "A name, email and password are enough to get started."
        case .signIn: "Sign in with the email you used to create your account."
        case .resetPassword: "We will email you a link to choose a new password."
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .signUp: "Create account"
        case .signIn: "Sign in"
        case .resetPassword: "Reset password"
        }
    }

    private var primaryButtonTitle: String {
        switch mode {
        case .signUp: "Create account"
        case .signIn: "Sign in"
        case .resetPassword: "Send reset link"
        }
    }

    private var primaryIdentifier: String {
        switch mode {
        case .signUp: "auth.create"
        case .signIn: "auth.signIn"
        case .resetPassword: "auth.reset"
        }
    }

    private var passwordHint: some View {
        Label {
            Text("At least 6 characters")
        } icon: {
            Image(systemName: password.count >= 6 ? "checkmark.circle.fill" : "circle")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(password.count >= 6 ? AppColors.accent : AppColors.secondaryInk)
        .accessibilityLabel(password.count >= 6 ? "Password meets the 6 character minimum" : "Password needs at least 6 characters")
    }

    private func authField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.micro) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.secondaryInk)
            content()
                .padding(AppSpacing.medium)
                .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
    }

    private var canSubmit: Bool {
        let emailOK = email.contains("@") && email.contains(".")
        if mode == .resetPassword { return emailOK }
        let passwordOK = password.count >= 6
        if mode == .signUp {
            return emailOK && passwordOK && TextSanitizer.clean(displayName).count >= 2
        }
        return emailOK && passwordOK
    }

    private func submit() async {
        guard canSubmit, !isWorking else { return }
        isWorking = true
        store.errorBanner = nil
        defer { isWorking = false }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .signIn:
            await store.signIn(email: trimmedEmail, password: password)
        case .signUp:
            await store.signUp(
                email: trimmedEmail,
                password: password,
                displayName: TextSanitizer.clean(displayName, maximumLength: 40)
            )
            if store.noticeBanner != nil, !store.isSignedIn {
                mode = .signIn
                password = ""
            }
        case .resetPassword:
            await store.resetPassword(email: trimmedEmail)
        }
        if store.isSignedIn { dismiss() }
    }
}
