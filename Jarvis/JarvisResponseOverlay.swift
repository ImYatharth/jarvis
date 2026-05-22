import AppKit
import Combine
import SwiftUI

// MARK: - Response Overlay Window Manager

final class JarvisResponseOverlayManager: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private weak var jarvisManager: JarvisManager?

    init(jarvisManager: JarvisManager) {
        self.jarvisManager = jarvisManager
    }

    func showOrUpdate() {
        guard let jarvisManager else { return }

        if window == nil {
            createWindow(jarvisManager: jarvisManager)
        }

        guard let window else { return }

        // Position top-right, accounting for menu bar
        repositionWindow(window)
        window.orderFrontRegardless()
        window.alphaValue = 1
    }

    func hide() {
        window?.orderOut(nil)
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }

    // MARK: NSWindowDelegate — reanchor to top-right whenever content resizes

    func windowDidResize(_ notification: Notification) {
        guard let window else { return }
        repositionWindow(window)
    }

    // MARK: Private

    private func createWindow(jarvisManager: JarvisManager) {
        let contentView = JarvisResponseOverlayView(manager: jarvisManager)

        // NSHostingController with .intrinsicContentSize makes the panel
        // automatically resize whenever the SwiftUI view's ideal size changes
        // (e.g. when the user expands / collapses the body).
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.sizingOptions = .intrinsicContentSize

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentViewController = hostingController
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        // Lock width to 340 pt; height is driven by SwiftUI content size.
        hostingController.view.widthAnchor.constraint(equalToConstant: 340).isActive = true

        self.window = panel
    }

    private func repositionWindow(_ window: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 340
        let margin: CGFloat = 12

        // Keep the top-right corner pinned just below the menu bar.
        let x = screenFrame.maxX - windowWidth - margin
        let y = screenFrame.maxY - 20
        window.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }
}

// MARK: - Response Overlay SwiftUI View

struct JarvisResponseOverlayView: View {
    @ObservedObject var manager: JarvisManager

    private let collapsedHeight: CGFloat = 52
    private let expandedMaxHeight: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header — always visible
            header

            // Expanded body — shown when user taps the chevron
            if manager.isResponseOverlayExpanded {
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.horizontal, 14)

                scrollableBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: 340)
        .background(overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 18, x: 0, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: manager.isResponseOverlayExpanded)
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: manager.lastResponseText)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            // Status pulse dot
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.22))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }

            // Preview — first line of response with markdown stripped
            Text(previewText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Expand / collapse toggle
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    manager.isResponseOverlayExpanded.toggle()
                }
            } label: {
                Image(systemName: manager.isResponseOverlayExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Dismiss
            Button {
                manager.isResponseOverlayVisible = false
                manager.isResponseOverlayExpanded = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.40))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(height: collapsedHeight)
    }

    // MARK: Expanded body

    private var scrollableBody: some View {
        ScrollView(.vertical, showsIndicators: true) {
            renderedMarkdown(manager.lastResponseText)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.92))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .textSelection(.enabled)
        }
        .frame(maxHeight: expandedMaxHeight)
    }

    // MARK: Helpers

    /// Renders the response as markdown using SwiftUI's built-in AttributedString
    /// support; falls back to plain text if parsing fails.
    @ViewBuilder
    private func renderedMarkdown(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }

    /// First non-empty line of the response with markdown syntax stripped,
    /// capped at 80 characters for the collapsed header.
    private var previewText: String {
        guard !manager.lastResponseText.isEmpty else { return "Waiting for Jarvis…" }
        let firstLine = manager.lastResponseText
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? manager.lastResponseText
        let stripped = stripMarkdown(firstLine)
        if stripped.count > 80 {
            return String(stripped.prefix(80)) + "…"
        }
        return stripped.isEmpty ? "Waiting for Jarvis…" : stripped
    }

    /// Removes common markdown syntax characters while keeping the readable text.
    private func stripMarkdown(_ text: String) -> String {
        var result = text
        // Heading markers: ## Title → Title
        result = result.replacingOccurrences(
            of: #"^#{1,6}\s+"#, with: "", options: [.regularExpression, .anchored])
        // Bold / italic — preserve inner text
        result = result.replacingOccurrences(
            of: #"\*{1,3}([^*\n]+)\*{1,3}"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"_{1,3}([^_\n]+)_{1,3}"#, with: "$1", options: .regularExpression)
        // Inline code — preserve inner text
        result = result.replacingOccurrences(
            of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    private var statusColor: Color {
        switch manager.activeActionStatus {
        case .running:       return Color(red: 0.4, green: 0.7, blue: 1.0)   // blue
        case .completed:     return Color(red: 0.3, green: 0.9, blue: 0.55)  // green
        case .failed:        return Color(red: 1.0, green: 0.4, blue: 0.4)   // red
        case .interrupted:   return Color(red: 1.0, green: 0.75, blue: 0.2)  // amber
        default:             return Color.white.opacity(0.5)
        }
    }

    private var overlayBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.92))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.35))
        }
    }
}
