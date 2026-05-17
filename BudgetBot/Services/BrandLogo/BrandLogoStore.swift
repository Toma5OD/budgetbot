import Foundation
import UIKit

/// Persistent store for *fetched* brand logos — the long-tail brands
/// the bundled simple-icons set doesn't carry (regional telcos,
/// utilities, gyms).
///
/// Caching design — answering "store them once so they load fast and
/// don't waste data":
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
///
/// The fetch tier is gated on a logo-API token (`logoAPIToken`). With
/// no token set the store is inert — the bundled marks and the SF
/// Symbol fallback still cover everything offline.
enum BrandLogoStore {

    // MARK: - API configuration

    /// UserDefaults key holding the user's logo-API publishable token.
    /// Logo-API tokens (Logo.dev, Brandfetch) are publishable, not
    /// secret — but we still keep it out of source. Empty ⇒ the fetch
    /// tier is disabled.
    static let tokenDefaultsKey = "BudgetBot.logoAPIToken"

    static var logoAPIToken: String {
        get { UserDefaults.standard.string(forKey: tokenDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: tokenDefaultsKey) }
    }

    static var isFetchEnabled: Bool { !logoAPIToken.isEmpty }

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
    /// logo has never been fetched (caller can then trigger `fetch`).
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

    /// Fetches a logo from the API tier and persists it. Returns the
    /// cached copy immediately if there already is one. `nil` when the
    /// fetch tier is disabled or the request fails — caller falls back
    /// to the SF Symbol.
    static func logo(forDomain domain: String) async -> UIImage? {
        if let cached = cachedLogo(forDomain: domain) { return cached }
        guard isFetchEnabled, let request = makeRequest(domain: domain) else { return nil }

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

    /// Logo.dev-style request: `https://img.logo.dev/<domain>?token=…`.
    /// Brandfetch's CDN follows a similar domain-keyed shape — swap the
    /// host/params here if the provider changes.
    private static func makeRequest(domain: String) -> URLRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "img.logo.dev"
        components.path = "/\(domain)"
        components.queryItems = [
            URLQueryItem(name: "token", value: logoAPIToken),
            URLQueryItem(name: "size", value: "128"),
            URLQueryItem(name: "format", value: "png"),
            URLQueryItem(name: "retina", value: "true")
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
