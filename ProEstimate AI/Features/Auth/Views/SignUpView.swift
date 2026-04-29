import SwiftUI

struct SignUpView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: SpacingTokens.xl) {
                // MARK: - Header

                VStack(spacing: SpacingTokens.sm) {
                    logoBadge

                    Text("Create Account")
                        .font(TypographyTokens.title)

                    Text("Get started with ProEstimate AI")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, SpacingTokens.xxl)

                // MARK: - One-tap providers (preferred path)

                VStack(spacing: SpacingTokens.sm) {
                    appleSignUpButton
                    googleSignUpButton
                }

                // MARK: - Divider

                HStack {
                    Rectangle()
                        .fill(ColorTokens.subtleBorder)
                        .frame(height: 1)
                    Text("OR SIGN UP WITH EMAIL")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Rectangle()
                        .fill(ColorTokens.subtleBorder)
                        .frame(height: 1)
                }
                .padding(.vertical, SpacingTokens.xs)

                // MARK: - Form Fields

                VStack(spacing: SpacingTokens.md) {
                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        Text("Full Name")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)

                        TextField("John Doe", text: $viewModel.fullName)
                            .formField()
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                    }

                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        Text("Email")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)

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
                            .foregroundStyle(.secondary)

                        SecureField("Minimum 8 characters", text: $viewModel.password)
                            .formField()
                            .textContentType(.newPassword)

                        if !viewModel.password.isEmpty && viewModel.password.count < 8 {
                            Text("Password must be at least 8 characters")
                                .font(TypographyTokens.caption2)
                                .foregroundStyle(ColorTokens.error)
                        }
                    }
                }

                // MARK: - Create Account Button

                PrimaryCTAButton(
                    title: "Create Account",
                    icon: "checkmark.circle",
                    isLoading: viewModel.isLoading,
                    isDisabled: !viewModel.isSignUpFormValid,
                    action: {
                        Task { await viewModel.signUp(appState: appState) }
                    }
                )

                // MARK: - Back to Login

                HStack(spacing: SpacingTokens.xxs) {
                    Text("Already have an account?")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        dismiss()
                    } label: {
                        Text("Sign In")
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
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
                .accessibilityLabel("Back")
                .accessibilityHint("Returns to sign in")
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Logo

    /// Brand badge: the orange `person.badge.plus` glyph centered inside a
    /// 96pt white disc. The white fill is unconditional in both color
    /// schemes — in dark mode it pops the orange off the system-dark
    /// canvas, and in light mode the soft shadow gives the disc enough
    /// edge to read as a deliberate badge rather than a flat fill.
    ///
    /// The SF Symbol's bounding box centers in the disc, but the
    /// `person.badge.plus` glyph itself sits a hair left of optical center
    /// because of the trailing "+" badge. A 2pt trailing padding nudges
    /// the bounding box left so the *figure* lands on the disc's vertical
    /// axis — the kind of optical correction designers expect.
    private var logoBadge: some View {
        Image(systemName: "person.badge.plus")
            .font(.system(size: 44, weight: .medium))
            .foregroundStyle(ColorTokens.primaryOrange)
            .symbolRenderingMode(.monochrome)
            .padding(.trailing, 2)
            .frame(width: 96, height: 96)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
            .accessibilityHidden(true)
    }

    // MARK: - Provider buttons

    private var appleSignUpButton: some View {
        Button {
            Task { await viewModel.signInWithApple(appState: appState) }
        } label: {
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
                Text("Continue with Apple")
                    .font(TypographyTokens.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
            .padding(.horizontal, SpacingTokens.md)
            .background(.black, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
            .foregroundStyle(.white)
        }
        .disabled(viewModel.isLoading)
        .accessibilityLabel("Continue with Apple")
    }

    private var googleSignUpButton: some View {
        Button {
            Task { await viewModel.signInWithGoogle(appState: appState) }
        } label: {
            HStack(spacing: SpacingTokens.xs) {
                Text("G")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.blue)
                Text("Continue with Google")
                    .font(TypographyTokens.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
            .padding(.horizontal, SpacingTokens.md)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .strokeBorder(ColorTokens.subtleBorder, lineWidth: 1)
            )
            .foregroundStyle(ColorTokens.primaryText)
        }
        .disabled(viewModel.isLoading)
        .accessibilityLabel("Continue with Google")
    }
}
