import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = AuthViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SpacingTokens.xl) {
                    // MARK: - Logo / Header
                    logoSection
                        .padding(.top, SpacingTokens.huge)

                    // MARK: - Form
                    formSection

                    // MARK: - Sign In Button
                    PrimaryCTAButton(
                        title: "Sign In",
                        icon: "arrow.right",
                        isLoading: viewModel.isLoading,
                        isDisabled: !viewModel.isLoginFormValid,
                        action: {
                            Task { await viewModel.login(appState: appState) }
                        }
                    )

                    // MARK: - Divider
                    dividerSection

                    // MARK: - Sign in with Apple
                    appleSignInButton

                    // MARK: - Forgot Password
                    Button {
                        viewModel.showForgotPassword = true
                    } label: {
                        Text("Forgot Password?")
                            .font(TypographyTokens.subheadline)
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }

                    // MARK: - Sign Up Link
                    HStack(spacing: SpacingTokens.xxs) {
                        Text("Don't have an account?")
                            .font(TypographyTokens.subheadline)
                            .foregroundStyle(ColorTokens.secondaryText)

                        Button {
                            viewModel.showSignUp = true
                        } label: {
                            Text("Sign Up")
                                .font(TypographyTokens.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(ColorTokens.primaryOrange)
                        }
                    }
                    .padding(.bottom, SpacingTokens.xxl)
                }
                .padding(.horizontal, SpacingTokens.xl)
                .readableFormWidth()
            }
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

    // MARK: - Logo Section

    private var logoSection: some View {
        VStack(spacing: SpacingTokens.sm) {
            Image("housd-icon-light")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 56)
                .padding(SpacingTokens.md)
                .background(ColorTokens.surface, in: Circle())
                .shadow(color: ColorTokens.primaryOrange.opacity(0.18), radius: 12)

            Text("ProEstimate")
                .font(TypographyTokens.largeTitle)

            Text("AI-powered estimates for professionals")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: SpacingTokens.md) {
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text("Email")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)

                TextField("you@company.com", text: $viewModel.email)
                    .formField()
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !viewModel.email.isEmpty && !viewModel.isEmailValid {
                    Text("Please enter a valid email address.")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(ColorTokens.error)
                }
            }

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text("Password")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)

                SecureField("Enter your password", text: $viewModel.password)
                    .formField()
                    .textContentType(.password)
            }
        }
    }

    // MARK: - Divider

    private var dividerSection: some View {
        HStack {
            Rectangle()
                .fill(ColorTokens.subtleBorder)
                .frame(height: 1)

            Text("or")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.secondaryText)

            Rectangle()
                .fill(ColorTokens.subtleBorder)
                .frame(height: 1)
        }
    }

    // MARK: - Apple Sign In

    @ViewBuilder
    private var appleSignInButton: some View {
        Button {
            Task { await viewModel.signInWithApple(appState: appState) }
        } label: {
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
                Text("Sign in with Apple")
                    .font(TypographyTokens.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
            .padding(.horizontal, SpacingTokens.md)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .strokeBorder(ColorTokens.primaryOrange.opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(ColorTokens.primaryText)
        }
        .disabled(viewModel.isLoading)
    }
}
