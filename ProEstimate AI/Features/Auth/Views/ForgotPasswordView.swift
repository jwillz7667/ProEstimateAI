import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: SpacingTokens.xl) {
                Spacer()

                if viewModel.forgotPasswordSuccess {
                    successContent
                } else {
                    formContent
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, SpacingTokens.xl)
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        viewModel.forgotPasswordSuccess = false
                        dismiss()
                    }
                    .foregroundStyle(ColorTokens.primaryOrange)
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
        .presentationDetents([.medium])
    }

    // MARK: - Form Content

    private var formContent: some View {
        VStack(spacing: SpacingTokens.xl) {
            VStack(spacing: SpacingTokens.sm) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 48))
                    .foregroundStyle(ColorTokens.primaryOrange)

                Text("Forgot your password?")
                    .font(TypographyTokens.title3)

                Text("Enter your email and we'll send you a link to reset your password.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text("Email")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)

                TextField("you@company.com", text: $viewModel.email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            PrimaryCTAButton(
                title: "Send Reset Link",
                icon: "paperplane",
                isLoading: viewModel.isLoading,
                isDisabled: viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: {
                    Task { await viewModel.forgotPassword() }
                }
            )
        }
    }

    // MARK: - Success Content

    private var successContent: some View {
        VStack(spacing: SpacingTokens.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(ColorTokens.success)

            Text("Check Your Email")
                .font(TypographyTokens.title3)

            Text("If an account with that email exists, we've sent a password reset link. Please check your inbox and spam folder.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecondaryButton(title: "Done") {
                viewModel.forgotPasswordSuccess = false
                dismiss()
            }
            .frame(maxWidth: 200)
            .padding(.top, SpacingTokens.sm)
        }
    }
}
