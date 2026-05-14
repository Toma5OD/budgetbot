import Foundation
import UIKit

/// Talks to the Anthropic Messages API using the user's own API key.
///
/// Smart-mode integration:
/// - Forces well-typed structured output via **tool_use** (`tools` + `tool_choice`),
///   so we never parse prose JSON.
/// - Caches the long system prompt with `cache_control: ephemeral` so repeated
///   extractions / recommendations are cheaper and faster.
/// - Retries 429 / 5xx / transient-network failures with exponential backoff + jitter.
/// - Per-request timeout via a dedicated `URLSession` config.
/// - Honours `Task.checkCancellation()` so user-cancelled work releases the connection.
/// - Passes optional account context so the model can hint which account each
///   transaction belongs to.
struct AIService {

    // MARK: - Errors

    enum AIError: LocalizedError {
        case missingKey
        case http(Int, String)
        case decoding(String)
        case empty
        case cancelled
        case transient

        var errorDescription: String? {
            switch self {
            case .missingKey:        return "No AI API key set. Add one in Settings."
            case .http(let c, let m): return "AI request failed (HTTP \(c)): \(m)"
            case .decoding(let m):   return "Couldn't read AI response: \(m)"
            case .empty:             return "AI returned no usable content."
            case .cancelled:         return "Cancelled."
            case .transient:         return "Temporary AI failure — retry."
            }
        }
    }

    // MARK: - Inputs

    enum Input {
        case image(UIImage)
        case pdf(Data, filename: String?)
        case text(String)
    }

    // MARK: - Config

    static let defaultModel = "claude-sonnet-4-6"
    private let endpoint   = URL(string: "https://api.anthropic.com/v1/messages")!
    private let modelsURL  = URL(string: "https://api.anthropic.com/v1/models")!
    private let apiVersion = "2023-06-01"
    /// Anthropic beta header required to send PDFs as `document` content.
    private let pdfBeta = "pdfs-2024-09-25"
    /// Anthropic beta header that unlocks `cache_control` blocks.
    private let cacheBeta = "prompt-caching-2024-07-31"

    private let model: String
    private let apiKey: String
    private let session: URLSession
    /// Retry backoff is shortened in tests so the suite stays fast.
    private let backoffScale: Double

    /// Build a service. The API key is injected so callers control where it
    /// comes from (Keychain in production, a test string in tests).
    init(
        model: String = AIService.defaultModel,
        apiKey: String,
        requestTimeout: TimeInterval = 60,
        sessionConfiguration: URLSessionConfiguration? = nil,
        backoffScale: Double = 1.0
    ) {
        self.model = model
        self.apiKey = apiKey
        let cfg = sessionConfiguration ?? URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = requestTimeout
        cfg.timeoutIntervalForResource = requestTimeout * 2
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
        self.backoffScale = backoffScale
    }

    /// Convenience for production callers: pulls the user's API key from
    /// Keychain. Throws if none is set.
    static func fromKeychain(model: String = AIService.defaultModel) -> AIService? {
        guard let key = KeychainService.shared.get(.anthropicAPIKey), !key.isEmpty else {
            return nil
        }
        return AIService(model: model, apiKey: key)
    }

    // MARK: - Key validation

    /// Quick, cheap check that the key works. Hits `/v1/models` which doesn't
    /// run an LLM call. Returns `true` on HTTP 200.
    static func validate(
        key: String,
        timeout: TimeInterval = 8,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) async -> Bool {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        req.httpMethod = "GET"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let cfg = sessionConfiguration ?? URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: cfg)
        do {
            let (_, resp) = try await session.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Extraction

    /// The controlled vocabulary the AI must pick from. Mirrors
    /// `TxCategory.defaults`. If a receipt fits NONE of these, the AI sets
    /// `new_category` instead — see system prompt.
    private static let categoryEnum: [String] = [
        // Food & drink
        "Groceries", "Dining", "Coffee", "Alcohol",
        // Transport
        "Fuel", "Public Transport", "Taxi & Ride-share", "Parking", "Car Maintenance",
        // Recurring bills
        "Rent", "Mortgage", "Electricity", "Heating & Gas", "Water",
        "Internet", "Mobile Plan", "Streaming", "Other Subscriptions",
        "Insurance", "Taxes", "Bank Fees", "Loan Payment",
        // Health
        "Pharmacy", "Medical", "Personal Care",
        // Home & family
        "Home & Garden", "Pets", "Childcare",
        // Lifestyle
        "Entertainment", "Shopping", "Clothing", "Electronics",
        "Books & Media", "Hobbies", "Travel", "Education",
        "Charity", "Gifts Given",
        // Catch-all
        "Cash Withdrawal", "Other Expense",
        // Income
        "Salary", "Freelance", "Investment Returns", "Refund",
        "Gift Received", "Interest", "Other Income"
    ]

    private static let extractToolSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "drafts": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "date": [
                            "type": "string",
                            "description": "ISO 8601 date (yyyy-MM-dd). Use today if unknown."
                        ],
                        "amount": [
                            "type": "number",
                            "description": "Signed total. Negative = money OUT (expense), positive = money IN (income)."
                        ],
                        "currency": [
                            "type": "string",
                            "description": "ISO 4217 currency code detected from the receipt (e.g. EUR, USD, GBP). Read the actual currency printed/shown on the receipt — only fall back to the user's default if truly unreadable."
                        ],
                        "payee": [
                            "type": "string",
                            "description": "Merchant or counterparty. 'Unknown' if not legible."
                        ],
                        "note": [
                            "type": "string",
                            "description": "Optional short note explaining anything ambiguous, or which subset of a receipt this draft covers (e.g. 'meds-only subset of Tesco receipt')."
                        ],
                        "suggested_category": [
                            "type": "string",
                            "enum": categoryEnum,
                            "description": "BEST match from the existing categories. Pick whichever fits even loosely — only leave this empty if truly nothing in the list applies, in which case use `new_category` instead."
                        ],
                        "new_category": [
                            "type": "string",
                            "description": "Set ONLY when NO `suggested_category` value fits. Use a short, generic Title Case name (e.g. 'Vape Shop', 'Locksmith'). DO NOT use this if a category like 'Pharmacy', 'Home & Garden', 'Personal Care' already covers it. The app will create a new category from this string and reuse it next time."
                        ],
                        "account_hint": [
                            "type": "string",
                            "description": "Exact `name` from the accounts list provided in the user message, if you can tell which account this transaction belongs to. Omit if unsure."
                        ],
                        "payment_method": [
                            "type": "string",
                            "enum": ["cash", "card", "unknown"],
                            "description": "Did the receipt indicate cash or card? Look for 'CASH', 'PAID CASH', a card brand (Visa/Mastercard/Amex), a card-ending number, or 'change due' (cash). Use 'unknown' if there's no signal."
                        ],
                        "line_items": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "description": ["type": "string"],
                                    "amount":      ["type": "number"],
                                    "category":    [
                                        "type": "string",
                                        "enum": categoryEnum,
                                        "description": "Category for this single item. Omit if the whole receipt is one category — the draft's headline will cover it."
                                    ]
                                ],
                                "required": ["description", "amount"]
                            ]
                        ],
                        "confidence": [
                            "type": "number",
                            "description": "0..1 — how sure you are about this row."
                        ]
                    ],
                    "required": ["amount", "payee", "confidence"]
                ]
            ]
        ],
        "required": ["drafts"]
    ]

    private static let extractSystem = """
    You are BudgetBot, a precise financial-data extractor. The user will send you receipts, \
    invoices, bank statements, screenshots, PDFs or freeform descriptions of money in / out. \
    Report every distinct transaction via the `record_transactions` tool.

    CATEGORISATION RULES — IMPORTANT:
    - ALWAYS prefer a value from the `suggested_category` enum. The list is comprehensive: \
    Pharmacy, Personal Care, Home & Garden, Pets, Mobile Plan, Streaming, Electronics, \
    Clothing, Childcare, Education, Charity, Insurance, Bank Fees, Taxes, etc. Look at \
    every option before giving up.
    - Worked examples — these merchants ALWAYS map to these existing categories:
        Chemist Warehouse, Boots, CVS, Walgreens, LloydsPharmacy, McCabes Pharmacy → Pharmacy
        Lenehans, Woodies, Home Depot, B&Q, IKEA, Topsoil, Garden Centre → Home & Garden
        Tesco, Lidl, Aldi, SuperValu, Dunnes, Sainsbury's, Trader Joe's, Walmart → Groceries
        Starbucks, Costa, Pret, Caffè Nero, Insomnia → Coffee
        Vodafone, Three, EE, Verizon, AT&T (mobile bills) → Mobile Plan
        Netflix, Spotify, Disney+, Apple TV+ → Streaming
        Shell, BP, Circle K, Texaco, Esso (fuel) → Fuel
        Specsavers, dentist visits, GP, doctor → Medical
        H&M, Zara, Uniqlo, Penneys, Primark → Clothing
    - Use `new_category` ONLY when none of the enum values come even close. Be conservative: \
    if `Other Expense` is your fallback instinct, look at the list again first.
    - Categorise PER LINE ITEM where it's meaningfully mixed. A grocery shop that includes \
    paracetamol has TWO categories: 'Groceries' and 'Pharmacy'. Emit ONE DRAFT PER CATEGORY, \
    sum the items in each. Set `note` to "Split from <payee> receipt" on each split.
    - When everything on the receipt is one category, emit a single draft with that headline \
    category. Don't bother stamping every line_item with the same category — leave them blank \
    and the app fills them in from the headline.

    OTHER RULES:
    - `amount` is signed: negative = expense, positive = income.
    - Read the printed currency from the receipt (€, $, £, currency code or country tax \
    label). Only fall back to the user's default if truly unreadable.
    - Set `payment_method` from receipt cues: 'cash' if you see CASH/PAID CASH/change due, \
    'card' if you see a card brand or card-ending, 'unknown' otherwise.
    - If accounts are provided and you can tell which one paid (e.g. card ending matches), \
    set `account_hint` to that account's exact name.
    - `payee` is the merchant's name as you'd say it in conversation. Strip noise: "TESCO \
    DUBLIN 04 *MOBILE" → "Tesco". "CHEMIST WAREHOUSE STH KING ST" → "Chemist Warehouse".
    - Never invent a transaction. Set `confidence` low if anything is unclear.
    - Do not produce prose — only call the tool.
    """

    func extract(
        from inputs: [Input],
        defaultCurrency: String,
        accounts: [AccountContext] = []
    ) async throws -> [ExtractedDraft] {
        let key = apiKey
        guard !key.isEmpty else { throw AIError.missingKey }

        var contentBlocks: [[String: Any]] = []
        for input in inputs {
            switch input {
            case .image(let img):
                guard let jpeg = img.jpegData(compressionQuality: 0.8) else { continue }
                contentBlocks.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": jpeg.base64EncodedString()
                    ]
                ])
            case .pdf(let data, _):
                contentBlocks.append([
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": "application/pdf",
                        "data": data.base64EncodedString()
                    ]
                ])
            case .text(let txt):
                contentBlocks.append(["type": "text", "text": txt])
            }
        }

        var trailer = "Default currency: \(defaultCurrency)."
        if !accounts.isEmpty {
            let json = (try? JSONEncoder().encode(accounts)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            trailer += " The user's accounts: \(json). Set `account_hint` to one of these names when confident."
        }
        trailer += " Extract every transaction and call record_transactions."

        contentBlocks.append(["type": "text", "text": trailer])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": [[
                "type": "text",
                "text": Self.extractSystem,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tools": [[
                "name": "record_transactions",
                "description": "Record one or more financial transactions extracted from the user's materials.",
                "input_schema": Self.extractToolSchema,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tool_choice": ["type": "tool", "name": "record_transactions"],
            "messages": [[
                "role": "user",
                "content": contentBlocks
            ]]
        ]

        let raw = try await sendWithRetry(body: body, apiKey: key, includePDFBeta: containsPDF(inputs))
        let toolInput = try Self.toolUseInput(in: raw, expectedName: "record_transactions")

        struct Envelope: Codable { let drafts: [ExtractedDraftWire] }
        do {
            let env = try JSONDecoder().decode(Envelope.self, from: toolInput)
            return env.drafts.map { mapDraft($0, fallbackCurrency: defaultCurrency) }
        } catch {
            throw AIError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Recommendations

    private static let recommendToolSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "recommendations": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "kind": ["type": "string", "enum": ["silly", "savings", "general"]],
                        "title": ["type": "string", "description": "≤ 60 chars."],
                        "body":  ["type": "string", "description": "≤ 280 chars. Concrete, no lectures."],
                        "estimated_monthly_savings": ["type": "number"]
                    ],
                    "required": ["kind", "title", "body"]
                ]
            ]
        ],
        "required": ["recommendations"]
    ]

    private static let recommendSystem = """
    You are BudgetBot's coach. Given a summary of recent transactions, identify (a) silly / \
    wasteful spending the user could obviously cut, and (b) realistic savings opportunities. \
    Be concrete and specific, never lecture, and report findings via the `recommend_actions` tool only. \
    Estimate monthly savings only when you have data to support it.
    """

    func recommendations(for summary: String, defaultCurrency: String) async throws -> [RecommendationWire] {
        let key = apiKey
        guard !key.isEmpty else { throw AIError.missingKey }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": [[
                "type": "text",
                "text": Self.recommendSystem,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tools": [[
                "name": "recommend_actions",
                "description": "Surface specific spending or savings recommendations for the user.",
                "input_schema": Self.recommendToolSchema,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tool_choice": ["type": "tool", "name": "recommend_actions"],
            "messages": [[
                "role": "user",
                "content": [["type": "text", "text": summary]]
            ]]
        ]

        let raw = try await sendWithRetry(body: body, apiKey: key, includePDFBeta: false)
        let toolInput = try Self.toolUseInput(in: raw, expectedName: "recommend_actions")
        do {
            return try JSONDecoder().decode(RecommendationsWire.self, from: toolInput).recommendations
        } catch {
            throw AIError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Ask (conversational Q&A — streaming, multi-turn, tool-using)

    private static let askSystem = """
    You are BudgetBot's assistant. Answer the user's question about their finances using only \
    the DATA block and tool results provided. Be specific with numbers, currencies, and dates. \
    If you need data that isn't in the DATA block, call the `query_transactions` tool to fetch \
    it before answering — don't guess. If the data still doesn't contain the answer, say so \
    plainly — never invent figures. Use the user's base currency unless they specify otherwise.
    """

    private static let queryToolSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "start_date":     ["type": "string", "description": "Inclusive yyyy-MM-dd."],
            "end_date":       ["type": "string", "description": "Inclusive yyyy-MM-dd."],
            "payee_contains": ["type": "string", "description": "Case-insensitive substring."],
            "category":       ["type": "string", "description": "Case-insensitive substring of category name."],
            "min_amount":     ["type": "number", "description": "Absolute value lower bound."],
            "max_amount":     ["type": "number", "description": "Absolute value upper bound."],
            "sign":           ["type": "string", "enum": ["positive", "negative"]],
            "limit":          ["type": "integer", "description": "Max rows 1-200, default 100."]
        ],
        "required": []
    ]

    static let queryToolName = "query_transactions"

    /// One conversational message in the wire history.
    struct AskMessage: Codable, Hashable, Identifiable {
        var id = UUID()
        let role: String
        let blocks: [AskBlock]

        enum CodingKeys: String, CodingKey { case role, content }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(role, forKey: .role)
            try c.encode(blocks, forKey: .content)
        }

        init(role: String, blocks: [AskBlock], id: UUID = UUID()) {
            self.id = id
            self.role = role
            self.blocks = blocks
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = UUID()
            self.role = try c.decode(String.self, forKey: .role)
            self.blocks = try c.decode([AskBlock].self, forKey: .content)
        }
    }

    enum AskBlock: Codable, Hashable {
        case text(String)
        case toolUse(id: String, name: String, input: JSONValue)
        case toolResult(toolUseID: String, content: String)

        enum CodingKeys: String, CodingKey {
            case type, text, id, name, input, tool_use_id, content
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let s):
                try c.encode("text", forKey: .type)
                try c.encode(s, forKey: .text)
            case .toolUse(let id, let name, let input):
                try c.encode("tool_use", forKey: .type)
                try c.encode(id, forKey: .id)
                try c.encode(name, forKey: .name)
                try c.encode(input, forKey: .input)
            case .toolResult(let id, let content):
                try c.encode("tool_result", forKey: .type)
                try c.encode(id, forKey: .tool_use_id)
                try c.encode(content, forKey: .content)
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try c.decode(String.self, forKey: .text))
            case "tool_use":
                self = .toolUse(
                    id:    try c.decode(String.self, forKey: .id),
                    name:  try c.decode(String.self, forKey: .name),
                    input: try c.decode(JSONValue.self, forKey: .input)
                )
            case "tool_result":
                self = .toolResult(
                    toolUseID: try c.decode(String.self, forKey: .tool_use_id),
                    content:   try c.decode(String.self, forKey: .content)
                )
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                    debugDescription: "Unknown block type \(type)")
            }
        }
    }

    enum AskEvent {
        case textDelta(String)
        case toolUseStarted(id: String, name: String)
        case toolUseFinished(id: String, name: String, input: JSONValue)
        case messageStopped(stopReason: String?)
    }

    /// Streams one assistant response. Caller drives the multi-turn loop: on
    /// `messageStopped(stopReason: "tool_use")`, execute the tool and call
    /// again with the appended `tool_result`.
    func askStream(
        messages: [AskMessage]
    ) -> AsyncThrowingStream<AskEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.streamRequest(messages: messages, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamRequest(
        messages: [AskMessage],
        into continuation: AsyncThrowingStream<AskEvent, Error>.Continuation
    ) async throws {
        guard !apiKey.isEmpty else { throw AIError.missingKey }

        let encoder = JSONEncoder()
        let messagesJSON = try messages.map {
            try JSONSerialization.jsonObject(with: encoder.encode($0)) as! [String: Any]
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            "system": [[
                "type": "text",
                "text": Self.askSystem,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tools": [[
                "name": Self.queryToolName,
                "description": "Fetch a slice of the user's transactions matching the given filters. Use this whenever the user's question requires specific data not already in the DATA block.",
                "input_schema": Self.queryToolSchema,
                "cache_control": ["type": "ephemeral"]
            ]],
            "messages": messagesJSON
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue(apiKey,              forHTTPHeaderField: "x-api-key")
        req.setValue(apiVersion,          forHTTPHeaderField: "anthropic-version")
        req.setValue(cacheBeta,           forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.empty }
        guard (200..<300).contains(http.statusCode) else {
            var buf = ""
            for try await line in bytes.lines { buf += line; if buf.count > 400 { break } }
            throw AIError.http(http.statusCode, buf)
        }

        var parser = SSEParser()
        struct ToolUseAccumulator { var id: String; var name: String; var partialJSON: String = "" }
        var openToolUse: [Int: ToolUseAccumulator] = [:]

        for try await chunk in bytes {
            try Task.checkCancellation()
            let data = Data([chunk])
            for event in parser.feed(data) {
                guard let jdata = event.data.data(using: .utf8) else { continue }
                guard let obj = try? JSONSerialization.jsonObject(with: jdata) as? [String: Any] else { continue }
                let type = obj["type"] as? String ?? event.name ?? ""

                switch type {
                case "content_block_start":
                    let idx = obj["index"] as? Int ?? 0
                    if let block = obj["content_block"] as? [String: Any],
                       (block["type"] as? String) == "tool_use",
                       let id = block["id"] as? String,
                       let name = block["name"] as? String {
                        openToolUse[idx] = .init(id: id, name: name)
                        continuation.yield(.toolUseStarted(id: id, name: name))
                    }
                case "content_block_delta":
                    let idx = obj["index"] as? Int ?? 0
                    if let delta = obj["delta"] as? [String: Any] {
                        let dtype = delta["type"] as? String
                        if dtype == "text_delta", let text = delta["text"] as? String {
                            continuation.yield(.textDelta(text))
                        } else if dtype == "input_json_delta", let partial = delta["partial_json"] as? String {
                            openToolUse[idx]?.partialJSON += partial
                        }
                    }
                case "content_block_stop":
                    let idx = obj["index"] as? Int ?? 0
                    if let acc = openToolUse[idx] {
                        let json = acc.partialJSON.isEmpty ? "{}" : acc.partialJSON
                        if let data = json.data(using: .utf8),
                           let input = try? JSONDecoder().decode(JSONValue.self, from: data) {
                            continuation.yield(.toolUseFinished(id: acc.id, name: acc.name, input: input))
                        }
                        openToolUse[idx] = nil
                    }
                case "message_delta":
                    if let delta = obj["delta"] as? [String: Any],
                       let stop = delta["stop_reason"] as? String {
                        continuation.yield(.messageStopped(stopReason: stop))
                    }
                case "error":
                    let msg = (obj["error"] as? [String: Any])?["message"] as? String ?? "stream error"
                    throw AIError.http(0, msg)
                default:
                    break
                }
            }
        }
    }

    // MARK: - HTTP / retries

    private func sendWithRetry(body: [String: Any], apiKey: String, includePDFBeta: Bool) async throws -> Data {
        let maxAttempts = 4
        var lastError: Error?
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                return try await send(body: body, apiKey: apiKey, includePDFBeta: includePDFBeta)
            } catch let err as AIError {
                lastError = err
                if Self.isTransient(err) && attempt < maxAttempts {
                    let delay = Self.backoffSeconds(attempt: attempt) * backoffScale
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw err
            } catch is CancellationError {
                throw AIError.cancelled
            } catch {
                lastError = error
                if attempt < maxAttempts && Self.isTransientURL(error) {
                    let delay = Self.backoffSeconds(attempt: attempt) * backoffScale
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw AIError.http(0, error.localizedDescription)
            }
        }
        throw lastError ?? AIError.empty
    }

    private func send(body: [String: Any], apiKey: String, includePDFBeta: Bool) async throws -> Data {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        var betas = [cacheBeta]
        if includePDFBeta { betas.append(pdfBeta) }
        req.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.empty }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AIError.http(http.statusCode, msg)
        }
        return data
    }

    // MARK: - Response parsing

    /// Anthropic responses with `tool_choice: tool` always include exactly one `tool_use`
    /// content block with an `input` object. Pulls it out and re-serialises to Data for Codable.
    static func toolUseInput(in data: Data, expectedName: String) throws -> Data {
        struct Resp: Decodable {
            struct Block: Decodable {
                let type: String
                let name: String?
                let input: JSONValue?
            }
            let content: [Block]
            let stop_reason: String?
        }
        let parsed: Resp
        do { parsed = try JSONDecoder().decode(Resp.self, from: data) }
        catch { throw AIError.decoding("Top-level: \(error.localizedDescription)") }

        guard let block = parsed.content.first(where: { $0.type == "tool_use" && $0.name == expectedName }),
              let input = block.input else {
            throw AIError.decoding("No tool_use block named \(expectedName); stop_reason=\(parsed.stop_reason ?? "?")")
        }
        return try JSONEncoder().encode(input)
    }

    /// For free-form text responses (Q&A) — joins all `text` blocks in order.
    static func firstText(in data: Data) throws -> String {
        struct Resp: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let parsed = try JSONDecoder().decode(Resp.self, from: data)
        let text = parsed.content.compactMap { $0.text }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.empty }
        return text
    }

    // MARK: - Retry classification

    static func isTransient(_ err: AIError) -> Bool {
        if case .http(let code, _) = err {
            return code == 429 || (500...599).contains(code) || code == 0
        }
        return false
    }

    static func isTransientURL(_ err: Error) -> Bool {
        guard let urlErr = err as? URLError else { return false }
        switch urlErr.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet, .badServerResponse:
            return true
        default:
            return false
        }
    }

    static func backoffSeconds(attempt: Int) -> Double {
        let base = pow(2.0, Double(attempt - 1)) * 0.5    // 0.5, 1, 2, 4 …
        let jitter = Double.random(in: 0...0.4)
        return base + jitter
    }

    // MARK: - Helpers

    private func containsPDF(_ inputs: [Input]) -> Bool {
        inputs.contains { if case .pdf = $0 { return true } else { return false } }
    }

    private func mapDraft(_ w: ExtractedDraftWire, fallbackCurrency: String) -> ExtractedDraft {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let date = w.date.flatMap { df.date(from: $0) } ?? Date()

        let items = (w.line_items ?? []).map {
            ExtractedDraft.LineItem(
                description: $0.description,
                amount: Decimal($0.amount),
                category: $0.category
            )
        }
        let payment = ExtractedDraft.PaymentMethod(rawValue: w.payment_method ?? "unknown") ?? .unknown

        return ExtractedDraft(
            date: date,
            amount: Decimal(w.amount),
            currency: w.currency ?? fallbackCurrency,
            payee: w.payee ?? "Unknown",
            note: w.note,
            suggestedCategory: w.suggested_category,
            newCategory: w.new_category,
            accountHint: w.account_hint,
            paymentMethod: payment,
            lineItems: items,
            confidence: w.confidence ?? 0.5
        )
    }
}

// MARK: - Minimal JSON value for round-tripping `input`

enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self)             { self = .bool(v);   return }
        if let v = try? c.decode(Double.self)           { self = .number(v); return }
        if let v = try? c.decode(String.self)           { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self)      { self = .array(v);  return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let v):    try c.encode(v)
        case .number(let v):  try c.encode(v)
        case .string(let v):  try c.encode(v)
        case .array(let v):   try c.encode(v)
        case .object(let v):  try c.encode(v)
        }
    }
}
