import Foundation
import SwiftUI
import SwiftData

/// Owns the conversational state for the Ask tab. Multi-turn (full history
/// goes back on each request), streaming, with `query_transactions` tool use
/// executed locally against a SwiftData snapshot.
@Observable
@MainActor
final class AskViewModel {

    /// A user-visible turn. The same logical message may have multiple visible
    /// pieces (e.g. assistant text → tool call → tool result → more text).
    struct VisibleTurn: Identifiable, Hashable {
        let id = UUID()
        var role: Role
        var text: String = ""
        var toolCall: ToolCall?      // only for kind == .tool

        enum Role: Hashable { case user, assistant, tool }
        struct ToolCall: Hashable {
            let name: String
            let summary: String      // short human-readable, e.g. "Looked up 8 coffee transactions"
        }
    }

    // MARK: - State

    var turns: [VisibleTurn] = []
    var isStreaming: Bool = false
    var error: String?

    /// Conversation seed text — kept invisible to the user, sent on every turn
    /// so the AI has accounts and totals context.
    var primingContext: String = ""
    var base: String = "USD"
    var model: String = AIService.defaultModel

    /// Snapshot of every confirmed tx the AI may query against.
    var querySnapshot: [TransactionQuery.Snapshot] = []

    private var history: [AIService.AskMessage] = []
    private var inflight: Task<Void, Never>?

    // MARK: - Lifecycle

    func ask(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isStreaming else { return }
        error = nil
        isStreaming = true

        let userTurn = VisibleTurn(role: .user, text: q)
        turns.append(userTurn)

        // Add a primer for the very first user turn — the system prompt is
        // cached so we put per-session context in the first user message.
        let firstUserText: String = {
            if history.isEmpty {
                return "DATA:\n\(primingContext)\n\nQUESTION:\n\(q)"
            }
            return q
        }()

        history.append(.init(
            role: "user",
            blocks: [.text(firstUserText)]
        ))

        let assistantTurn = VisibleTurn(role: .assistant)
        turns.append(assistantTurn)

        inflight = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        inflight?.cancel()
        inflight = nil
        isStreaming = false
    }

    func reset() {
        stop()
        turns.removeAll()
        history.removeAll()
    }

    // MARK: - Agent loop

    private func run() async {
        defer { isStreaming = false }

        // Backstop for 5.1.2(i) — the UI gates on consent before
        // calling `ask`, but nothing should reach Anthropic without it
        // no matter the entry path.
        guard AIConsent.isGranted else {
            error = "AI processing needs your permission first — you'll be asked when you send a question."
            return
        }

        guard let service = AIService.fromKeychain(model: model) else {
            error = "No AI API key set. Add one in Settings."
            return
        }

        // Up to 4 streaming round-trips before we give up (prevents loops).
        for _ in 0..<4 {
            do {
                let stopReason = try await streamOne(service)
                if stopReason != "tool_use" { return }
            } catch is CancellationError {
                return
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { self.error = msg }
                return
            }
        }
    }

    /// Streams one assistant response, applying deltas to the visible turn.
    /// Returns the stop_reason ("end_turn" / "tool_use" / "max_tokens" …).
    private func streamOne(_ service: AIService) async throws -> String {
        // Track current assistant message blocks to push into `history` once
        // the stream ends.
        var assistantBlocks: [AIService.AskBlock] = []
        var currentText = ""
        var stopReason: String?
        var toolCalls: [(id: String, name: String, input: JSONValue)] = []

        for try await event in service.askStream(messages: history) {
            switch event {
            case .textDelta(let s):
                currentText += s
                await MainActor.run {
                    if var last = self.turns.last, last.role == .assistant {
                        last.text = currentText
                        self.turns[self.turns.count - 1] = last
                    }
                }
            case .toolUseStarted:
                break
            case .toolUseFinished(let id, let name, let input):
                toolCalls.append((id, name, input))
                if !currentText.isEmpty {
                    assistantBlocks.append(.text(currentText))
                    currentText = ""
                }
                assistantBlocks.append(.toolUse(id: id, name: name, input: input))
            case .messageStopped(let reason):
                stopReason = reason
            }
        }

        if !currentText.isEmpty {
            assistantBlocks.append(.text(currentText))
        }

        history.append(.init(role: "assistant", blocks: assistantBlocks))

        // Execute any tool calls and push back a single tool_result user
        // message that bundles all of them.
        if !toolCalls.isEmpty {
            var resultBlocks: [AIService.AskBlock] = []
            for call in toolCalls {
                let (resultJSON, summary) = executeTool(name: call.name, input: call.input)
                resultBlocks.append(.toolResult(toolUseID: call.id, content: resultJSON))
                await MainActor.run {
                    var t = VisibleTurn(role: .tool)
                    t.toolCall = .init(name: call.name, summary: summary)
                    self.turns.append(t)
                    // Add a fresh assistant turn for the next streaming round.
                    self.turns.append(VisibleTurn(role: .assistant))
                }
            }
            history.append(.init(role: "user", blocks: resultBlocks))
        }

        return stopReason ?? "end_turn"
    }

    // MARK: - Tools

    private func executeTool(name: String, input: JSONValue) -> (resultJSON: String, summary: String) {
        guard name == AIService.queryToolName else {
            return ("Unknown tool.", "Unknown tool: \(name)")
        }

        // Decode args.
        let argsData: Data = (try? JSONEncoder().encode(input)) ?? Data()
        let args = (try? JSONDecoder().decode(TransactionQuery.Args.self, from: argsData))
            ?? .init()

        let rows = TransactionQuery().execute(args: args, against: querySnapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(rows)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let summary = summarise(args: args, rowCount: rows.count)
        return (json, summary)
    }

    private func summarise(args: TransactionQuery.Args, rowCount: Int) -> String {
        var bits: [String] = []
        if let p = args.payee_contains { bits.append("payee ~ \(p)") }
        if let c = args.category { bits.append("\(c)") }
        if let s = args.start_date { bits.append("from \(s)") }
        if let e = args.end_date { bits.append("to \(e)") }
        if let s = args.sign { bits.append(s == "negative" ? "expenses" : "income") }
        let scope = bits.joined(separator: ", ")
        return "Looked up \(rowCount) transaction\(rowCount == 1 ? "" : "s")\(scope.isEmpty ? "" : " — \(scope)")"
    }
}
