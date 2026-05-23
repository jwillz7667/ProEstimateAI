import SwiftUI

/// Account creation screen — visually paired with `LoginView`.
struct SignUpView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: AuthViewModel
    @State private var isPasswordVisible: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case fullName
        case email
        case password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SpacingTokens.lg) {
                brandSection
                    .padding(.top, SpacingTokens.xl)

                fullNameField
                emailField
                passwordField

                PrimaryCTAButton(
                    title: "CREATE ACCOUNT",
                    trailingIcon: "arrow.right",
                    isLoading: viewModel.isLoading,
                    isDisabled: !viewModel.isSignUpFormValid,
                    style: .dark
                ) {
                    focusedField = nil
                    Task { await viewModel.signUp(appState: appState) }
                }
                .padding(.top, SpacingTokens.xs)

                dividerSection

                appleSignUpButton
                googleSignUpButton

                Spacer(minLength: SpacingTokens.huge)

                signInFooter
            }
            .padding(.horizontal, SpacingTokens.xl)
            .readableFormWidth()
        }
        .background(ColorTokens.surface.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(ColorTokens.textPrimary)
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

    // MARK: - Brand Header

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
                Text("Create Account")
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("Get started with ProEstimate AI.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Fields

    private var fullNameField: some View {
        labeledField("FULL NAME", icon: "person") {
            TextField("Jane Builder", text: $viewModel.fullName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .fullName)
                .submitLabel(.next)
                .onSubmit { focusedField = .email }
        } isFocused: { focusedField == .fullName }
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            labeledField("EMAIL ADDRESS", icon: "envelope") {
                TextField("name@company.com", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            } isFocused: { focusedField == .email }

            if !viewModel.email.isEmpty && !viewModel.isEmailValid {
                Text("Please enter a valid email address.")
                    .font(TypographyTokens.caption2)
                    .foregroundStyle(ColorTokens.error)
            }
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            labeledField("PASSWORD", icon: "lock", trailingIconAction: {
                isPasswordVisible.toggle()
            }, trailingIcon: isPasswordVisible ? "eye.slash" : "eye") {
                Group {
                    if isPasswordVisible {
                        TextField("Minimum 8 characters", text: $viewModel.password)
                    } else {
                        SecureField("Minimum 8 characters", text: $viewModel.password)
                    }
                }
                .textContentType(.newPassword)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    focusedField = nil
                    Task { await viewModel.signUp(appState: appState) }
                }
            } isFocused: { focusedField == .password }

            if !viewModel.password.isEmpty && viewModel.password.count < 8 {
                Text("Password must be at least 8 characters")
                    .font(TypographyTokens.caption2)
                    .foregroundStyle(ColorTokens.error)
            }
        }
    }

    // MARK: - Field Builder

    @ViewBuilder
    private func labeledField<Content: View>(
        _ label: String,
        icon: String,
        trailingIconAction: (() -> Void)? = nil,
        trailingIcon: String? = nil,
        @ViewBuilder content: () -> Content,
        isFocused: () -> Bool
    ) -> some View {
        let focused = isFocused()
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text(label)
                .font(TypographyTokens.inputLabel)
                .tracking(0.6)
                .foregroundStyle(ColorTokens.textSecondary)

            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: icon)
                    .foregroundStyle(ColorTokens.textTertiary)

                content()

                if let trailingIcon, let action = trailingIconAction {
                    Button(action: action) {
                        Image(systemName: trailingIcon)
                            .foregroundStyle(ColorTokens.textTertiary)
                    }
                }
            }
            .padding(.vertical, SpacingTokens.sm + 2)
            .padding(.horizontal, SpacingTokens.md)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.input))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.input)
                    .strokeBorder(
                        focused ? ColorTokens.primaryOrange : ColorTokens.cardStroke,
                        lineWidth: focused ? 1.5 : 1
                    )
            )
        }
    }

    // MARK: - Divider

    private var dividerSection: some View {
        HStack(spacing: SpacingTokens.sm) {
            Rectangle().fill(ColorTokens.cardStroke).frame(height: 1)
            Text("or continue with")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.textSecondary)
            Rectangle().fill(ColorTokens.cardStroke).frame(height: 1)
        }
        .padding(.vertical, SpacingTokens.xs)
    }

    // MARK: - Provider Buttons

    private var appleSignUpButton: some View {
        Button {
            Task { await viewModel.signInWithApple(appState: appState) }
        } label: {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
                Text("Continue with Apple")
                    .font(TypographyTokens.bodyEmphasized)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm + 4)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.input))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.input)
                    .strokeBorder(ColorTokens.cardStroke, lineWidth: 1)
            )
            .foregroundStyle(ColorTokens.textPrimary)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }

    private var googleSignUpButton: some View {
        Button {
            Task { await viewModel.signInWithGoogle(appState: appState) }
        } label: {
            HStack(spacing: SpacingTokens.sm) {
                Text("G")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: 0x4285F4), Color(hex: 0xEA4335), Color(hex: 0xFBBC05), Color(hex: 0x34A853)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                Text("Continue with Google")
                    .font(TypographyTokens.bodyEmphasized)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm + 4)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.input))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.input)
                    .strokeBorder(ColorTokens.cardStroke, lineWidth: 1)
            )
            .foregroundStyle(ColorTokens.textPrimary)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }

    private var signInFooter: some View {
        HStack(spacing: 4) {
            Text("Already have an account?")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.textSecondary)
            Button { dismiss() } label: {
                Text("Sign In")
                    .font(TypographyTokens.subheadline.weight(.bold))
                    .foregroundStyle(ColorTokens.textPrimary)
            }
        }
        .padding(.bottom, SpacingTokens.xl)
    }
}
