import Foundation

/// Warms `URLCache.shared` for image URLs the user is about to see.
///
/// `AsyncImage` is the only consumer that matters for our use case, and
/// it fetches via `URLSession.shared` — which is wired through
/// `URLCache.shared`. So a successful prefetch means the AsyncImage
/// resolves from the on-disk cache the moment its View body renders,
/// instead of opening a fresh HTTPS round-trip while the placeholder
/// blinks.
///
/// Two design constraints:
///
///   1. **In-flight dedup.** A single dashboard load can submit the same
///      URL multiple times (once via the projects list, again via the
///      thumbnail map fallback path) and a navigation back to the
///      dashboard re-submits everything. Track in-flight URLs and
///      dedupe; a no-op when the URL is already pending or already
///      cached.
///
///   2. **Off the main actor.** Prefetching runs from `Task.detached`
///      with `.utility` priority so it never competes with view
///      rendering or user-driven networking. A failed prefetch is
///      silent — `AsyncImage` will retry on first render anyway.
actor ThumbnailPrefetcher {
    static let shared = ThumbnailPrefetcher()

    private var inflight: Set<URL> = []
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fire-and-forget prefetch. Returns immediately; actual network
    /// work happens on a detached `.utility` task so callers don't pay
    /// for the latency.
    nonisolated func prefetch(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.prefetchAll(urls)
        }
    }

    private func prefetchAll(_ urls: [URL]) async {
        // Dedup against both URLCache and our own inflight set up front,
        // then hand each survivor to a child task. TaskGroup is
        // unstructured-friendly: it bounds concurrency to whatever the
        // system scheduler hands us instead of `Promise.all`-blasting
        // every URL at once.
        let cache = URLCache.shared
        let pending: [URL] = urls.compactMap { url in
            if inflight.contains(url) { return nil }
            let request = Self.cacheableRequest(for: url)
            if let cached = cache.cachedResponse(for: request),
               cached.data.isEmpty == false
            {
                return nil
            }
            inflight.insert(url)
            return url
        }

        guard !pending.isEmpty else { return }

        await withTaskGroup(of: URL.self) { group in
            for url in pending {
                group.addTask { [session] in
                    let request = Self.cacheableRequest(for: url)
                    do {
                        // `URLSession.shared.data(for:)` honors the
                        // request's cache policy, so a 304 is a no-op
                        // and the cache entry is silently extended.
                        // Discard the bytes — we only care that the
                        // entry lands in URLCache for AsyncImage to
                        // pick up.
                        _ = try await session.data(for: request)
                    } catch {
                        // Silent. AsyncImage will retry on render and
                        // surface its own failure phase if needed.
                    }
                    return url
                }
            }
            for await url in group {
                inflight.remove(url)
            }
        }
    }

    /// Build a request that prefers the cache when available but falls
    /// through to the network otherwise. The handlers ship
    /// `Cache-Control: public, max-age=31536000, immutable`, so a hit
    /// here is essentially permanent until URLCache evicts on capacity
    /// pressure.
    private static func cacheableRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .returnCacheDataElseLoad
        return request
    }
}
