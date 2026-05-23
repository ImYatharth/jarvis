import Combine
import Foundation

enum JarvisAIBackend: String, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "ChatGPT / Codex"
        case .claude: return "Claude"
        }
    }

    var shortName: String {
        switch self {
        case .codex: return "ChatGPT"
        case .claude: return "Claude"
        }
    }
}

enum JarvisVoicePreset: String, CaseIterable, Identifiable {
    case localVoice
    case cloudVoice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localVoice:
            return "Local"
        case .cloudVoice:
            return "Cloud"
        }
    }
}

enum JarvisCodexReasoningEffort: String, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .xhigh:
            return "X-High"
        }
    }

    var level: Int {
        switch self {
        case .low:
            return 1
        case .medium:
            return 2
        case .high:
            return 3
        case .xhigh:
            return 4
        }
    }
}

enum JarvisCodexServiceTier: String, CaseIterable, Identifiable {
    case standard
    case fast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .fast:
            return "Fast"
        }
    }
}

struct JarvisCodexModelOption: Identifiable, Equatable {
    let model: String
    let displayName: String
    let shortDisplayName: String
    let supportedEfforts: [JarvisCodexReasoningEffort]
    let defaultEffort: JarvisCodexReasoningEffort?
    let inputModalities: [String]
    let isDefault: Bool

    var id: String { model }

    static let fallbackPickerModels: [JarvisCodexModelOption] = [
        JarvisCodexModelOption(
            model: "gpt-5.4",
            displayName: "GPT-5.4",
            shortDisplayName: "5.4",
            supportedEfforts: JarvisCodexReasoningEffort.allCases,
            defaultEffort: .medium,
            inputModalities: ["text", "image"],
            isDefault: true
        ),
        JarvisCodexModelOption(
            model: "gpt-5.4-mini",
            displayName: "GPT-5.4 Mini",
            shortDisplayName: "5.4 Mini",
            supportedEfforts: JarvisCodexReasoningEffort.allCases,
            defaultEffort: .medium,
            inputModalities: ["text", "image"],
            isDefault: false
        )
    ]

    static let fallbackDefaultModel = "gpt-5.4"

    static func fallbackOption(for model: String) -> JarvisCodexModelOption? {
        fallbackPickerModels.first(where: { $0.model == model })
    }
}

@MainActor
final class JarvisSettings: ObservableObject {
    static let shared = JarvisSettings()

    @Published var voicePreset: JarvisVoicePreset {
        didSet { UserDefaults.standard.set(voicePreset.rawValue, forKey: Keys.voicePreset) }
    }

    @Published var showCursor: Bool {
        didSet { UserDefaults.standard.set(showCursor, forKey: Keys.showCursor) }
    }

    @Published var wakeWordEnabled: Bool {
        didSet { UserDefaults.standard.set(wakeWordEnabled, forKey: Keys.wakeWordEnabled) }
    }

    @Published var codexReasoningEffort: JarvisCodexReasoningEffort {
        didSet { UserDefaults.standard.set(codexReasoningEffort.rawValue, forKey: Keys.codexReasoningEffort) }
    }

    @Published var codexServiceTier: JarvisCodexServiceTier {
        didSet { UserDefaults.standard.set(codexServiceTier.rawValue, forKey: Keys.codexServiceTier) }
    }

    @Published var codexActionModel: String {
        didSet {
            let normalized = codexActionModel.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(
                normalized.isEmpty ? JarvisCodexModelOption.fallbackDefaultModel : normalized,
                forKey: Keys.codexActionModel
            )
        }
    }

    @Published var appleTTSVoiceIdentifier: String {
        didSet {
            if appleTTSVoiceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserDefaults.standard.removeObject(forKey: Keys.appleTTSVoiceIdentifier)
            } else {
                UserDefaults.standard.set(appleTTSVoiceIdentifier, forKey: Keys.appleTTSVoiceIdentifier)
            }
        }
    }

    @Published var aiBackend: JarvisAIBackend {
        didSet { UserDefaults.standard.set(aiBackend.rawValue, forKey: Keys.aiBackend) }
    }

    private enum Keys {
        static let productDefaultsGeneration = "jarvis.productDefaultsGeneration"
        static let voicePreset = "jarvis.voicePreset"
        static let showCursor = "jarvis.showCursor"
        static let wakeWordEnabled = "jarvis.wakeWordEnabled"
        static let aiBackend = "jarvis.aiBackend"
        static let codexReasoningEffort = "jarvis.codexReasoningEffort"
        static let codexServiceTier = "jarvis.codexServiceTier"
        static let codexActionModel = "jarvis.codexActionModel"
        static let appleTTSVoiceIdentifier = "jarvis.appleTTSVoiceIdentifier"
    }

    private static let currentProductDefaultsGeneration = 2

    private init() {
        Self.applyProductDefaultResetIfNeeded()

        voicePreset = JarvisVoicePreset(
            rawValue: UserDefaults.standard.string(forKey: Keys.voicePreset) ?? ""
        ) ?? .localVoice
        showCursor = UserDefaults.standard.object(forKey: Keys.showCursor) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.showCursor)
        wakeWordEnabled = UserDefaults.standard.bool(forKey: Keys.wakeWordEnabled)
        codexReasoningEffort = JarvisCodexReasoningEffort(
            rawValue: UserDefaults.standard.string(forKey: Keys.codexReasoningEffort) ?? ""
        ) ?? .medium
        codexServiceTier = JarvisCodexServiceTier(
            rawValue: UserDefaults.standard.string(forKey: Keys.codexServiceTier) ?? ""
        ) ?? {
            let bundledDefault = AppBundleConfiguration.stringValue(forKey: "CodexActionServiceTier") ?? ""
            return JarvisCodexServiceTier(rawValue: bundledDefault) ?? .fast
        }()
        codexActionModel = {
            let stored = UserDefaults.standard.string(forKey: Keys.codexActionModel)
                ?? AppBundleConfiguration.stringValue(forKey: "CodexActionModel")
                ?? ""
            let normalized = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? JarvisCodexModelOption.fallbackDefaultModel : normalized
        }()
        appleTTSVoiceIdentifier = UserDefaults.standard.string(forKey: Keys.appleTTSVoiceIdentifier)
            ?? AppBundleConfiguration.stringValue(forKey: "AppleTTSVoiceIdentifier")
            ?? ""
        aiBackend = JarvisAIBackend(
            rawValue: UserDefaults.standard.string(forKey: Keys.aiBackend) ?? ""
        ) ?? .codex
    }

    private static func applyProductDefaultResetIfNeeded() {
        let storedGeneration = UserDefaults.standard.integer(forKey: Keys.productDefaultsGeneration)
        guard storedGeneration < Self.currentProductDefaultsGeneration else { return }

        UserDefaults.standard.removeObject(forKey: Keys.voicePreset)
        UserDefaults.standard.removeObject(forKey: Keys.codexReasoningEffort)
        UserDefaults.standard.removeObject(forKey: Keys.codexServiceTier)
        UserDefaults.standard.removeObject(forKey: Keys.codexActionModel)
        UserDefaults.standard.removeObject(forKey: Keys.appleTTSVoiceIdentifier)
        UserDefaults.standard.set(Self.currentProductDefaultsGeneration, forKey: Keys.productDefaultsGeneration)
    }
}
