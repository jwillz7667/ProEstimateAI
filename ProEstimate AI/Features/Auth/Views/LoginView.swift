import SwiftUI

/// Sign-in screen — matches the overhaul auth.png screenshot.
/// Light surface, square brand mark, all-caps input labels, full-width
/// black SIGN IN button, neutral Apple / Google rows, footer create-account.
struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = AuthViewModel()
    @State private var isPasswordVisible: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SpacingTokens.lg) {
                    brandSection
                        .padding(.top, SpacingTokens.huge)

                    emailField
                    passwordField

                    PrimaryCTAButton(
                        title: "SIGN IN",
                        trailingIcon: "arrow.right",
                        isLoading: viewModel.isLoading,
                        isDisabled: !viewModel.isLoginFormValid,
                        style: .dark
                    ) {
                        focusedField = nil
                        Task { await viewModel.login(appState: appState) }
                    }
                    .padding(.top, SpacingTokens.xs)

                    dividerSection

                    appleSignInButton
                    googleSignInButton

                    Spacer(minLength: SpacingTokens.huge)

                    createAccountFooter
                }
                .padding(.horizontal, SpacingTokens.xl)
                .readableFormWidth()
            }
            .background(ColorTokens.surface.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )) {
                Button("OK", role: .cancel) { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .navigationDestination(isPresented: $viewModel.showSignUp) {
                SignUpView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showForgotPassword) {
                ForgotPasswordView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Brand Section

    private var brandSection: some View {
        VStack(spacing: SpacingTokens.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(ColorTokens.brandLogoTint)
                    .frame(width: 72, height: 72)

                Image(systemName: "compass.drawing")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(ColorTokens.textPrimary)
            }

            VStack(spacing: SpacingTokens.xs) {
                Text("ProEstimate AI")
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .foregroundStyle(ColorTokens.textPrimary)

                Text("Sign in to access your projects.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Email Field

    private var emailField: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text("EMAIL ADDRESS")
                .font(TypographyTokens.inputLabel)
                .tracking(0.6)
                .foregroundStyle(ColorTokens.textSecondary)

            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "envelope")
                    .foregroundStyle(ColorTokens.textTertiary)

                TextField("name@company.com", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }
            .padding(.vertical, SpacingTokens.sm + 2)
            .padding(.horizontal, SpacingTokens.md)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.input))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.input)
                    .strokeBorder(
                        focusedField == .email ? ColorTokens.primaryOrange : ColorTokens.cardStroke,
                        lineWidth: focusedField == .email ? 1.5 : 1
                    )
            )

            if !viewModel.email.isEmpty && !viewModel.isEmailValid {
                Text("Please enter a valid email address.")
                    .font(TypographyTokens.caption2)
                    .foregroundStyle(ColorTokens.error)
            }
        }
    }

    // MARK: - Password Field

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack {
                Text("PASSWORD")
                    .font(TypographyTokens.inputLabel)
                    .tracking(0.6)
                    .foregroundStyle(ColorTokens.textSecondary)

                Spacer()

                Button {
                    viewModel.showForgotPassword = true
                } label: {
                    Text("Forgot Password?")
                        .font(TypographyTokens.caption.weight(.semibold))
                        .foregroundStyle(ColorTokens.accentBlue)
                }
            }

            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "lock")
                    .foregroundStyle(ColorTokens.textTertiary)

                Group {
                    if isPasswordVisible {
                        TextField("••••••••", text: $viewModel.password)
                    } else {
                        SecureField("••••••••", text: $viewModel.password)
                    }
                }
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    focusedField = nil
                    Task { await viewModel.login(appState: appState) }
                }

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(ColorTokens.textTertiary)
                }
                .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
            }
            .padding(.vertical, SpacingTokens.sm + 2)
            .padding(.horizontal, SpacingTokens.md)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.input))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.input)
                    .strokeBorder(
                        focusedField == .password ? ColorTokens.primaryOrange : ColorTokens.cardStroke,
                        lineWidth: focusedField == .password ? 1.5 : 1
                    )
            )
        }
    }

    // MARK: - Divider

    private var dividerSection: some View {
        HStack(spacing: SpacingTokens.sm) {
            Rectangle()
                .fill(ColorTokens.cardStroke)
                .frame(height: 1)

            Text("or continue with")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.textSecondary)

            Rectangle()
                .fill(ColorTokens.cardStroke)
                .frame(height: 1)
        }
        .padding(.vertical, SpacingTokens.xs)
    }

    // MARK: - Apple / Google

    private var appleSignInButton: some View {
        Button {
            Task { await viewModel.signInWithApple(appState: appState) }
        } label: {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("Sign in with Apple")
                    .font(TypographyTokens.bodyEmphasized)
                    .foregroundStyle(ColorTokens.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm + 4)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.input))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.input)
                    .strokeBorder(ColorTokens.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }

    private var googleSignInButton: some View {
        Button {
            Task { await viewModel.signInWithGoogle(appState: appState) }
        } label: {
            HStack(spacing: SpacingTokens.sm) {
                googleGlyph
                Text("Sign in with Google")
                    .font(TypographyTokens.bodyEmphasized)
                    .foregroundStyle(ColorTokens.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm + 4)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.input))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.input)
                    .strokeBorder(ColorTokens.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }

    /// Multi-color "G" mark approximating Google's logo without redistributing
    /// the brand asset. Good enough for sign-in row recognition.
    private var googleGlyph: some View {
        Text("G")
            .font(.system(size: 20, weight: .heavy, design: .default))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(hex: 0x4285F4),
                        Color(hex: 0xEA4335),
                        Color(hex: 0xFBBC05),
                        Color(hex: 0x34A853),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    // MARK: - Create Account Footer

    private var createAccountFooter: some View {
        HStack(spacing: 4) {
            Text("Don't have an account?")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.textSecondary)

            Button {
                viewModel.showSignUp = true
            } label: {
                Text("Create Account")
                    .font(TypographyTokens.subheadline.weight(.bold))
                    .foregroundStyle(ColorTokens.textPrimary)
            }
        }
        .padding(.bottom, SpacingTokens.xl)
    }
}
