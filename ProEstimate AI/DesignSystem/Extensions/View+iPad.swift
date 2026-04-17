import SwiftUI

extension View {
    /// Constrains content to a readable width on iPad while remaining
    /// full-width on iPhone. Centers the content horizontally.
    func readableContentWidth() -> some View {
        frame(maxWidth: 700, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Narrower constraint for forms and auth screens on iPad.
    func readableFormWidth() -> some View {
        frame(maxWidth: 500, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
