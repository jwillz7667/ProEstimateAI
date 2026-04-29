import SwiftUI

// MARK: - Public API

extension View {
    /// Applies the canonical card surface styling: dark slate fill in
    /// light mode, brand-orange border, and a forced dark colorScheme on
    /// the receiver's content so text and icons inside the card render
    /// against the dark surface without per-call-site changes.
    func glassCard(cornerRadius: CGFloat = RadiusTokens.card) -> some View {
        modifier(GlassCardStyle(cornerRadius: cornerRadius, drawsBorder: true))
    }

    /// Variant without a stroked border — same surface and content
    /// styling, but used where the parent container draws its own border
    /// (e.g. composite cards built from multiple sub-cards).
    func glassSurface(cornerRadius: CGFloat = RadiusTokens.card) -> some View {
        modifier(GlassCardStyle(cornerRadius: cornerRadius, drawsBorder: false))
    }

    /// Form-field chrome — a thin pill of input background with the
    /// same orange-accent treatment as cards. Inputs inside cards
    /// inherit the parent card's dark colorScheme, so their text reads
    /// white in light mode automatically.
    func formField() -> some View {
        modifier(FormFieldStyle())
    }
}

// MARK: - Card Style

/// Canonical card chrome.
///
/// In light mode the card surface is intentionally dark slate (`#2A323A`)
/// and the receiver's content is rendered with `\.colorScheme = .dark`
/// so labels, secondary text, system materials, and SF Symbols inside
/// adapt to the dark surface without each call site having to override
/// foreground colors. The stroked orange border sits at full opacity in
/// light mode (1.5pt) for clear separation against the white page
/// background, and at 0.35 opacity in dark mode (1pt) as a subtle accent
/// on the existing dark page background.
private struct GlassCardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let drawsBorder: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, .dark)
            .background(
                ColorTokens.surface,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay {
                if drawsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: 8, x: 0, y: 4)
    }

    private var borderColor: Color {
        // Solid brand orange in light mode for confident separation
        // against the white page background; a subtle accent in dark
        // mode where the existing chrome is already low-contrast.
        switch colorScheme {
        case .light: return ColorTokens.primaryOrange
        case .dark: return ColorTokens.primaryOrange.opacity(0.35)
        @unknown default: return ColorTokens.primaryOrange.opacity(0.35)
        }
    }

    private var borderWidth: CGFloat {
        colorScheme == .light ? 1.5 : 1
    }

    private var shadowOpacity: Double {
        // White page background swallows soft shadows — bump up in
        // light mode so the elevation reads.
        colorScheme == .light ? 0.12 : 0.06
    }
}

// MARK: - Form Field Style

/// Input chrome shared by inline form fields. Mirrors the card's dark
/// surface + orange accent in light mode so freestanding inputs (not
/// inside a card) carry the same theme.
private struct FormFieldStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(SpacingTokens.sm)
            .environment(\.colorScheme, .dark)
            .background(
                ColorTokens.inputBackground,
                in: RoundedRectangle(cornerRadius: RadiusTokens.small)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .foregroundStyle(ColorTokens.onDarkPrimary)
    }

    private var borderColor: Color {
        switch colorScheme {
        case .light: return ColorTokens.primaryOrange.opacity(0.85)
        case .dark: return ColorTokens.primaryOrange.opacity(0.3)
        @unknown default: return ColorTokens.primaryOrange.opacity(0.3)
        }
    }

    private var borderWidth: CGFloat {
        colorScheme == .light ? 1.25 : 1
    }
}
