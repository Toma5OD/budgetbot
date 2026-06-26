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
                        "card_brand": [
                            "type": "string",
                            "enum": ["Visa", "Mastercard", "Amex", "Discover", "Other"],
                            "description": "Set when the receipt prints the card brand (VISA, MASTERCARD, AMEX, AMERICAN EXPRESS, DISCOVER). Use 'Other' for unusual brands (UnionPay, JCB, etc). Omit if no brand is shown."
                        ],
                        "card_last4": [
                            "type": "string",
                            "description": "Exactly 4 digits — the last four of the card number. Receipts print this as 'XXXX 4242', '**** 4242', 'ending 4242', etc. Omit if not shown."
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
                        ],
                        "questions": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Specific things you need the USER to confirm because you couldn't read them confidently — a faded total, illegible line-item prices, an ambiguous date/year, a smudged merchant name. Phrase each as one short plain question, e.g. 'Couldn't read the total clearly — is it €9.24?' or 'Some item prices were unreadable — please check the items.' Leave empty when you're confident. WHENEVER you add a question, also set `confidence` below 0.7."
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
    - Categorise PER LINE ITEM by what the item ACTUALLY IS — not by the shop it came from \
    (a supermarket basket holds a need and a want at once). Put everything bought in ONE \
    payment into ONE draft: list each item in `line_items` with its own `category`, and the \
    app turns a multi-category draft into a single transaction with per-item splits. Do NOT \
    break one payment into several drafts — items bought together must stay in one draft so \
    they share one date and one merchant. Emit SEPARATE drafts only for genuinely separate \
    payments: distinct rows on a bank statement, or things clearly bought at different times.
    - Read each item IN CONTEXT — the same word can be a need or a want. "Duck" is food \
    (Groceries); an "inflatable duck" or "rubber duck" is a toy (Hobbies). "Oil" is Groceries; \
    "baby oil" is Personal Care. Use the full item text, quantity and the merchant to decide.
    - When everything on the receipt is genuinely one category, emit a single draft with that \
    headline category and leave the line_items' categories blank — the app fills them from the \
    headline. Only do this when you're SURE they're all the same; never lump a clearly different \
    item under the headline just to avoid splitting.
    - AMBIGUITY: if you can't confidently tell what an item is or which category fits (an \
    unlabelled SKU, an odd item for that merchant, a genuinely unusual quantity), make your \
    best guess but set the draft `confidence` below 0.7 so the app asks the user to confirm \
    instead of silently mis-filing it.

    OTHER RULES:
    - `amount` is signed: negative = expense, positive = income.
    - `date`: the transaction's date as yyyy-MM-dd, plus the time as yyyy-MM-dd'T'HH:mm \
    (24-hour, local) when the receipt prints one. The user message states TODAY'S date — use it \
    to resolve ambiguity: if the receipt's year is not clearly printed, assume the CURRENT year, \
    and never output a year earlier than last year unless a full 4-digit year is plainly legible \
    on the receipt. Never output a date in the future. If the receipt shows NO date at all, OMIT \
    `date` entirely — the app stamps it with the current date and time. Never guess a date. \
    If you ever emit several drafts for one event (same purchase, same day), they MUST all \
    carry the exact same date — differing years or days between items bought together is always \
    a mistake.
    - Read the printed currency from the receipt (€, $, £, currency code or country tax \
    label). Only fall back to the user's default if truly unreadable.
    - Set `payment_method` from receipt cues: 'cash' if you see CASH/PAID CASH/change due, \
    'card' if you see a card brand or card-ending, 'unknown' otherwise.
    - When `payment_method` is 'card', also extract `card_brand` (Visa / Mastercard / Amex / \
    Discover / Other) and `card_last4` (the 4 digits shown after asterisks) when the receipt \
    prints them. Common patterns to look for: 'VISA xxxx 4242', '**** 4242', 'Mastercard \
    ending 1234', 'AMEX ************1005'. Omit either field if it isn't shown.
    - If accounts are provided and you can tell which one paid (e.g. card ending matches), \
    set `account_hint` to that account's exact name.
    - `payee` is the merchant's name as you'd say it in conversation. Strip noise: "TESCO \
    DUBLIN 04 *MOBILE" → "Tesco". "CHEMIST WAREHOUSE STH KING ST" → "Chemist Warehouse".
    - Never invent a transaction. If the image or OCR text is poor and you cannot confidently \
    read something that matters — the total, line-item prices, the date, the merchant — DO NOT \
    paper over it. Instead: (a) make your best-effort guess, (b) set `confidence` below 0.7, and \
    (c) add a specific entry to `questions` naming exactly what you couldn't read (e.g. \
    "Couldn't read the total clearly — is it €9.24?"). Never bury an OCR problem in `note` while \
    leaving `confidence` high — that silently saves a guess. A low-confidence draft with clear \
    questions routes to the user for a quick confirmation instead of auto-saving.
    - Some inputs are SPOKEN transcripts, not receipts. They may contain filler words, \
    self-corrections ("no wait", "scratch that", "do that again"), and spelled-out names \
    ("that's R-A-B-E-L-O" → payee "Rabelo"). Interpret the user's FINAL intent: apply the \
    corrections, join spelled-out letters into the name, resolve relative dates ("last \
    Wednesday", "this morning") against today's date, and treat an address as the merchant's \
    location rather than the payee. One spoken sentence can describe several purchases from a \
    single seller — emit a per-category split for each item (a haircut → Personal Care, a \
    football jersey → Clothing) under that one merchant, exactly like a multi-item receipt.
    - Do not produce prose — only call the tool.
    """

    func extract(
        from inputs: [Input],
        defaultCurrency: String,
        accounts: [AccountContext] = []
    ) async throws -> [ExtractedDraft] {
        let key = apiKey
        guard !key.isEmpty else { throw AIError.missingKey }

        // OCR pre-pass: if the user has on-device OCR enabled (default
        // ON), try to extract text from every image input via Vision
        // before we send anything to the LLM. When the OCR text is long
        // enough to be useful we replace the image with a small text
        // block — Anthropic charges roughly 10× more for image tokens
        // than text tokens, so this is a big cost / latency win.
        // When OCR is empty or unconvincing (faded thermal paper,
        // handwriting, blurry shot) we keep the image so accuracy
        // never regresses.
        let useOCR = UserDefaults.standard.object(forKey: "BudgetBot.ocrEnabled") as? Bool ?? true
        var contentBlocks: [[String: Any]] = []
        for input in inputs {
            switch input {
            case .image(let img):
                var ocrText: String?
                if useOCR, let extracted = await VisionOCRService.extractIfUseful(from: img) {
                    ocrText = extracted
                }
                if let text = ocrText {
                    contentBlocks.append([
                        "type": "text",
                        "text": "RECEIPT_TEXT (extracted on-device via Vision OCR):\n\(text)"
                    ])
                } else {
                    guard let jpeg = img.jpegData(compressionQuality: 0.8) else { continue }
                    contentBlocks.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": jpeg.base64EncodedString()
                        ]
                    ])
                }
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

        // Anchor the model in real time — without this it dates receipts
        // with an unclear year to its training-era guess (often a year in
        // the past), which silently drops them out of "this month".
        var trailer = "Today's date is \(Self.isoDay(Date())). Default currency: \(defaultCurrency)."
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

    // MARK: - Rescan / refine single draft with user hint

    /// Re-runs extraction on the same receipt input, but tells the AI exactly
    /// what was wrong with the previous attempt and what the user wants
    /// corrected. Returns one refined draft (the same shape as the original).
    func refineDraft(
        _ draft: ExtractedDraft,
        userHint: String,
        inputs: [Input],
        defaultCurrency: String
    ) async throws -> ExtractedDraft {
        guard !apiKey.isEmpty else { throw AIError.missingKey }

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
        let summaryJSON = (try? JSONEncoder().encode(Self.summary(of: draft)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        contentBlocks.append([
            "type": "text",
            "text": """
            Previous extraction attempt:
            \(summaryJSON)

            User's hint about what's wrong / what to look for:
            "\(userHint)"

            Re-extract this single transaction with the hint in mind. Use the same \
            `record_transactions` tool format with EXACTLY ONE draft in the array.
            """
        ])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
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

        let raw = try await sendWithRetry(body: body, apiKey: apiKey, includePDFBeta: containsPDF(inputs))
        let toolInput = try Self.toolUseInput(in: raw, expectedName: "record_transactions")
        struct Envelope: Codable { let drafts: [ExtractedDraftWire] }
        let env = try JSONDecoder().decode(Envelope.self, from: toolInput)
        guard let wire = env.drafts.first else {
            throw AIError.decoding("Refine returned no drafts")
        }
        var refined = mapDraft(wire, fallbackCurrency: defaultCurrency)
        // Keep the user's id so the UI can swap in place.
        refined.id = draft.id
        return refined
    }

    // MARK: - Critique pass

    private static let critiqueToolSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "corrections": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "draft_index": [
                            "type": "integer",
                            "description": "0-based position in the drafts array provided in the user message."
                        ],
                        "field": [
                            "type": "string",
                            "enum": ["amount", "payee", "currency", "date",
                                     "suggested_category", "new_category",
                                     "payment_method", "card_brand", "card_last4",
                                     "note"],
                            "description": "Which field of the draft was wrong."
                        ],
                        "new_value": [
                            "type": "string",
                            "description": "Corrected value as a string. Amounts: signed decimal like '-52.10'. Dates: yyyy-MM-dd. Currency: ISO 4217. Payment method: cash/card/unknown."
                        ],
                        "rationale": [
                            "type": "string",
                            "description": "≤ 140 chars. Concrete: 'Receipt total 52.00, draft has 25.00 — misread 5 as 2'."
                        ]
                    ],
                    "required": ["draft_index", "field", "new_value", "rationale"]
                ]
            ]
        ],
        "required": ["corrections"]
    ]

    private static let critiqueSystem = """
    You are BudgetBot's quality auditor. The user is showing you:
    1. The same receipt(s) a previous AI already processed.
    2. The drafts that AI produced, as JSON.

    Your job: spot CLEAR mistakes only. Report each correction via the \
    `report_corrections` tool. If everything is correct, return an empty \
    `corrections` array — don't invent issues.

    Things to flag:
    - Misread amounts (digit confusion like 5↔2, 8↔3, 0↔6, missed decimals).
    - Wrong sign (refund shown as expense, or vice versa).
    - Wrong currency (€ vs $ vs £ misread).
    - Wrong date (year flipped, EU vs US date order misread).
    - Wrong payee.
    - Mis-categorisation that's clearly wrong (e.g. a pharmacy assigned to \
    'Other Expense' when 'Pharmacy' fits perfectly).
    - Missed transactions (the receipt has more line items than drafts).

    Things to NOT flag:
    - Style preferences. A reasonable category for a hardware shop is fine \
    even if a better one exists.
    - Adjacent categories that are both defensible (Coffee vs Dining for a \
    café meal).
    - Anything where the original AI's confidence < 0.4 and the draft is \
    plausibly correct — those need a human, not you.

    Output only via the tool. No prose.
    """

    func critique(
        drafts: [ExtractedDraft],
        against inputs: [Input],
        defaultCurrency: String
    ) async throws -> [CritiqueCorrection] {
        guard !apiKey.isEmpty else { throw AIError.missingKey }
        guard !drafts.isEmpty else { return [] }

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

        let draftsJSON = (try? JSONEncoder().encode(drafts.map(Self.summary(of:))))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        contentBlocks.append([
            "type": "text",
            "text": "Default currency: \(defaultCurrency).\n\nDrafts to audit (index matches order):\n\(draftsJSON)\n\nReport any clear mistakes."
        ])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": [[
                "type": "text",
                "text": Self.critiqueSystem,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tools": [[
                "name": "report_corrections",
                "description": "Report each clear mistake in the drafts.",
                "input_schema": Self.critiqueToolSchema,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tool_choice": ["type": "tool", "name": "report_corrections"],
            "messages": [[
                "role": "user",
                "content": contentBlocks
            ]]
        ]

        let raw = try await sendWithRetry(body: body, apiKey: apiKey, includePDFBeta: containsPDF(inputs))
        let toolInput = try Self.toolUseInput(in: raw, expectedName: "report_corrections")
        do {
            return try JSONDecoder().decode(CritiqueResult.self, from: toolInput).corrections
        } catch {
            throw AIError.decoding(error.localizedDescription)
        }
    }

    /// Compact summary the critique AI sees — keeps token count tight while
    /// preserving every field that could be wrong.
    private static func summary(of draft: ExtractedDraft) -> [String: String?] {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return [
            "date":               df.string(from: draft.date),
            "amount":             "\(draft.amount)",
            "currency":           draft.currency,
            "payee":              draft.payee,
            "suggested_category": draft.suggestedCategory,
            "new_category":       draft.newCategory,
            "payment_method":     draft.paymentMethod.rawValue,
            "note":               draft.note,
            "confidence":         "\(draft.confidence)"
        ]
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

    // MARK: - Itemise (describe an existing charge → line items)

    private static let itemiseSystem = """
    You turn a short free-text description of a purchase into itemised line items.

    You are given a MERCHANT, the charge's TOTAL with its CURRENCY (for context \
    only), a list of CATEGORIES, and the user's DESCRIPTION of what they bought. \
    Produce one line per item the description actually mentions:
    - Give each a short `description` (e.g. "Lighter", not "two lighters"), a \
      `quantity` (>= 1), and an `amount` = quantity × a realistic per-unit price \
      for that merchant.
    - Only itemise what the description mentions. NEVER invent items, and NEVER \
      inflate prices to reach the TOTAL. It is completely normal and expected for \
      your items to add up to LESS than the TOTAL — the app handles the \
      remainder. Use the TOTAL only to keep your prices realistic, not as a \
      target to hit.
    - Use positive `amount` magnitudes.
    - Pick a `category` from the provided CATEGORIES list when one clearly fits; \
      otherwise omit it.

    Emit the result through the `record_items` tool.
    """

    private static let itemiseToolSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "description": ["type": "string"],
                        "quantity": ["type": "integer", "description": "How many of this item, >= 1."],
                        "amount": ["type": "number", "description": "Line total (quantity × unit price), positive, in the given currency."],
                        "category": ["type": "string", "description": "One of the provided category names, or omit."]
                    ],
                    "required": ["description", "amount"]
                ]
            ]
        ],
        "required": ["items"]
    ]

    /// Breaks a known charge total into line items from a free-text
    /// description — "two lighters" against a €4 Centra charge becomes
    /// 2 × Lighter at €2. The returned lines are guaranteed to sum to
    /// `total` (see `reconcile`).
    ///
    /// `total` is the positive magnitude of the charge; the caller keeps
    /// the transaction's sign when persisting the lines as splits.
    func itemise(merchant: String,
                 total: Decimal,
                 currency: String,
                 description: String,
                 categories: [String]) async throws -> [ItemisedLine] {
        let key = apiKey
        guard !key.isEmpty else { throw AIError.missingKey }

        let totalString = NSDecimalNumber(decimal: total).stringValue
        let userText = """
        MERCHANT: \(merchant)
        TOTAL: \(totalString) \(currency)
        CATEGORIES: \(categories.isEmpty ? "(none)" : categories.joined(separator: ", "))
        DESCRIPTION: \(description)
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": [[
                "type": "text",
                "text": Self.itemiseSystem,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tools": [[
                "name": "record_items",
                "description": "Record the itemised line items for the charge.",
                "input_schema": Self.itemiseToolSchema,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tool_choice": ["type": "tool", "name": "record_items"],
            "messages": [[
                "role": "user",
                "content": [["type": "text", "text": userText]]
            ]]
        ]

        let raw = try await sendWithRetry(body: body, apiKey: key, includePDFBeta: false)
        let toolInput = try Self.toolUseInput(in: raw, expectedName: "record_items")
        let wire: ItemisationWire
        do {
            wire = try JSONDecoder().decode(ItemisationWire.self, from: toolInput)
        } catch {
            throw AIError.decoding(error.localizedDescription)
        }
        return wire.items.map {
            ItemisedLine(description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines),
                         quantity: max(1, $0.quantity ?? 1),
                         amount: Decimal($0.amount),
                         category: $0.category)
        }
    }

    /// Reconciles AI line items against the known `total` *honestly*:
    /// rounding noise snaps to the total, a shortfall becomes an explicit
    /// "Unaccounted" line, and an overshoot is reported (not silently
    /// scaled away) so the user decides. Pure + deterministic — unit-tested.
    static func settle(_ lines: [ItemisedLine],
                       to total: Decimal,
                       unaccountedLabel: String = "Unaccounted") -> ItemisationResult {
        guard !lines.isEmpty, total > 0 else {
            return ItemisationResult(lines: lines, status: .balanced)
        }
        let rounded = lines.map { line -> ItemisedLine in
            var l = line; l.amount = round2(max(Decimal(0), line.amount)); return l
        }
        let sum = rounded.reduce(Decimal(0)) { $0 + $1.amount }
        let tolerance = max(round2(total * (Decimal(string: "0.02") ?? 0)),
                            Decimal(string: "0.05") ?? 0)
        let diff = total - sum

        if abs(diff) <= tolerance {
            // Rounding noise — drop the residual on the largest line.
            var out = rounded
            if diff != 0, let i = out.indices.max(by: { out[$0].amount < out[$1].amount }) {
                out[i].amount += diff
            }
            return ItemisationResult(lines: out, status: .balanced)
        } else if diff > 0 {
            // Described items fall short — surface the remainder, don't pad.
            let extra = ItemisedLine(description: unaccountedLabel,
                                     quantity: 1, amount: round2(diff), category: nil)
            return ItemisationResult(lines: rounded + [extra],
                                     status: .under(remainder: round2(diff)))
        } else {
            // Items exceed the charge — the user resolves it (scale or redo).
            return ItemisationResult(lines: rounded, status: .over(excess: round2(-diff)))
        }
    }

    /// Forces `lines` to sum exactly to `total` by scaling proportionally,
    /// residual on the largest line. Only used when the user *explicitly*
    /// asks to scale an overshoot to fit — never silently.
    static func proportionalScale(_ lines: [ItemisedLine], to total: Decimal) -> [ItemisedLine] {
        guard !lines.isEmpty, total > 0 else { return lines }
        let raw = lines.map { max(Decimal(0), $0.amount) }
        let sum = raw.reduce(0, +)

        var scaled: [Decimal]
        if sum <= 0 {
            let each = round2(total / Decimal(lines.count))
            scaled = Array(repeating: each, count: lines.count)
        } else {
            scaled = raw.map { round2($0 * total / sum) }
        }
        let residual = total - scaled.reduce(0, +)
        if let maxIdx = scaled.indices.max(by: { scaled[$0] < scaled[$1] }) {
            scaled[maxIdx] += residual
        }
        return zip(lines, scaled).map { line, amt in
            var l = line; l.amount = amt; return l
        }
    }

    /// Expands any line with quantity > 1 into that many individual
    /// lines, each an equal share of the line total (rounding residual
    /// on the first). "2 × Coffee €13" becomes two "Coffee €6.50" lines
    /// so each is independently editable. Lines stay quantity 1.
    static func expandQuantities(_ lines: [ItemisedLine]) -> [ItemisedLine] {
        var out: [ItemisedLine] = []
        for line in lines {
            guard line.quantity > 1 else { out.append(line); continue }
            let q = line.quantity
            let each = round2(line.amount / Decimal(q))
            var amounts = Array(repeating: each, count: q)
            amounts[0] += line.amount - amounts.reduce(0, +)   // residual on the first
            for a in amounts {
                out.append(ItemisedLine(description: line.description,
                                        quantity: 1, amount: a, category: line.category))
            }
        }
        return out
    }

    /// Round a Decimal to 2 places, banker's-free (plain half-up).
    private static func round2(_ d: Decimal) -> Decimal {
        var value = d
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
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

    /// Parses the AI's date string — a full datetime when the receipt
    /// printed a time, a plain date otherwise. No date at all (nil/empty
    /// or unparseable) → the current date and time, so a receipt that
    /// doesn't show when it happened is stamped now.
    static func parseReceiptDate(_ raw: String?, now: Date = Date()) -> Date {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return now }
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            df.dateFormat = format
            if let d = df.date(from: raw) {
                return Self.biasTowardPresent(d, now: now)
            }
        }
        return now
    }

    /// Receipts uploaded this year are almost always *from* this year — but a
    /// faded or partly-legible year makes the model guess last year, parking
    /// the spend ~12 months in the past (and out of "this month"). This kept
    /// happening, so the prompt instruction isn't enough — we correct it here.
    ///
    /// Rules, in order:
    ///   • A receipt can't be from the future → clamp a forward-dated row to now.
    ///   • A date that's roughly a year stale (≈11–13½ months) is the classic
    ///     "right day, wrong year" misread → re-anchor its month/day to the most
    ///     recent occurrence that isn't in the future (this year if that hasn't
    ///     passed yet, otherwise last year — so a July date in June stays put).
    ///   • Anything else (genuinely recent, or clearly well over a year old and
    ///     therefore a deliberate old receipt) is left exactly as read.
    static func biasTowardPresent(_ date: Date, now: Date) -> Date {
        if date > now { return now }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let daysOld = cal.dateComponents([.day], from: date, to: now).day ?? 0
        guard (330...410).contains(daysOld) else { return date }

        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let nowYear = cal.component(.year, from: now)
        for year in stride(from: nowYear, through: nowYear - 1, by: -1) {
            comps.year = year
            if let candidate = cal.date(from: comps), candidate <= now {
                return candidate
            }
        }
        return date
    }

    /// `yyyy-MM-dd` for the given instant — used to tell the model what day
    /// it is so it doesn't guess the year on receipts with a faded date.
    static func isoDay(_ date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
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
        let date = Self.parseReceiptDate(w.date)

        let items = (w.line_items ?? []).map {
            ExtractedDraft.LineItem(
                description: $0.description,
                amount: Decimal($0.amount),
                category: $0.category
            )
        }
        let payment = ExtractedDraft.PaymentMethod(rawValue: w.payment_method ?? "unknown") ?? .unknown

        // Normalise card_last4: keep only digits, accept only exactly 4.
        let last4: String? = {
            guard let raw = w.card_last4 else { return nil }
            let digits = raw.filter(\.isNumber)
            return digits.count == 4 ? digits : nil
        }()

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
            cardBrand: w.card_brand,
            cardLast4: last4,
            lineItems: items,
            confidence: w.confidence ?? 0.5,
            questions: w.questions?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
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
