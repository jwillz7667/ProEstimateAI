import SwiftUI

extension View {
    /// Constrains content to a readable width on iPad while remaining
    /// full-width on iPhone. Centers the content horizontally.
    func readableContentWidth() -> some View {
        frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
    }
}
