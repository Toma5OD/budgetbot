import XCTest
@testable import BudgetBot

/// Locks in the fix for the bug where every cloud dictation came back
/// "Didn't catch any speech": gpt-4o-mini-transcribe returns the transcript
/// alongside a `usage` object, which the old flat [String:String] decode
/// choked on, zeroing out the text.
final class CloudTranscriberTests: XCTestCase {

    func test_parsesText_despiteUsageObject() {
        let json = #"{"text":"two coffees thirteen euro","usage":{"type":"tokens","input_tokens":5,"output_tokens":4}}"#
            .data(using: .utf8)!
        XCTAssertEqual(CloudTranscriber.transcript(fromOpenAIResponse: json), "two coffees thirteen euro")
    }

    func test_parsesPlainWhisperShape() {
        let json = #"{"text":"haircut thirty euro"}"#.data(using: .utf8)!
        XCTAssertEqual(CloudTranscriber.transcript(fromOpenAIResponse: json), "haircut thirty euro")
    }

    func test_emptyTextStillDecodes() {
        // A genuinely silent clip → decodes to "" (caller maps that to a
        // clear "silent" message), not a decode failure.
        let json = #"{"text":""}"#.data(using: .utf8)!
        XCTAssertEqual(CloudTranscriber.transcript(fromOpenAIResponse: json), "")
    }

    func test_rejectsNonTranscriptionShape() {
        let json = #"{"error":{"message":"bad request","type":"invalid_request_error"}}"#.data(using: .utf8)!
        XCTAssertNil(CloudTranscriber.transcript(fromOpenAIResponse: json))
    }
}
