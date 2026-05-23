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
            // Soft canvas — the dark hero strip sits at the top of the
            // scrolling content rather than the whole sheet, matching the
            // overhaul's three-tier card layout.
            ColorTokens.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: SpacingTokens.xl) {
                    heroStrip
                        .padding(.top, SpacingTokens.huge)

                    if !viewModel.products.isEmpty {
                        PlanSelectorView(
                            products: viewModel.products,
                            selectedProduct: viewModel.selectedProduct,
                            selectedTier: $viewModel.selectedTier,
                            isAnnualSelected: $viewModel.isAnnualSelected,
                            onSelect: { product in
                                viewModel.selectProduct(product)
                                Task { await viewModel.purchase() }
                            }
                        )
                    }

                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage) {
                            Task { await viewModel.purchase() }
                        }
                    }

                    if viewModel.showRestorePurchases {
                        Button {
                            Task { await viewModel.restorePurchases() }
                        } label: {
                            HStack(spacing: 6) {
                                if viewModel.isRestoring {
                                    ProgressView().controlSize(.small)
                                }
                                Text("Restore Purchases")
                                    .font(TypographyTokens.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(ColorTokens.textSecondary)
                        }
                        .disabled(viewModel.isRestoring)
                    }

                    LegalDisclosureSection(selectedProduct: viewModel.selectedProduct)
                }
                .padding(.horizontal, SpacingTokens.lg)
                .padding(.bottom, SpacingTokens.xxxl)
            }

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

    // MARK: - Hero Strip

    private var heroStrip: some View {
        VStack(alignment: .center, spacing: SpacingTokens.xs) {
            Text("PROESTIMATE AI")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(ColorTokens.heroForeground.opacity(0.65))

            Text(viewModel.decision.headline.isEmpty ? "Unlock Your Professional Potential" : viewModel.decision.headline)
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(ColorTokens.heroForeground)

            Text(viewModel.decision.subheadline.isEmpty
                ? "Scale your remodeling business with precision tools, unlimited rendering capabilities, and seamless client management. Choose the tier that matches your ambition."
                : viewModel.decision.subheadline)
                .font(TypographyTokens.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(ColorTokens.heroForeground.opacity(0.78))
                .padding(.top, SpacingTokens.xxs)
        }
        .padding(SpacingTokens.lg)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [ColorTokens.overlayAccent, ColorTokens.heroBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: RadiusTokens.hero)
        )
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
                        .foregroundStyle(ColorTokens.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(ColorTokens.surface, in: Circle())
                        .overlay(Circle().strokeBorder(ColorTokens.cardStroke, lineWidth: 1))
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
                .foregroundStyle(ColorTokens.textPrimary)
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
