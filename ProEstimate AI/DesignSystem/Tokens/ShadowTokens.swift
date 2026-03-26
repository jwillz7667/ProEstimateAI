import SwiftUI

enum ShadowTokens {
    static let small = ShadowStyle(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    static let medium = ShadowStyle(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    static let large = ShadowStyle(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

extension View {
    func shadow(_ style: ShadowTokens.ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
