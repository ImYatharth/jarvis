# AGENTS.md - Jarvis (Main App Target)

## Core Architecture

### Voice and Codex pipeline
- `JarvisDictationManager.swift` manages push-to-talk, audio capture, and speech-to-text provider selection.
- `JarvisSpeechToTextProvider.swift` defines the STT abstraction and selects providers from the active Jarvis preset.
- `OpenAITranscriptionProvider.swift` is the default cloud STT provider using `gpt-4o-mini-transcribe`.
- `AppleSpeechTranscriptionProvider.swift` is the built-in macOS STT fallback.
- `TextToSpeechProvider.swift` defines the TTS abstraction plus provider factory logic.
- `OpenAITTSProvider.swift` is the default cloud TTS provider using `gpt-4o-mini-tts`.
- `TextToSpeechProvider.swift` also includes `AppleSystemTTSProvider` as the local speech fallback.
- `JarvisOpenAIVoiceConfiguration.swift` stores the Cloud voice API key in Keychain and validates it.
- `JarvisCodexEnvironment.swift` prepares Jarvis's isolated Codex home, bundled browser MCP config, and bundled skill inventory.
- `JarvisBundledSkills.swift` selects the Jarvis-owned and curated skills to inject into turns when the request clearly matches them.

### Actions and state
- `ActionProvider.swift` defines Jarvis's unified Codex request contract.
- `CodexAppServerActionProvider.swift` streams action progress from `codex app-server`.
- `JarvisSettings.swift` stores persisted menu bar settings in `UserDefaults`, including voice mode, Codex effort, and cursor visibility.
- `JarvisManager.swift` orchestrates Codex turns, current-screen screenshot capture, cursor overlay, and spoken summaries.

### UI shell
- `JarvisApp.swift` boots the menu bar app and startup services.
- `JarvisPanelView.swift` renders the compact panel, including Jarvis preset controls and action status.
- `MenuBarPanelManager.swift` and `OverlayWindow.swift` own the menu bar shell and cursor-adjacent overlay behavior.
- `JarvisScreenCaptureUtility.swift` captures current-screen context for Codex turns.

## Defaults

- STT default: OpenAI `gpt-4o-mini-transcribe`
- Codex model default: `gpt-5.4`
- Codex effort default: `medium`
- Codex service tier default: `fast`
- TTS default: OpenAI `gpt-4o-mini-tts`
- Local fallbacks: Apple Speech and Apple system speech
- Unified assistant path: Codex app-server
- Bundled browser tools: `chrome-devtools-mcp`, `@playwright/mcp`
- Bundled skills: `jarvis-assistant`, `doc`, `pdf`, `slides`, `spreadsheet`, `screenshot`, `transcribe`, `speech`, `openai-docs`
