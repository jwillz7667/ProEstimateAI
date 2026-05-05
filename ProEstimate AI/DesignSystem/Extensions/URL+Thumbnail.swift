import Foundation

extension URL {
    /// Append (or replace) a `?w=<width>` query item so the backend
    /// serves a resized JPEG variant instead of the original-resolution
    /// PNG. The backend snaps arbitrary widths to the nearest of
    /// {240, 480, 960}; passing one of those values keeps us aligned
    /// with its bucketing without forcing a dependency between the two
    /// constants.
    ///
    /// Existing query items are preserved — important because the same
    /// URL might already carry, e.g., a signed-link token in a future
    /// iteration. `URLComponents` round-trips us safely without
    /// corrupting the path or fragment.
    ///
    /// Returns `self` unchanged if the URL can't be decomposed (which
    /// shouldn't happen for our backend-generated URLs but isn't worth
    /// crashing over).
    func thumbnail(width: Int) -> URL {
        guard width > 0,
              var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        else { return self }

        var items = components.queryItems ?? []
        items.removeAll { $0.name == "w" }
        items.append(URLQueryItem(name: "w", value: String(width)))
        components.queryItems = items

        return components.url ?? self
    }
}
