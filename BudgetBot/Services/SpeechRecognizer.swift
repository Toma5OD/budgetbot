import Foundation
import Speech
import AVFoundation

/// Dictation that honours the user's choice in Settings → Dictation.
///
///   - **On-device** (default): Apple's `Speech` framework streaming live
///     partial results. Free, private, offline.
///   - **Cloud** (Whisper / Gemini): records a clip, then sends it to the
///     chosen provider once you stop. More accurate; needs that key + a
///     connection. Falls back to on-device when offline if allowed.
///
/// `transcript` updates live on-device, or once after transcription for
/// cloud. The view mirrors it into its text field.
@Observable
@MainActor
final class SpeechRecognizer {

    var transcript = ""
    var isRecording = false
    var isTranscribing = false
    var errorMessage: String?
    /// A cloud recording is sitting on disk that failed to transcribe (no
    /// network, rate-limited, server hiccup). The UI shows a Retry button so
    /// the user never has to say it again. Survives app relaunch.
    var canRetry = false

    init() {
        // Surface a clip left over from a previous failed attempt.
        canRetry = FileManager.default.fileExists(atPath: Self.pendingClipURL.path)
    }

    // On-device
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    // Cloud
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    private var activeEngine: DictationEngine = .onDevice

    var isBusy: Bool { isRecording || isTranscribing }

    func toggle() {
        if isRecording { stop() } else if !isTranscribing { Task { await start() } }
    }

    func start() async {
        errorMessage = nil
        transcript = ""
        // A fresh recording supersedes any clip that failed earlier.
        clearPending()
        activeEngine = DictationSettings.effectiveEngine(isOnline: NetworkMonitor.shared.isOnline)

        guard await authorize(cloud: activeEngine.isCloud) else {
            errorMessage = "Allow microphone\(activeEngine.isCloud ? "" : " and speech") access in Settings to dictate."
            return
        }
        if activeEngine.isCloud { startCloudRecording() } else { await startOnDevice() }
    }

    func stop() {
        if activeEngine.isCloud { finishCloudRecording() } else { stopOnDevice() }
    }

    // MARK: - On-device

    private func startOnDevice() async {
        let locale = DictationSettings.languageCode.map(Locale.init(identifier:)) ?? Locale.current
        let rec = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let rec, rec.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        recognizer = rec
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.addsPunctuation = DictationSettings.addsPunctuation
            if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req

            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak req] buffer, _ in
                req?.append(buffer)
            }
            engine.prepare()
            try engine.start()

            task = rec.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || (result?.isFinal ?? false) { self.stopOnDevice() }
                }
            }
            isRecording = true
        } catch {
            errorMessage = "Couldn't start recording."
            stopOnDevice()
        }
    }

    private func stopOnDevice() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        isRecording = false
        deactivateSession()
    }

    // MARK: - Cloud

    private func startCloudRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Record straight into the persistent pending-clip slot so the
            // raw audio survives a failed transcription (and an app relaunch)
            // and can be retried without re-recording.
            let url = Self.pendingClipURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: url)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.prepareToRecord()
            guard rec.record() else {
                errorMessage = "Couldn't start recording."
                deactivateSession()
                return
            }
            recorder = rec
            recordingURL = url
            isRecording = true
        } catch {
            errorMessage = "Couldn't start recording."
            deactivateSession()
        }
    }

    private func finishCloudRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        deactivateSession()

        guard let url = recordingURL, let data = try? Data(contentsOf: url), !data.isEmpty else {
            errorMessage = "Didn't catch any audio."
            clearPending()
            return
        }
        // Remember which provider this clip is for, so a retry — even after
        // relaunch — uses the right one.
        UserDefaults.standard.set(activeEngine.rawValue, forKey: Self.pendingEngineKey)
        transcribe(engine: activeEngine)
    }

    /// Re-run transcription on the clip that's already on disk. Used both
    /// after recording and when the user taps Retry — no re-recording.
    func retry() {
        guard canRetry, !isBusy else { return }
        canRetry = false
        let engine = DictationEngine(rawValue: UserDefaults.standard.string(forKey: Self.pendingEngineKey) ?? "")
            ?? DictationSettings.effectiveEngine(isOnline: NetworkMonitor.shared.isOnline)
        guard engine.isCloud else {
            errorMessage = "Pick a cloud voice engine in Settings to transcribe this."
            canRetry = true
            return
        }
        transcribe(engine: engine)
    }

    private func transcribe(engine: DictationEngine) {
        errorMessage = nil
        isTranscribing = true
        Task {
            do {
                guard let data = try? Data(contentsOf: Self.pendingClipURL), !data.isEmpty else {
                    throw CloudTranscriber.TranscribeError.empty
                }
                transcript = try await CloudTranscriber.transcribe(data, mimeType: "audio/m4a", engine: engine)
                clearPending()          // success — drop the clip
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                canRetry = true         // keep the clip; let the user retry
            }
            isTranscribing = false
        }
    }

    // MARK: - Pending clip (offline / failed-transcription retry)

    static let pendingEngineKey = "BudgetBot.dictation.pendingEngine"

    /// Stable on-disk home for the last cloud recording. In Caches so it's
    /// non-precious but survives backgrounding and relaunch for retries.
    static var pendingClipURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingDictation", isDirectory: true)
            .appendingPathComponent("clip.m4a")
    }

    private func clearPending() {
        try? FileManager.default.removeItem(at: Self.pendingClipURL)
        UserDefaults.standard.removeObject(forKey: Self.pendingEngineKey)
        canRetry = false
    }

    // MARK: - Shared

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func authorize(cloud: Bool) async -> Bool {
        if !cloud {
            let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
            }
            guard speechOK else { return false }
        }
        return await AVAudioApplication.requestRecordPermission()
    }
}
