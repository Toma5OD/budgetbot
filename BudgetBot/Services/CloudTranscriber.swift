import Foundation

/// Cloud speech-to-text for the optional dictation engines. Sends a
/// recorded audio clip to the user's chosen provider and returns the
/// transcript. Mirrors gigbook's web voice path (Whisper / Gemini).
///
/// On-device dictation never touches this — see `SpeechRecognizer`.
enum CloudTranscriber {

    enum TranscribeError: LocalizedError {
        case missingKey
        case unauthorized(provider: String, code: Int)
        case rateLimited(provider: String)
        case server(provider: String, code: Int)
        case http(provider: String, code: Int, body: String)
        case empty
        case badResponse

        var errorDescription: String? {
            switch self {
            case .missingKey:
                "No API key for this voice engine — add it in Settings → API keys."
            case .unauthorized(let p, let c):
                "\(p) rejected the key (\(c)). Check it in Settings → API keys."
            case .rateLimited(let p):
                "\(p) is rate-limiting or out of credit (429). Wait a moment, then Retry."
            case .server(let p, let c):
                "\(p) had a server error (\(c)). Your recording is saved — tap Retry."
            case .http(let p, let c, let m):
                "\(p) transcription failed (\(c)). \(m)"
            case .empty:
                "Didn't catch any speech — the recording was silent or too short."
            case .badResponse:
                "Couldn't read the transcription response."
            }
        }
    }

    /// Turn an HTTP status + body into the most specific error we can, so
    /// the user sees *why* it failed (bad key vs quota vs outage) rather
    /// than a bare code.
    private static func classify(_ provider: String, _ code: Int, _ body: String) -> TranscribeError {
        switch code {
        case 401, 403: return .unauthorized(provider: provider, code: code)
        case 429:      return .rateLimited(provider: provider)
        case 500...599: return .server(provider: provider, code: code)
        default:       return .http(provider: provider, code: code, body: String(body.prefix(160)))
        }
    }

    /// Lightweight auth check for a voice provider's key — lists models and
    /// returns true on a 2xx. Lets the API keys screen tell the user a key is
    /// good before they rely on it for dictation. No audio, no user content.
    static func validate(key: String, engine: DictationEngine) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var req: URLRequest
        switch engine {
        case .whisper:
            req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            req.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        case .gemini:
            req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(trimmed)")!)
        case .onDevice:
            return false
        }
        req.timeoutInterval = 20
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode else { return false }
        return (200..<300).contains(code)
    }

    static func transcribe(_ audio: Data,
                           mimeType: String,
                           engine: DictationEngine) async throws -> String {
        guard let keyName = engine.keychainKey,
              let key = KeychainService.shared.get(keyName), !key.isEmpty else {
            throw TranscribeError.missingKey
        }
        switch engine {
        case .whisper: return try await whisper(audio, mimeType: mimeType, key: key)
        case .gemini:  return try await gemini(audio, mimeType: mimeType, key: key)
        case .onDevice: throw TranscribeError.badResponse
        }
    }

    // MARK: - OpenAI Whisper

    /// `gpt-4o-mini-transcribe` first (better on accents/noise/names),
    /// falling back to `whisper-1` for keys that don't expose it.
    private static let whisperModels = ["gpt-4o-mini-transcribe", "whisper-1"]

    private static func whisper(_ audio: Data, mimeType: String, key: String) async throws -> String {
        let ext = mimeType.contains("mp4") || mimeType.contains("m4a") ? "m4a"
                : mimeType.contains("wav") ? "wav" : "m4a"
        var lastError: TranscribeError = .badResponse

        for model in whisperModels {
            let boundary = "budgetbot.\(UUID().uuidString)"
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.httpBody = multipart(boundary: boundary, model: model,
                                     filename: "recording.\(ext)", mime: mimeType, audio: audio)
            req.timeoutInterval = 120

            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) {
                    let parsed = try? JSONDecoder().decode([String: String].self, from: data)
                    let text = (parsed?["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty { throw TranscribeError.empty }
                    return text
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                lastError = Self.classify("OpenAI", code, body)
                // Only try the fallback model on not-found / bad-request.
                if code != 404 && code != 400 { break }
            } catch let e as TranscribeError {
                throw e
            } catch {
                lastError = .badResponse
            }
        }
        throw lastError
    }

    private static func multipart(boundary: String, model: String,
                                  filename: String, mime: String, audio: Data) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("response_format", "json")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // MARK: - Google Gemini

    private static func gemini(_ audio: Data, mimeType: String, key: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(key)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": "Transcribe this audio of someone describing an expense, word for word. Reply with only the transcript text."],
                    ["inline_data": ["mime_type": mimeType, "data": audio.base64EncodedString()]]
                ]
            ]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Self.classify("Google Gemini", code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else { throw TranscribeError.badResponse }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw TranscribeError.empty }
        return trimmed
    }
}
