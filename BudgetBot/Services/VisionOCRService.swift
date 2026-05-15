import Foundation
import Vision
import UIKit

/// On-device receipt OCR using `VNRecognizeTextRequest`.
///
/// Why this exists: every receipt photo currently goes to Anthropic as
/// a base64 image. That's:
///   - **Slow** — round-trip latency + image-token processing on the
///     model side.
///   - **Expensive** — image tokens are ~10× the price of text tokens.
///   - **Brittle** — fails when offline or the API errors out.
///
/// Vision runs on-device in well under a second, costs nothing, works
/// offline, and produces clean enough text for the LLM to parse
/// structurally. We keep the LLM in the loop because turning raw
/// receipt text into our `ExtractedDraft` shape (line items, payment
/// method, dates, regional formats) is where the LLM still earns its
/// keep — Vision just hands it cleaner input.
///
/// Fallback path is left intact: when OCR fails or produces too little
/// text, the caller falls back to sending the raw image so we never
/// regress receipts that Vision can't handle (faded thermal paper,
/// handwriting, blurry phone shots).
@MainActor
enum VisionOCRService {

    /// Minimum useful text length. Below this the receipt almost
    /// certainly didn't OCR cleanly (blank Vision output, single-word
    /// shop name, etc) and we let the caller fall back to image input.
    static let minUsefulTextLength = 30

    enum OCRError: LocalizedError {
        case noImageData
        case visionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noImageData:
                return "Couldn't read the receipt image."
            case .visionFailed(let s):
                return "Text recognition failed: \(s)"
            }
        }
    }

    /// Returns the recognised text, ordered top-to-bottom and left-to-
    /// right so the resulting string reads like the original receipt.
    /// Empty string means Vision saw nothing — caller should fall back
    /// to the image path.
    static func extractText(
        from image: UIImage,
        languages: [String] = ["en-US", "en-GB", "fr-FR", "de-DE", "es-ES", "it-IT"]
    ) async throws -> String {
        guard let cgImage = image.cgImage else { throw OCRError.noImageData }

        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    cont.resume(throwing: OCRError.visionFailed(error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = stitchObservations(observations)
                cont.resume(returning: text)
            }
            // .accurate is slower than .fast but recognises receipt
            // fonts (tiny dot-matrix, low-contrast thermal) noticeably
            // better. On modern iPhones it still runs in well under
            // a second.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages
            // Receipts often have product codes / sums that aren't real
            // words — language correction would otherwise mangle them.
            // The `minimumTextHeight` default catches everything but the
            // tiniest fine print; leave it alone for now.

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(throwing: OCRError.visionFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Convenience: returns `nil` instead of throwing, plus enforces
    /// the minimum-useful-length threshold. Use this from the AI
    /// pipeline — when it returns nil, fall back to image input.
    static func extractIfUseful(
        from image: UIImage,
        minLength: Int = minUsefulTextLength
    ) async -> String? {
        do {
            let text = try await extractText(from: image)
            return text.count >= minLength ? text : nil
        } catch {
            return nil
        }
    }

    // MARK: - Stitching observations into reading order

    /// Reading order: top-to-bottom rows, then left-to-right within a
    /// row. Vision returns observations in arbitrary order with
    /// normalised coordinates (0,0 = bottom-left, 1,1 = top-right of
    /// the image), so we group by Y and sort within group by X.
    static func stitchObservations(
        _ observations: [VNRecognizedTextObservation]
    ) -> String {
        let lines: [(yCentre: CGFloat, x: CGFloat, text: String)] =
            observations.compactMap { obs in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                let bb = obs.boundingBox
                let yCentre = bb.midY
                return (yCentre, bb.minX, candidate.string)
            }
        // Group by Y so that words sitting on the same line cluster
        // together. 1% of image height is a forgiving row tolerance.
        let rowTolerance: CGFloat = 0.01
        var rows: [[(yCentre: CGFloat, x: CGFloat, text: String)]] = []
        for line in lines.sorted(by: { $0.yCentre > $1.yCentre }) {   // top-down
            if let last = rows.indices.last,
               let representative = rows[last].first,
               abs(representative.yCentre - line.yCentre) < rowTolerance {
                rows[last].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
            .map { row in
                row.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
            }
            .joined(separator: "\n")
    }
}
