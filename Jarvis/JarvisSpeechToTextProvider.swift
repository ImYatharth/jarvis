//
//  JarvisSpeechToTextProvider.swift
//  Jarvis
//
//  Shared protocol surface for speech-to-text backends.
//

import AVFoundation
import Foundation

protocol SpeechToTextStreamingSession: AnyObject {
    var finalTranscriptFallbackDelaySeconds: TimeInterval { get }
    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer)
    func requestFinalTranscript()
    func cancel()
}

protocol SpeechToTextProvider {
    var displayName: String { get }
    var requiresSpeechRecognitionPermission: Bool { get }
    var isConfigured: Bool { get }
    var unavailableExplanation: String? { get }

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws -> any SpeechToTextStreamingSession
}

enum JarvisSpeechToTextProviderFactory {
    static func makeProvider(for voicePreset: JarvisVoicePreset) -> any SpeechToTextProvider {
        let openAIProvider = OpenAITranscriptionProvider()
        let appleProvider = AppleSpeechTranscriptionProvider()

        switch voicePreset {
        case .localVoice:
            return appleProvider
        case .cloudVoice:
            return openAIProvider
        }
    }

    @MainActor
    static func makeDefaultProvider() -> any SpeechToTextProvider {
        let provider = makeProvider(for: JarvisSettings.shared.voicePreset)
        print("🎙️ Transcription: using \(provider.displayName)")
        return provider
    }
}
