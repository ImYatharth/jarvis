#!/usr/bin/env python3
"""Replaces the three Jarvis cursor views with a minimal glowing dot design."""

import re
import sys
from pathlib import Path

TARGET = Path(__file__).parent.parent / "Jarvis" / "OverlayWindow.swift"

if not TARGET.exists():
    print(f"Error: {TARGET} not found")
    sys.exit(1)

src = TARGET.read_text()

GLYPH = '''\
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
}'''

LISTENING = '''\
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
}'''

PROCESSING = '''\
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
}'''

def replace_struct(source: str, struct_name: str, replacement: str) -> str:
    # Match from `private struct <Name>` to its closing `}` at the same indent level
    pattern = rf'(private struct {re.escape(struct_name)}: View \{{)'
    match = re.search(pattern, source)
    if not match:
        print(f"Warning: could not find {struct_name}")
        return source

    start = match.start()
    depth = 0
    i = start
    while i < len(source):
        if source[i] == '{':
            depth += 1
        elif source[i] == '}':
            depth -= 1
            if depth == 0:
                end = i + 1
                return source[:start] + replacement + source[end:]
        i += 1

    print(f"Warning: could not find closing brace for {struct_name}")
    return source

src = replace_struct(src, "JarvisCursorGlyphView", GLYPH)
src = replace_struct(src, "JarvisListeningCursorView", LISTENING)
src = replace_struct(src, "JarvisProcessingCursorView", PROCESSING)

# Shrink the idle cursor frame from 28 to 20
src = src.replace(
    "JarvisCursorGlyphView(isReturning: isReturningToCursor)\n                .frame(width: 28, height: 28)",
    "JarvisCursorGlyphView(isReturning: isReturningToCursor)\n                .frame(width: 20, height: 20)",
)

TARGET.write_text(src)
print(f"Done — updated {TARGET}")
