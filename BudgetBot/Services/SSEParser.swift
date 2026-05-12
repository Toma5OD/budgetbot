import Foundation

/// Minimal Server-Sent-Events line parser. Reads chunks of `Data`, yields
/// `(event: String?, data: String)` pairs as complete frames are seen.
///
/// SSE wire format we care about:
///
///     event: content_block_delta
///     data: {"type":"content_block_delta", ...}
///
///     event: message_stop
///     data: {"type":"message_stop"}
///
/// Frames are separated by blank lines.
struct SSEParser {

    struct Event: Equatable {
        let name: String?
        let data: String
    }

    private var buffer = ""

    /// Feed bytes, get back zero or more complete events.
    mutating func feed(_ data: Data) -> [Event] {
        guard let chunk = String(data: data, encoding: .utf8) else { return [] }
        buffer += chunk

        var events: [Event] = []
        // Split on blank-line frame boundaries. `.literal` is required so
        // Swift doesn't do Unicode-aware matching that munges consecutive \n.
        while let range = buffer.range(of: "\n\n", options: .literal) {
            let frame = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let ev = parseFrame(frame) { events.append(ev) }
        }
        return events
    }

    /// Flush any partial frame at end-of-stream.
    mutating func flush() -> Event? {
        defer { buffer = "" }
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return parseFrame(trimmed)
    }

    private func parseFrame(_ frame: String) -> Event? {
        var name: String?
        var dataParts: [String] = []
        for line in frame.components(separatedBy: "\n") {
            // SSE allows ":" comment lines — skip.
            if line.hasPrefix(":") || line.isEmpty { continue }
            if let colon = line.firstIndex(of: ":") {
                let field = String(line[..<colon])
                var value = String(line[line.index(after: colon)...])
                if value.hasPrefix(" ") { value.removeFirst() }
                switch field {
                case "event": name = value
                case "data":  dataParts.append(value)
                default:      break
                }
            }
        }
        guard !dataParts.isEmpty else { return nil }
        return Event(name: name, data: dataParts.joined(separator: "\n"))
    }
}
