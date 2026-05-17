import Foundation
import UIKit

/// Persistent store for fetched brand logos — the single source of
/// real, full-colour subscription logos.
///
/// Logos come from each brand's own favicon, served by a free public
/// favicon endpoint. No token, no account, no quota worth worrying
/// about, nothing to pay for. A favicon *is* the brand's own published
/// icon, so the result is the real Netflix / Spotify / Three mark —
/// not a stand-in.
///
/// Caching design — "store them once so they load fast and don't
/// waste data":
///   - **Disk**: a logo is written to a `BrandLogos/` folder in the
///     App Group container the first time it's fetched, and read from
///     there forever after. Fetched once, then zero network.
///   - **Why not SwiftData**: a brand logo is *re-derivable cache
///     data*, not user data. Putting it in the synced store would
///     push every logo into the user's iCloud and bloat the
///     system-of-record. The App Group container is the correct home
///     — survives launches, isn't auto-purged like `Caches/`, and the
///     widget extension can read it too.
///   - **Memory**: an `NSCache` sits on top so we don't re-decode a
///     PNG every time a row scrolls past.
enum BrandLogoStore {

    // MARK: - Caches

    private static let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        return c
    }()

    /// `BrandLogos/` inside the App Group container.
    private static var cacheDirectory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupID)
        else { return nil }
        let dir = container.appendingPathComponent("BrandLogos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(for domain: String) -> URL? {
        // Domains are filesystem-safe enough, but normalise anyway.
        let safe = domain.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory?.appendingPathComponent("\(safe).png")
    }

    // MARK: - Lookup

    /// Synchronous lookup — memory then disk. Returns `nil` if the
    /// logo has never been fetched (caller can then trigger `logo`).
    static func cachedLogo(forDomain domain: String) -> UIImage? {
        let key = domain as NSString
        if let hit = memory.object(forKey: key) { return hit }
        guard let url = fileURL(for: domain),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    /// Returns the brand's logo — the cached copy if there is one,
    /// otherwise fetches it from the favicon service and persists it.
    /// `nil` only when offline on first sight or the request fails;
    /// the caller then falls back to an SF Symbol.
    static func logo(forDomain domain: String) async -> UIImage? {
        if let cached = cachedLogo(forDomain: domain) { return cached }
        guard let request = makeRequest(domain: domain) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data)
            else { return nil }
            persist(data: data, image: image, domain: domain)
            return image
        } catch {
            return nil
        }
    }

    // MARK: - Internals

    /// Google's public favicon endpoint:
    /// `https://www.google.com/s2/favicons?domain=<domain>&sz=128`.
    /// Free, unauthenticated, no quota worth worrying about. DuckDuckGo
    /// (`https://icons.duckduckgo.com/ip3/<domain>.ico`) is a drop-in
    /// alternative if this ever needs swapping.
    private static func makeRequest(domain: String) -> URLRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/s2/favicons"
        components.queryItems = [
            URLQueryItem(name: "domain", value: domain),
            URLQueryItem(name: "sz", value: "128")
        ]
        guard let url = components.url else { return nil }
        return URLRequest(url: url)
    }

    private static func persist(data: Data, image: UIImage, domain: String) {
        memory.setObject(image, forKey: domain as NSString)
        guard let url = fileURL(for: domain) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// Wipes the on-disk + in-memory logo cache. Logos are
    /// re-derivable, so this is always safe — exposed for a future
    /// "clear cache" affordance.
    static func clearCache() {
        memory.removeAllObjects()
        guard let dir = cacheDirectory else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
