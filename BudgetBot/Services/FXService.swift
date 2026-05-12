import Foundation
import SwiftData

/// Single source of truth for foreign-exchange conversion.
///
/// - Fetches ECB's free daily feed (no key, no rate limit):
///   https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml
/// - Rates are expressed as "1 EUR = X currency". Cross-pair conversion goes
///   through EUR.
/// - Cached in SwiftData (`FXRateSnapshot`) so cold-start has *some* rates even
///   when offline. Refresh is best-effort and never blocks the UI.
@MainActor
@Observable
final class FXService {

    private(set) var rates: [String: Decimal] = ["EUR": 1.0]
    private(set) var fetchedAt: Date?
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private let container: ModelContainer
    private let session: URLSession

    init(container: ModelContainer, session: URLSession = .shared) {
        self.container = container
        self.session = session
        loadCached()
    }

    // MARK: - Public

    /// Convert `amount` denominated in `from` to `to`. Returns `amount` unchanged
    /// if either rate is missing — better to display the original number than to
    /// silently fabricate a converted value.
    nonisolated static func convert(
        _ amount: Decimal,
        from: String,
        to: String,
        rates: [String: Decimal]
    ) -> Decimal {
        let f = from.uppercased(), t = to.uppercased()
        if f == t { return amount }
        guard let fromRate = rates[f], let toRate = rates[t], fromRate > 0 else {
            return amount
        }
        let inEUR = amount / fromRate
        return inEUR * toRate
    }

    func convert(_ amount: Decimal, from: String, to: String) -> Decimal {
        Self.convert(amount, from: from, to: to, rates: rates)
    }

    /// Pull fresh rates if cached are older than `maxAge`. Best-effort.
    func refreshIfStale(maxAge: TimeInterval = 24 * 60 * 60) async {
        if let f = fetchedAt, Date().timeIntervalSince(f) < maxAge { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let url = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastError = "ECB HTTP error"; return
            }
            let parsed = try ECBRateParser().parse(data)
            var merged = parsed
            merged["EUR"] = 1.0
            rates = merged
            fetchedAt = Date()
            lastError = nil
            persist(rates: merged, at: fetchedAt!)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Persistence

    private func loadCached() {
        let ctx = container.mainContext
        let descriptor = FetchDescriptor<FXRateSnapshot>(sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)])
        if let snap = (try? ctx.fetch(descriptor))?.first {
            var r = snap.rates
            r["EUR"] = 1.0
            self.rates = r
            self.fetchedAt = snap.fetchedAt
        }
    }

    private func persist(rates: [String: Decimal], at date: Date) {
        let ctx = container.mainContext
        // Replace previous snapshots so the table never grows.
        if let existing = try? ctx.fetch(FetchDescriptor<FXRateSnapshot>()) {
            for old in existing { ctx.delete(old) }
        }
        let stringified = rates.mapValues { "\($0)" }
        let json = (try? JSONEncoder().encode(stringified)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        ctx.insert(FXRateSnapshot(fetchedAt: date, ratesJSON: json))
        try? ctx.save()
    }
}

// MARK: - ECB XML parser

/// Minimal `XMLParser` adaptor for the ECB daily file.
///
/// Document shape:
///
///     <gesmes:Envelope>
///       <Cube>
///         <Cube time="2026-05-12">
///           <Cube currency="USD" rate="1.0800"/>
///           <Cube currency="GBP" rate="0.8600"/>
///           ...
///         </Cube>
///       </Cube>
///     </gesmes:Envelope>
final class ECBRateParser: NSObject, XMLParserDelegate {
    enum ParseError: Error { case malformed }
    private var rates: [String: Decimal] = [:]
    private var didParse = false

    func parse(_ data: Data) throws -> [String: Decimal] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw ParseError.malformed }
        guard didParse else { throw ParseError.malformed }
        return rates
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Cube" else { return }
        if let currency = attributeDict["currency"],
           let rateString = attributeDict["rate"],
           let rate = Decimal(string: rateString) {
            rates[currency] = rate
            didParse = true
        }
    }
}
