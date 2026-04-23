import Foundation
import UIKit

/// Simple async image fetcher used when a `UIImage` is required at a specific
/// moment — e.g. right before rendering a PDF. SwiftUI `AsyncImage` is great
/// for on-screen rendering but can't hand a `UIImage` to UIKit code; this
/// closes that gap without pulling in a full image caching framework.
///
/// Relies entirely on URLSession's built-in HTTPURLResponse cache. Backend
/// image endpoints return immutable cache headers, so repeat calls within a
/// session are fast and network-free.
enum ImageFetcher {
    enum FetchError: LocalizedError {
        case badStatus(code: Int)
        case notAnImage

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "Image server returned HTTP \(code)."
            case .notAnImage:          return "Downloaded bytes were not a decodable image."
            }
        }
    }

    /// Fetches the bytes at `url` and decodes them into a `UIImage`. Throws on
    /// network failure, non-2xx HTTP status, or undecodable bytes.
    static func fetch(_ url: URL) async throws -> UIImage {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.badStatus(code: http.statusCode)
        }
        guard let image = UIImage(data: data) else {
            throw FetchError.notAnImage
        }
        return image
    }
}
