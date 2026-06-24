import Foundation
import Speech
import AVFoundation

/// On-device dictation built on Apple's `Speech` framework + `AVAudioEngine`.
/// Free, private, works offline where the device supports it — no server,
/// no API key. Drives the mic button on the quick-add sheet.
///
/// Lifecycle: `toggle()` from the UI. `transcript` updates live with
/// partial results; the view mirrors it into its text field.
@Observable
@MainActor
final class SpeechRecognizer {

    var transcript = ""
    var isRecording = false
    var errorMessage: String?

    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    init(localeIdentifier: String = Locale.current.identifier) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
            ?? SFSpeechRecognizer()
    }

    func toggle() {
        if isRecording { stop() } else { Task { await start() } }
    }

    func start() async {
        errorMessage = nil
        guard await authorize() else {
            errorMessage = "Allow microphone and speech access in Settings to dictate."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        do {
            try beginSession(recognizer: recognizer)
            isRecording = true
        } catch {
            errorMessage = "Couldn't start recording."
            cleanup()
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        isRecording = false
        deactivateSession()
    }

    // MARK: - Internals

    private func beginSession(recognizer: SFSpeechRecognizer) throws {
        task?.cancel()
        task = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }
    }

    private func cleanup() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        isRecording = false
        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func authorize() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
