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
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(ColorTokens.primaryOrange)

                    Text("Create Account")
                        .font(TypographyTokens.title)

                    Text("Get started with your first 3 free AI estimates")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, SpacingTokens.xxl)

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
                    }

                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        Text("Company Name")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)

                        TextField("Apex Remodeling Co.", text: $viewModel.companyName)
                            .formField()
                            .textContentType(.organizationName)
                            .textInputAutocapitalization(.words)
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
            .readableContentWidth()
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
}
