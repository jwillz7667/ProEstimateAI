import SwiftUI

// MARK: - Public API

extension View {
    /// Applies the canonical card surface styling: white fill in light mode
    /// (`#EBECEB` page beneath, orange border for separation) and the
    /// system grouped-background color in dark mode. Card content adapts
    /// to the parent color scheme — slate text in light, white text in dark.
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
    /// same orange-accent treatment as cards. Adapts to the parent
    /// scheme (slate text on a `#EBECEB` fill in light mode; white text
    /// on a darker fill in dark mode).
    func formField() -> some View {
        modifier(FormFieldStyle())
    }
}

// MARK: - Card Style

/// Canonical card chrome.
///
/// In light mode the card surface is white sitting on a `#EBECEB` page
/// background, with a solid orange border (1.5pt) for separation. In
/// dark mode the card uses the system grouped-cell color with a subtle
/// orange border (1pt @ 35%). Card content inherits the parent color
/// scheme — `ColorTokens.primaryText` / `secondaryText` are adaptive,
/// so labels and secondary text resolve to slate-on-white in light and
/// system labels in dark without per-call-site overrides.
private struct GlassCardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let drawsBorder: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                ColorTokens.glassCardFill,
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
        // against the gray page background; a subtle accent in dark
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
        // Light page swallows soft shadows — keep elevation readable.
        colorScheme == .light ? 0.08 : 0.06
    }
}

// MARK: - Form Field Style

/// Input chrome shared by inline form fields. In light mode the field
/// fill is the page-background gray (`#EBECEB`) so an input sits visually
/// inset against a white card. In dark mode the field is a hair lighter
/// than the surrounding card. Foreground tracks `primaryText`, which
/// resolves to slate in light mode and system label in dark.
private struct FormFieldStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(SpacingTokens.sm)
            .background(
                ColorTokens.glassFieldFill,
                in: RoundedRectangle(cornerRadius: RadiusTokens.small)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .foregroundStyle(ColorTokens.primaryText)
    }

    private var borderColor: Color {
        switch colorScheme {
        case .light: return ColorTokens.primaryOrange.opacity(0.55)
        case .dark: return ColorTokens.primaryOrange.opacity(0.3)
        @unknown default: return ColorTokens.primaryOrange.opacity(0.3)
        }
    }

    private var borderWidth: CGFloat {
        colorScheme == .light ? 1 : 1
    }
}
