import SwiftUI

enum ShadowTokens {
    /// Light card lift — used on standard surface cards over `background`.
    static let small = ShadowStyle(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    /// Mid-emphasis lift — pressable rows, subtle hero ambient.
    static let medium = ShadowStyle(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    /// Pronounced lift — stacked sheets, paywall tier cards.
    static let large = ShadowStyle(color: .black.opacity(0.10), radius: 24, x: 0, y: 12)
    /// Deep navy hero glow ("Ready to build?" CTA card).
    static let hero = ShadowStyle(color: Color(hex: 0x0E1A2E).opacity(0.22), radius: 20, x: 0, y: 12)

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

extension View {
    func shadow(_ style: ShadowTokens.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
