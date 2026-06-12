import SwiftUI
import SwiftData

/// Streaming, multi-turn Q&A. The AI sees a primer summary on first turn and
/// can call `query_transactions` to fetch precise data on demand.
struct AskView: View {
    @Environment(\.modelContext) private var context
    @Environment(FXService.self) private var fx
    @Query(filter: #Predicate<Transaction> { $0.confirmed }, sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    @Query(filter: #Predicate<Account> { !$0.archived }, sort: \Account.createdAt)
    private var accounts: [Account]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var vm = AskViewModel()
    @State private var question = ""
    @State private var showAIConsent = false
    @State private var showNeedsKey = false
    @State private var pendingQuestion: String?

    private let suggestions = [
        "How much did I spend on coffee in the last 30 days?",
        "What's my biggest recurring expense?",
        "Did I spend more on Dining this month vs last?",
        "Where can I realistically cut $50/month?"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if vm.turns.isEmpty && !vm.isStreaming {
                                emptyState
                            }
                            ForEach(vm.turns) { turn in
                                TurnView(turn: turn).id(turn.id)
                            }
                            if let e = vm.error {
                                Text(e).font(.callout).foregroundStyle(.red).padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: vm.turns.last?.text) { _, _ in
                        if let last = vm.turns.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: vm.turns.count) { _, _ in
                        if let last = vm.turns.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("Ask about your money…", text: $question, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { send() }
                        .accessibilityLabel("Question")

                    if vm.isStreaming {
                        Button {
                            vm.stop()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title3).padding(8)
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Stop AI response")
                    } else {
                        Button {
                            send()
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.title3).padding(8)
                        }
                        .disabled(!canSend)
                        .accessibilityLabel("Send question")
                    }
                }
                .padding()
            }
            .navigationTitle("Ask")
            .appHeaderToolbar()
            .toolbar {
                if !vm.turns.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New") { vm.reset() }
                            .accessibilityLabel("Start a new conversation")
                    }
                }
            }
            .onAppear { hydrate() }
            .sheet(isPresented: $showAIConsent) {
                AIConsentSheet {
                    if let q = pendingQuestion {
                        pendingQuestion = nil
                        question = ""
                        vm.ask(q)
                    }
                }
            }
            .alert("AI key needed", isPresented: $showNeedsKey) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Ask uses AI to answer from your records. Add your Anthropic API key in Settings → AI to turn it on.")
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask anything about your money. I'll fetch the data I need on the fly using a `query_transactions` tool — so the answers are based on your actual records, not on guesses.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Text("Try:").font(.subheadline.bold()).padding(.horizontal).padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        question = s
                        send()
                    } label: {
                        HStack {
                            Text(s).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(.tint)
                        }
                        .padding(12)
                        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Try: \(s)")
                }
            }
            .padding(.horizontal)
        }
    }

    private var canSend: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isStreaming
    }

    private func send() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        // No key → point at Settings instead of erroring after the fact.
        // The key is optional app-wide; only the AI features need it.
        guard KeychainService.shared.get(.anthropicAPIKey)?.isEmpty == false else {
            showNeedsKey = true
            return
        }
        // 5.1.2(i): explicit permission before the question (and any
        // transaction summaries the agent fetches) goes to the AI
        // service. One-time; revocable in Settings → AI.
        guard AIConsent.isGranted else {
            pendingQuestion = q
            showAIConsent = true
            return
        }
        question = ""
        vm.ask(q)
    }

    private func hydrate() {
        let base = profiles.first?.baseCurrency ?? profiles.first?.defaultCurrency ?? "USD"
        vm.base = base
        vm.model = profiles.first?.aiModel ?? AIService.defaultModel
        vm.primingContext = buildPrimer(base: base)
        // Flatten transactions to one row per (transaction or split), so the
        // AI can query by category at the right granularity.
        var snaps: [TransactionQuery.Snapshot] = []
        for tx in transactions {
            let convert: (Decimal, String, String) -> Decimal = { fx.convert($0, from: $1, to: $2) }
            if tx.splitItems.isEmpty {
                snaps.append(.init(
                    date: tx.date,
                    payee: tx.payee,
                    category: tx.category?.name ?? "Uncategorised",
                    account: tx.account?.name ?? "?",
                    amount: tx.amount,
                    currency: tx.currency,
                    amountInBase: tx.amountInBase(base, liveConvert: convert),
                    baseCurrency: base
                ))
            } else {
                for s in tx.splitItems {
                    snaps.append(.init(
                        date: s.date,
                        payee: s.payee,
                        category: s.category?.name ?? "Uncategorised",
                        account: s.account?.name ?? "?",
                        amount: s.amount,
                        currency: s.currency,
                        amountInBase: s.amountInBase(base, liveConvert: convert),
                        baseCurrency: base
                    ))
                }
            }
        }
        vm.querySnapshot = snaps
    }

    private func buildPrimer(base: String) -> String {
        var s = "Base currency: \(base)\n"
        s += "Today: \(ISO8601DateFormatter.dayOnly.string(from: Date()))\n\n"
        s += "ACCOUNTS:\n"
        for a in accounts {
            let bal = fx.convert(a.balance, from: a.currency, to: base)
            s += "- \(a.name) (\(a.kind.displayName), \(a.currency)): \(a.balance) \(a.currency)"
            if a.currency != base {
                s += " (~\(NSDecimalNumber(decimal: bal).doubleValue.rounded()) \(base))"
            }
            s += "\n"
        }
        if let budget = profiles.first?.monthlyBudget {
            s += "\nMonthly budget: \(budget) \(base)\n"
        }
        s += "\nTransactions are not included verbatim — call the `query_transactions` tool when you need them."
        return s
    }
}

private struct TurnView: View {
    let turn: AskViewModel.VisibleTurn

    var body: some View {
        switch turn.role {
        case .user:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.crop.circle.fill").foregroundStyle(.tint)
                Text(turn.text).font(.body).fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal)

        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                if turn.text.isEmpty {
                    HStack(spacing: 4) {
                        Circle().fill(.secondary).frame(width: 6, height: 6)
                        Circle().fill(.secondary).frame(width: 6, height: 6).opacity(0.6)
                        Circle().fill(.secondary).frame(width: 6, height: 6).opacity(0.3)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Thinking")
                } else {
                    Text(turn.text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal)

        case .tool:
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "wand.and.stars").font(.caption).foregroundStyle(.secondary)
                Text(turn.toolCall?.summary ?? "").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 28)
        }
    }
}

extension ISO8601DateFormatter {
    static let dayOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
