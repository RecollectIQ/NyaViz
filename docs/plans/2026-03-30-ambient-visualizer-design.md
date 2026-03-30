# Ambient Breathing Visualizer

**Date:** 2026-03-30
**Replaces:** Bar visualizer (AudioVisualizerView.swift)

## Goal

Replace the explicit bar visualizer with an ambient, barely-there breathing system that complements the artwork and lyrics without stealing focus. Minimal brutalist aesthetic — felt more than seen.

## Approach

Pure SwiftUI (Approach A). No Metal. Canvas + scaleEffect + gradient overlays.

## Audio Signal

Add `bassEnergy` (Float, 0-1) to `AudioPlayerManager` — average of lowest ~20 frequency bands, smoothed with same fast-attack/slow-release as existing bands. This single value drives all three effects.

## Three Breathing Effects

### A) Background Image Breathing
- `scaleEffect(1.0 + bassEnergy * 0.02 * intensity)` on the background image
- At silence: 1.0. At max bass with full intensity: 1.02
- Smooth spring animation to avoid jerky transitions
- Image rendered slightly oversized to hide edge clipping during scale

### B) Vignette Pulse
- RadialGradient overlay: transparent center fading to dark edges
- At rest: vignette darkness reaches ~60% inward from edges
- On bass: reaches ~65-70% inward (tightens)
- Driven by `bassEnergy * intensity` controlling gradient start/end radius ratios
- Subtle "tunnel vision" pulse

### C) Floating Dust Motes
- ~40 particles drifting in random directions (not just downward)
- Size: 1-3pt circles, opacity 0.15-0.35
- Beat-reactive: bass causes slight size pulse (+0.5pt) and opacity boost (+0.1)
- Slow ambient drift — dust in a projector beam feel
- Canvas + TimelineView, same pattern as current snowfall

## Removals

- Delete `AudioVisualizerView.swift`
- Remove all references in MainPlayerView, FullScreenLyricsView, etc.
- Remove bar settings: `visualizerBarWidth`, `visualizerBarCount`, `visualizerBarGap`, `visualizerBarOpacity`
- Remove bar settings UI from SettingsPanelView

## Settings

- Keep `showVisualizer` as master toggle for all effects
- Add `visualizerIntensity` (0.0-1.0, default 0.5) — scales all three effects
- Reuse existing `particleDensity` for dust mote count

## Gating

All three effects gated behind `showVisualizer` toggle.
