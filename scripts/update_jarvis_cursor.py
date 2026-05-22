#!/usr/bin/env python3
"""Replaces the three Jarvis cursor views with a minimal glowing dot design."""

import sys
from pathlib import Path

# Locate the file from cwd or script location
candidates = [
    Path.cwd() / "Jarvis" / "OverlayWindow.swift",
    Path(__file__).parent.parent / "Jarvis" / "OverlayWindow.swift",
]
target = next((p for p in candidates if p.exists()), None)

if not target:
    print("ERROR: Jarvis/OverlayWindow.swift not found. Run from the project root.")
    sys.exit(1)

print(f"Editing: {target}")
src = target.read_text()

# ── Diagnostic ─────────────────────────────────────────────────────────────
structs = [
    "JarvisCursorGlyphView",
    "JarvisListeningCursorView",
    "JarvisProcessingCursorView",
]
for name in structs:
    key = f"struct {name}"
    print(f"  {'✓' if key in src else '✗'} {key}")

# ── Struct replacement ──────────────────────────────────────────────────────
def replace_struct(source: str, name: str, replacement: str) -> str:
    key = f"struct {name}"
    idx = source.find(key)
    if idx == -1:
        print(f"  SKIP: could not find {key}")
        return source
    # Walk back to find 'private ' prefix if present
    prefix_start = max(0, idx - 8)
    if source[prefix_start:idx].strip() == "private":
        idx = prefix_start + source[prefix_start:].index("private")
    # Find the opening brace
    brace_idx = source.index("{", idx)
    depth = 0
    i = brace_idx
    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                print(f"  ✓ Replaced {name}")
                return source[:idx] + replacement + source[i + 1:]
        i += 1
    print(f"  SKIP: unmatched braces in {name}")
    return source


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

# Shrink idle cursor frame (try both 28 and any existing value)
for old_w in ["28", "24", "20"]:
    old = f"JarvisCursorGlyphView(isReturning: isReturningToCursor)\n                .frame(width: {old_w}, height: {old_w})"
    new = "JarvisCursorGlyphView(isReturning: isReturningToCursor)\n                .frame(width: 20, height: 20)"
    if old in src:
        src = src.replace(old, new)
        print(f"  ✓ Frame updated from {old_w} → 20")
        break

target.write_text(src)
print(f"\nDone — {target} updated. Rebuild in Xcode now.")
