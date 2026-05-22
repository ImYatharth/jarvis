import Foundation

@MainActor
final class JarvisClaudeActionProvider: FullActionProvider {
    let displayName = "Claude"
    var stateDidChange: (() -> Void)?

    private(set) var status: JarvisActionStatus = .idle
    private(set) var authState: JarvisCodexAuthState = .unknown
    private(set) var activeTurnSummary: String?
    private(set) var debugEvents: [String] = []
    private(set) var collaborationModes: [String] = []
    private(set) var experimentalFeatures: [String] = []

    // MARK: - Model catalogue

    static let modelOptions: [JarvisCodexModelOption] = [
        JarvisCodexModelOption(
            model: "claude-opus-4-7",
            displayName: "Claude Opus 4.7",
            shortDisplayName: "Opus 4.7",
            supportedEfforts: [],
            defaultEffort: nil,
            inputModalities: ["text", "image"],
            isDefault: true
        ),
        JarvisCodexModelOption(
            model: "claude-sonnet-4-6",
            displayName: "Claude Sonnet 4.6",
            shortDisplayName: "Sonnet 4.6",
            supportedEfforts: [],
            defaultEffort: nil,
            inputModalities: ["text", "image"],
            isDefault: false
        ),
        JarvisCodexModelOption(
            model: "claude-haiku-4-5-20251001",
            displayName: "Claude Haiku 4.5",
            shortDisplayName: "Haiku 4.5",
            supportedEfforts: [],
            defaultEffort: nil,
            inputModalities: ["text", "image"],
            isDefault: false
        )
    ]

    var availableModels: [JarvisCodexModelOption] { Self.modelOptions }
    var supportedEffortsForSelectedModel: [JarvisCodexReasoningEffort] { [] }
    var accountSummary: String? { nil }

    func supportedEfforts(for model: String) -> [JarvisCodexReasoningEffort] { [] }

    // MARK: - Lifecycle

    var isConfigured: Bool {
        JarvisClaudeKeychainStore.hasConfiguredAPIKey()
    }

    var unavailableExplanation: String? {
        isConfigured ? nil : "Add a Claude API key in Settings."
    }

    var sessionStatusSummary: String {
        guard JarvisClaudeKeychainStore.hasConfiguredAPIKey() else {
            return "Claude API key required"
        }
        switch status {
        case .running: return "Claude is thinking"
        case .idle: return "Claude ready"
        default: return "Claude"
        }
    }

    var configurationSummary: String {
        let model = JarvisSettings.shared.codexActionModel
        return Self.modelOptions.first(where: { $0.model == model })?.displayName
            ?? model
    }

    var canInterruptCurrentAction: Bool {
        status == .running
    }

    func prewarmSession(forceFreshSession: Bool) async -> String? {
        guard JarvisClaudeKeychainStore.hasConfiguredAPIKey() else {
            authState = .authRequired
            stateDidChange?()
            return "Claude API key not configured."
        }
        authState = .authenticated(email: nil, plan: nil)
        stateDidChange?()
        return nil
    }

    func beginManagedLogin() async {}

    func logoutAccount() {
        JarvisClaudeKeychainStore.deleteAPIKey()
        authState = .authRequired
        stateDidChange?()
    }

    // MARK: - Submit

    func submitActionRequest(
        _ request: JarvisActionRequest,
        onEvent: @escaping @Sendable (JarvisActionEvent) -> Void
    ) async {
        guard let apiKey = JarvisClaudeKeychainStore.resolvedAPIKey() else {
            onEvent(.failed("Claude API key not configured. Add your key in Settings."))
            return
        }

        status = .running
        activeTurnSummary = "Asking Claude…"
        stateDidChange?()

        defer {
            status = .idle
            activeTurnSummary = nil
            stateDidChange?()
        }

        onEvent(.phase(JarvisActionProgress(phase: .thinking, detail: "sending your request to Claude.")))

        // Build user message content
        var userContent: [[String: Any]] = []

        if let screenshotPath = request.screenshotPath,
           let imageData = try? Data(contentsOf: URL(fileURLWithPath: screenshotPath)) {
            userContent.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ])
        }

        var contextParts: [String] = []
        if let app = request.frontmostApplicationName, !app.isEmpty {
            contextParts.append("Active app: \(app)")
        }
        if let window = request.frontmostWindowTitle, !window.isEmpty {
            contextParts.append("Window: \(window)")
        }
        if let label = request.screenshotLabel, !label.isEmpty {
            contextParts.append("Screen: \(label)")
        }

        let userText = contextParts.isEmpty
            ? request.transcript
            : "[\(contextParts.joined(separator: " | "))] \(request.transcript)"
        userContent.append(["type": "text", "text": userText])

        let model = Self.modelOptions.contains(where: { $0.model == JarvisSettings.shared.codexActionModel })
            ? JarvisSettings.shared.codexActionModel
            : "claude-opus-4-7"

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "stream": true,
            "system": """
                You are Jarvis, a screen-aware AI assistant for macOS. \
                Help the user with whatever they're doing on screen. \
                Be concise and specific. When a screenshot is provided, use it to give precise guidance.
                """,
            "messages": [["role": "user", "content": userContent]]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            onEvent(.failed("Could not build Claude request."))
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: req)

            guard let http = response as? HTTPURLResponse else {
                onEvent(.failed("No response from Claude."))
                return
            }
            switch http.statusCode {
            case 200...299:
                break
            case 401, 403:
                onEvent(.failed("Claude API key rejected. Update it in Settings."))
                return
            default:
                onEvent(.failed("Claude returned an error (HTTP \(http.statusCode))."))
                return
            }

            var fullText = ""
            for try await line in asyncBytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))
                guard jsonStr != "[DONE]",
                      let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["type"] as? String == "content_block_delta",
                      let delta = json["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let chunk = delta["text"] as? String
                else { continue }

                fullText += chunk
                onEvent(.liveUpdate(fullText))
            }

            if fullText.isEmpty {
                onEvent(.failed("Claude returned an empty response."))
            } else {
                onEvent(.completed(fullText))
            }

        } catch is CancellationError {
            onEvent(.interrupted("Interrupted."))
        } catch {
            onEvent(.failed("Claude request failed: \(error.localizedDescription)"))
        }
    }

    func cancelCurrentAction() {
        // Task cancellation comes from the manager cancelling currentResponseTask.
        // Update local state so the UI reflects the interruption immediately.
        status = .idle
        activeTurnSummary = nil
        stateDidChange?()
    }

    func respondToToolPrompt(requestID: Int, questionID: String, answer: String) {}
}
