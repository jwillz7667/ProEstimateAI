import SwiftUI

/// Full-screen paywall sheet with dark glass aesthetic.
/// Composed of modular sections: hero, plan selector, feature comparison,
/// purchase button, and legal disclosure.
///
/// Present as a sheet with `.sheet(item:)` bound to a `PaywallDecision`.
/// The `isBlocking` flag on the decision determines whether the user
/// can dismiss the sheet or must subscribe.
struct PaywallHostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: PaywallHostViewModel

    /// Callback fired when the purchase succeeds and the paywall should dismiss.
    var onPurchaseComplete: (() -> Void)?

    init(
        decision: PaywallDecision,
        onPurchaseComplete: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: PaywallHostViewModel(decision: decision))
        self.onPurchaseComplete = onPurchaseComplete
    }

    /// Preview-only initializer that accepts a pre-built view model.
    init(viewModel: PaywallHostViewModel, onPurchaseComplete: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onPurchaseComplete = onPurchaseComplete
    }

    var body: some View {
        ZStack {
            // Dark gradient background.
            backgroundGradient

            ScrollView {
                VStack(spacing: 0) {
                    // Hero section with headline and subheadline.
                    PaywallHeroSection(decision: viewModel.decision)

                    VStack(spacing: SpacingTokens.xl) {
                        // Tier + period picker.
                        if !viewModel.products.isEmpty {
                            PlanSelectorView(
                                products: viewModel.products,
                                selectedProduct: viewModel.selectedProduct,
                                selectedTier: $viewModel.selectedTier,
                                isAnnualSelected: $viewModel.isAnnualSelected
                            )
                        }

                        // Feature comparison — Free vs Pro vs Premium.
                        FeatureComparisonListView()

                        // Error message with inline retry.
                        if let errorMessage = viewModel.errorMessage {
                            errorBanner(errorMessage) {
                                Task { await viewModel.purchase() }
                            }
                        }

                        // Purchase CTA and secondary actions.
                        PurchaseButtonSection(
                            primaryTitle: viewModel.primaryCtaTitle,
                            isPurchasing: viewModel.isPurchasing,
                            isRestoring: viewModel.isRestoring,
                            showContinueFree: viewModel.showContinueFree,
                            showRestorePurchases: viewModel.showRestorePurchases,
                            secondaryCtaTitle: viewModel.decision.secondaryCtaTitle,
                            selectedProduct: viewModel.selectedProduct,
                            onPurchase: {
                                Task { await viewModel.purchase() }
                            },
                            onContinueFree: {
                                dismiss()
                            },
                            onRestore: {
                                Task { await viewModel.restorePurchases() }
                            }
                        )

                        // Legal disclosure.
                        LegalDisclosureSection(selectedProduct: viewModel.selectedProduct)
                    }
                    .padding(.horizontal, SpacingTokens.lg)
                    .padding(.bottom, SpacingTokens.xxxl)
                }
            }

            // Dismiss button — always shown so user can back out
            dismissButton
        }
        .task {
            await viewModel.loadProducts()
        }
        .onChange(of: viewModel.purchaseSucceeded) { _, succeeded in
            if succeeded {
                onPurchaseComplete?()
                dismiss()
            }
        }
        .interactiveDismissDisabled(false)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                ColorTokens.overlayBackground,
                ColorTokens.overlayAccent,
                ColorTokens.overlayBackground,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ColorTokens.onDarkSecondary)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, SpacingTokens.md)
                .padding(.top, SpacingTokens.md)
                .accessibilityLabel("Close")
                .accessibilityHint("Dismiss the paywall")
            }
            Spacer()
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String, onRetry: @escaping () -> Void) -> some View {
        HStack(spacing: SpacingTokens.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ColorTokens.warning)

            Text(message)
                .font(TypographyTokens.footnote)
                .foregroundStyle(ColorTokens.onDarkPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Try Again", action: onRetry)
                .font(TypographyTokens.footnote.weight(.semibold))
                .foregroundStyle(ColorTokens.primaryOrange)
                .disabled(viewModel.isPurchasing)
        }
        .padding(SpacingTokens.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTokens.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: RadiusTokens.small))
    }
}

// MARK: - Preview

#Preview("Soft Gate") {
    PaywallHostView(
        viewModel: .preview(decision: .sampleSoftGate)
    )
}

#Preview("Hard Gate") {
    PaywallHostView(
        viewModel: .preview(decision: .sampleHardGate)
    )
}
