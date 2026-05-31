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
                        // Free-tier counter — only rendered when the
                        // paywall fired because starter credits ran out.
                        // Hidden everywhere else so the rest of the app
                        // reads as "fully open" until exhaustion.
                        StarterCreditsExhaustedCard(
                            isVisible: viewModel.decision.placement == .generationLimitHit
                        )

                        // Tier + period picker.
                        if !viewModel.products.isEmpty {
                            PlanSelectorView(
                                products: viewModel.products,
                                selectedProduct: viewModel.selectedProduct,
                                selectedTier: $viewModel.selectedTier,
                                isAnnualSelected: $viewModel.isAnnualSelected
                            )
                        }

                        // Feature comparison — Free vs Pro.
                        FeatureComparisonListView()

                        // Inline catalog-load failure with retry. Purchase
                        // and restore outcomes go through `.alert(...)`
                        // bound at the bottom of this view, so this banner
                        // only fires when the StoreKit + backend catalog
                        // both failed to load.
                        if let errorMessage = viewModel.errorMessage {
                            errorBanner(errorMessage) {
                                Task { await viewModel.loadProducts() }
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
        .alert(
            viewModel.activeAlert?.title ?? "",
            isPresented: Binding(
                get: { viewModel.activeAlert != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.activeAlert = nil
                    }
                }
            ),
            presenting: viewModel.activeAlert,
            actions: { alert in
                ForEach(alert.actions, id: \.self) { action in
                    Button(action.title, role: action.buttonRole) {
                        handle(action, in: alert.context)
                    }
                }
            },
            message: { alert in
                Text(alert.message)
            }
        )
        .interactiveDismissDisabled(false)
    }

    // MARK: - Alert Action Dispatch

    /// Route a tapped alert action back into the view model. SwiftUI auto-
    /// dismisses the alert as soon as any button fires, so we only have to
    /// trigger the side-effect — the binding's `set` closure clears
    /// `activeAlert` for us.
    private func handle(_ action: PurchaseAlert.Action, in context: PurchaseAlert.Context) {
        switch action {
        case .dismiss:
            // No-op — the alert binding clears `activeAlert` automatically
            // when SwiftUI dismisses on tap.
            break
        case .tryAgain:
            switch context {
            case .purchase:
                Task { await viewModel.purchase() }
            case .restore:
                Task { await viewModel.restorePurchases() }
            }
        case .restorePurchases:
            Task { await viewModel.restorePurchases() }
        }
    }

    // MARK: - Background

    /// Adaptive paywall backdrop. Uses the same page background token as
    /// the rest of the app — white in light mode, system-dark in dark
    /// mode — so the paywall reads as part of the host theme rather than
    /// a permanently-dark "premium hero". A subtle warm orange wash at
    /// the top keeps the paywall feeling distinct from a regular screen.
    private var backgroundGradient: some View {
        ZStack {
            ColorTokens.background
                .ignoresSafeArea()
            LinearGradient(
                colors: [
                    ColorTokens.primaryOrange.opacity(0.06),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
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
                        .foregroundStyle(ColorTokens.secondaryText)
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
                .foregroundStyle(ColorTokens.primaryText)
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
