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
        self._viewModel = State(initialValue: PaywallHostViewModel(decision: decision))
        self.onPurchaseComplete = onPurchaseComplete
    }

    /// Preview-only initializer that accepts a pre-built view model.
    init(viewModel: PaywallHostViewModel, onPurchaseComplete: (() -> Void)? = nil) {
        self._viewModel = State(initialValue: viewModel)
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
                        // Plan toggle and pricing.
                        if !viewModel.products.isEmpty {
                            PlanSelectorView(
                                products: viewModel.products,
                                selectedProduct: viewModel.selectedProduct,
                                isAnnualSelected: $viewModel.isAnnualSelected,
                                onSelect: { viewModel.selectProduct($0) }
                            )
                        }

                        // Feature comparison.
                        FeatureComparisonListView()

                        // Usage meter for free users.
                        if !viewModel.decision.blocking {
                            FreeUsageMeterView()
                        }

                        // Error message.
                        if let errorMessage = viewModel.errorMessage {
                            errorBanner(errorMessage)
                        }

                        // Purchase CTA and secondary actions.
                        PurchaseButtonSection(
                            primaryTitle: viewModel.decision.primaryCtaTitle,
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

            // Dismiss button (only for non-blocking paywalls).
            if !viewModel.isBlocking {
                dismissButton
            }
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
        .interactiveDismissDisabled(viewModel.isBlocking)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(hex: 0x1A0E05),
                Color.black
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
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, SpacingTokens.md)
                .padding(.top, SpacingTokens.md)
            }
            Spacer()
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: SpacingTokens.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ColorTokens.warning)

            Text(message)
                .font(TypographyTokens.footnote)
                .foregroundStyle(.white.opacity(0.9))
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
