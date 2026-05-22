#!/usr/bin/env python3
"""
Applies dot-cursor and interactive-HUD changes to the Jarvis source files.
Run from the project root: python3 scripts/update_jarvis_cursor.py
"""

import sys
from pathlib import Path

ROOT = Path.cwd()

def find_file(relative: str) -> Path:
    candidates = [ROOT / relative, Path(__file__).parent.parent / relative]
    for p in candidates:
        if p.exists():
            return p
    return None

# ── Helpers ────────────────────────────────────────────────────────────────

def replace_struct(source: str, name: str, replacement: str) -> str:
    key = f"struct {name}"
    idx = source.find(key)
    if idx == -1:
        print(f"  SKIP (not found): {key}")
        return source
    prefix_start = max(0, idx - 8)
    if source[prefix_start:idx].strip() == "private":
        idx = prefix_start + source[prefix_start:].index("private")
    brace_idx = source.index("{", idx)
    depth, i = 0, brace_idx
    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                print(f"  ✓ Replaced struct {name}")
                return source[:idx] + replacement + source[i + 1:]
        i += 1
    print(f"  SKIP (unmatched braces): {name}")
    return source

def replace_computed_property(source: str, signature: str, replacement: str) -> str:
    """Replace a `@ViewBuilder\\nprivate var <name>: some View { ... }` block."""
    idx = source.find(signature)
    if idx == -1:
        print(f"  SKIP (not found): {signature!r}")
        return source
    brace_idx = source.index("{", idx)
    depth, i = 0, brace_idx
    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                print(f"  ✓ Replaced computed property at signature {signature!r}")
                return source[:idx] + replacement + source[i + 1:]
        i += 1
    print(f"  SKIP (unmatched braces): {signature!r}")
    return source

def insert_after(source: str, anchor: str, insertion: str) -> str:
    idx = source.find(anchor)
    if idx == -1:
        print(f"  SKIP (anchor not found): {anchor!r}")
        return source
    end = idx + len(anchor)
    print(f"  ✓ Inserted after {anchor!r}")
    return source[:end] + insertion + source[end:]

def replace_text(source: str, old: str, new: str, label: str = "") -> str:
    if old not in source:
        print(f"  SKIP (not found): {label or old!r}")
        return source
    print(f"  ✓ Replaced: {label or old!r}")
    return source.replace(old, new, 1)

# ══════════════════════════════════════════════════════════════════════════
# 1.  Jarvis/OverlayWindow.swift
# ══════════════════════════════════════════════════════════════════════════

overlay_path = find_file("Jarvis/OverlayWindow.swift")
if not overlay_path:
    print("ERROR: Jarvis/OverlayWindow.swift not found. Run from project root.")
    sys.exit(1)

print(f"\nEditing: {overlay_path}")
src = overlay_path.read_text()

# ── A. Cursor structs ──────────────────────────────────────────────────────

GLYPH = """\
private struct JarvisCursorGlyphView: View {
    var isReturning: Bool = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let cycleProgress = cycleProgress(for: timeline.date, duration: 4.0)
            let glowPulse = 1.0 + 0.35 * CGFloat(cos(Double(cycleProgress) * .pi * 2))

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 11, height: 11)
                    .scaleEffect(glowPulse)
                    .blur(radius: 3.5)

                Circle()
                    .fill(Color.white.opacity(0.93))
                    .frame(width: 5, height: 5)
            }
        }
    }
}"""

LISTENING = """\
private struct JarvisListeningCursorView: View {
    let audioPowerLevel: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            let cycle = cycleProgress(for: timeline.date, duration: 1.2)
            let resonancePhase = cubicBezierProgress(
                cycle,
                c1x: 0.2,
                c1y: 0.0,
                c2x: 0.8,
                c2y: 1.0
            )
            let clampedAudio = max(0, min(audioPowerLevel, 1))
            let ringDiameter = 5 + resonancePhase * (22 + clampedAudio * 6)
            let ringOpacity = max(0, (0.75 + clampedAudio * 0.15) * (1 - resonancePhase))
            let strokeWidth = max(0.5, 1.3 - resonancePhase * 0.9)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(Double(ringOpacity)), lineWidth: strokeWidth)
                    .frame(width: ringDiameter, height: ringDiameter)

                Circle()
                    .fill(Color.white.opacity(0.93))
                    .frame(width: 5, height: 5)
            }
        }
    }
}"""

PROCESSING = """\
private struct JarvisProcessingCursorView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let cycle = cycleProgress(for: timeline.date, duration: 0.9)
            let railSize: CGFloat = 13
            let circumference = CGFloat.pi * railSize
            let dashOn = circumference * 0.3
            let dashOff = max(circumference - dashOn, 0.01)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
                    .frame(width: railSize, height: railSize)

                Circle()
                    .stroke(
                        Color.white.opacity(0.88),
                        style: StrokeStyle(
                            lineWidth: 0.9,
                            lineCap: .round,
                            dash: [dashOn, dashOff],
                            dashPhase: 0
                        )
                    )
                    .frame(width: railSize, height: railSize)
                    .rotationEffect(.degrees(Double(cycle) * 360))

                Circle()
                    .fill(Color.white.opacity(0.93))
                    .frame(width: 5, height: 5)
            }
        }
    }
}"""

src = replace_struct(src, "JarvisCursorGlyphView", GLYPH)
src = replace_struct(src, "JarvisListeningCursorView", LISTENING)
src = replace_struct(src, "JarvisProcessingCursorView", PROCESSING)

# Shrink idle cursor frame
for old_w in ["28", "24"]:
    old = f"JarvisCursorGlyphView(isReturning: isReturningToCursor)\n                .frame(width: {old_w}, height: {old_w})"
    new = "JarvisCursorGlyphView(isReturning: isReturningToCursor)\n                .frame(width: 20, height: 20)"
    if old in src:
        src = src.replace(old, new, 1)
        print(f"  ✓ Frame updated from {old_w} → 20")
        break

# ── B. HUD: add isHUDExpanded state ───────────────────────────────────────

if "isHUDExpanded" not in src:
    # Insert after the first @State private var line after the struct open
    anchor = "/// Speech bubble text shown when pointing at a detected element."
    insertion = "    @State private var isHUDExpanded: Bool = false\n\n    "
    src = replace_text(src, anchor, insertion + anchor, "add isHUDExpanded state")
else:
    print("  ✓ isHUDExpanded already present")

# ── C. HUD placement: remove allowsHitTesting, add expand animation ────────

src = replace_text(
    src,
    "                    .allowsHitTesting(false)\n",
    "                    .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isHUDExpanded)\n"
    "                    .onChange(of: jarvisManager.showCodexActivityOverlay) { visible in\n"
    "                        if !visible { isHUDExpanded = false }\n"
    "                    }\n",
    "remove allowsHitTesting / add expand animation"
)

# ── D. Replace codexActivityHUD computed property ─────────────────────────
# Detect the manager type name used in this file
manager_type = "jarvisManager" if "jarvisManager" in src else "orbitManager"

HUD_REPLACEMENT = f"""\
@ViewBuilder
    private var codexActivityHUD: some View {{
        VStack(alignment: .leading, spacing: 10) {{
            HStack(alignment: .center, spacing: 8) {{
                Group {{
                    switch {manager_type}.activeActionStatus {{
                    case .running, .waitingForApproval:
                        JarvisMiniSpinner(tint: actionStatusAccentColor)
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DS.Colors.success)
                    case .interrupted:
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(DS.Colors.warning)
                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(DS.Colors.warning)
                    case .idle:
                        JarvisMarkView(size: 13)
                    }}
                }}
                .frame(width: 14, height: 14)

                Text("Jarvis")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Spacer(minLength: 4)

                DSQuietStatusChip(title: actionStatusLabel, tint: actionStatusAccentColor)

                if {manager_type}.voiceState == .responding {{
                    Button {{
                        {manager_type}.stopSpeech()
                    }} label: {{
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(DS.Colors.textSecondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }}
                    .buttonStyle(.plain)
                }}

                Button {{
                    isHUDExpanded.toggle()
                }} label: {{
                    Image(systemName: isHUDExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Colors.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }}
                .buttonStyle(.plain)

                Button {{
                    {manager_type}.dismissActivityOverlay()
                }} label: {{
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Colors.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }}
                .buttonStyle(.plain)
            }}

            if isHUDExpanded {{
                ScrollView {{
                    Text({manager_type}.activeActionStatusSummary ?? {manager_type}.codexSessionSummary)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(DS.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }}
                .frame(maxHeight: 160)
            }} else {{
                Text({manager_type}.activeActionStatusSummary ?? {manager_type}.codexSessionSummary)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineLimit(2)
            }}

            if let detail = codexHUDDetailLine {{
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
                    .lineLimit(isHUDExpanded ? nil : 2)
            }}

            if !{manager_type}.recentActionUpdates.isEmpty {{
                VStack(alignment: .leading, spacing: 5) {{
                    ForEach(
                        Array({manager_type}.recentActionUpdates.suffix(isHUDExpanded ? 20 : 4).enumerated()),
                        id: \\.offset
                    ) {{ _, update in
                        HStack(alignment: .top, spacing: 6) {{
                            Circle()
                                .fill(Color.white.opacity(0.55))
                                .frame(width: 4, height: 4)
                                .padding(.top, 4)
                            Text(update)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(DS.Colors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }}
                    }}
                }}
            }}

            if !{manager_type}.codexConfigurationSummary.isEmpty {{
                Text({manager_type}.codexConfigurationSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                    .lineLimit(isHUDExpanded ? nil : 1)
            }}
        }}
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: isHUDExpanded ? 340 : 252, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.clear)
                .jarvisGlassCard(
                    shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
                    fillOpacity: 0.36,
                    borderOpacity: 0.15,
                    highlightOpacity: 0.22,
                    shadowOpacity: 0.18,
                    glowOpacity: 0.03
                )
        )
    }}"""

# Try to replace using the computed property signature
for sig in ["@ViewBuilder\n    private var codexActivityHUD", "@ViewBuilder\n    private var codexActivityHUD:"]:
    if sig in src:
        src = replace_computed_property(src, sig, HUD_REPLACEMENT)
        break
else:
    print("  SKIP: codexActivityHUD computed property not found — check signature")

overlay_path.write_text(src)
print(f"  → Saved {overlay_path}")

# ══════════════════════════════════════════════════════════════════════════
# 2.  JarvisManager.swift — add dismissActivityOverlay() and stopSpeech()
# ══════════════════════════════════════════════════════════════════════════

manager_path = find_file("Jarvis/JarvisManager.swift")
if not manager_path:
    # Try OrbitManager name inside Jarvis folder
    manager_path = find_file("Jarvis/OrbitManager.swift")

if not manager_path:
    print("\nWARNING: JarvisManager.swift not found — skipping manager patch.")
    print("  Add these two methods manually near interruptCurrentAction():\n")
    print("    func dismissActivityOverlay() { showCodexActivityOverlay = false }")
    print("    func stopSpeech() { textToSpeechProvider.stopPlayback(); fallbackTextToSpeechProvider.stopPlayback() }")
else:
    print(f"\nEditing: {manager_path}")
    msrc = manager_path.read_text()

    NEW_METHODS = """
    func dismissActivityOverlay() {
        showCodexActivityOverlay = false
    }

    func stopSpeech() {
        textToSpeechProvider.stopPlayback()
        fallbackTextToSpeechProvider.stopPlayback()
    }

    """

    if "dismissActivityOverlay" in msrc:
        print("  ✓ dismissActivityOverlay already present")
    else:
        # Insert after interruptCurrentAction closing brace
        anchor = "func answerToolPrompt"
        if anchor in msrc:
            msrc = msrc.replace(anchor, NEW_METHODS.lstrip() + anchor, 1)
            print("  ✓ Added dismissActivityOverlay() and stopSpeech()")
        else:
            print("  SKIP: could not find insertion anchor in manager file")

    manager_path.write_text(msrc)
    print(f"  → Saved {manager_path}")

print("\nDone. Rebuild in Xcode (⌘R).")
