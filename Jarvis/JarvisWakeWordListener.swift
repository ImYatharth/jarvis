import AVFoundation
import Combine
import Foundation
import Speech

/// Always-on "Hey Jarvis" detector built on Apple's on-device Speech framework.
///
/// Runs a continuous recognition task over the microphone and watches partial
/// transcripts for a wake phrase. When detected it tears itself down (freeing
/// the mic) and fires `onWakeWordDetected`, which the manager uses to start a
/// normal dictation turn. Apple caps a single recognition task at roughly one
/// minute, so the listener proactively cycles the task before that limit and
/// restarts on any error or final result.
@MainActor
final class JarvisWakeWordListener: NSObject, ObservableObject {
    @Published private(set) var isListening = false

    /// Fired on the main actor the moment a wake phrase is heard. The listener
    /// has already stopped its audio engine by the time this runs, so the
    /// handler is free to start dictation on the same microphone.
    var onWakeWordDetected: (() -> Void)?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartWorkItem: DispatchWorkItem?
    private var lastTriggerDate = Date.distantPast

    /// Tracks intent independently of `isListening` so transient teardowns
    /// (task cycling, errors) don't make us forget we should be listening.
    private var wantsToListen = false

    /// Phrases that count as the wake word, including the mishearings Apple's
    /// dictation engine commonly produces for "Jarvis".
    private let wakePhrases = [
        "hey jarvis", "hey, jarvis", "hi jarvis", "hey jervis", "hey jarvi",
        "hey jervaise", "hey jarvris", "a jarvis", "hey travis", "hey charvis"
    ]

    override init() {
        let preferredLocales = [Locale.autoupdatingCurrent, Locale(identifier: "en-US")]
        var recognizer: SFSpeechRecognizer?
        for locale in preferredLocales {
            if let candidate = SFSpeechRecognizer(locale: locale) {
                recognizer = candidate
                break
            }
        }
        self.speechRecognizer = recognizer ?? SFSpeechRecognizer()
        super.init()
    }

    // MARK: Public control

    func start() {
        wantsToListen = true
        guard !isListening else { return }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            // Permission hasn't been granted yet (the dictation flow requests
            // it). Keep retrying quietly until it is.
            scheduleRestart(after: 3.0)
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            scheduleRestart(after: 3.0)
            return
        }

        beginRecognition()
    }

    func stop() {
        wantsToListen = false
        teardown()
    }

    /// Temporarily release the microphone (e.g. while a dictation turn borrows
    /// it) without forgetting that we want to keep listening afterwards.
    func pauseForDictation() {
        teardown()
    }

    func resume() {
        guard wantsToListen, !isListening else { return }
        start()
    }

    // MARK: Recognition lifecycle

    private func beginRecognition() {
        guard let speechRecognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("👂 JarvisWakeWordListener: failed to start audio engine: \(error)")
            teardown()
            scheduleRestart(after: 3.0)
            return
        }

        isListening = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let transcript = result.bestTranscription.formattedString.lowercased()
                    if self.containsWakePhrase(transcript) {
                        self.handleDetection()
                        return
                    }
                }
                if error != nil || (result?.isFinal ?? false) {
                    if self.wantsToListen { self.scheduleRestart(after: 0.3) }
                }
            }
        }

        // Cycle the task before Apple's ~1-minute limit ends it on its own.
        scheduleRestart(after: 50)
    }

    private func containsWakePhrase(_ transcript: String) -> Bool {
        // Only inspect the tail so a long-running partial transcript that
        // already contains the phrase doesn't keep re-triggering.
        let tail = String(transcript.suffix(48))
        return wakePhrases.contains { tail.contains($0) }
    }

    private func handleDetection() {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerDate) > 2.5 else { return }
        lastTriggerDate = now

        print("👂 JarvisWakeWordListener: wake word detected")
        teardown()              // free the mic for the dictation turn
        onWakeWordDetected?()
    }

    private func scheduleRestart(after seconds: TimeInterval) {
        restartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsToListen else { return }
            self.teardown()
            guard self.wantsToListen else { return }
            self.beginRecognition()
        }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func teardown() {
        isListening = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}
