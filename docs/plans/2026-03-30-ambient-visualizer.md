# Ambient Breathing Visualizer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the bar visualizer with an ambient breathing system — background scale pulse, vignette pulse, and floating dust motes — all driven by bass energy.

**Architecture:** Add `bassEnergy` to AudioPlayerManager. Replace SnowfallView with DustMoteView. Add vignette + scale breathing to BackgroundView. Remove AudioVisualizerView and all bar-related code. Update VideoExporter to match.

**Tech Stack:** SwiftUI Canvas, TimelineView, scaleEffect, RadialGradient

---

### Task 1: Add bassEnergy to AudioPlayerManager

**Files:**
- Modify: `NyaViz/Managers/AudioPlayerManager.swift:63` (add property)
- Modify: `NyaViz/Managers/AudioPlayerManager.swift:626-633` (compute bass in FFT callback)
- Modify: `NyaViz/Managers/AudioPlayerManager.swift:414-417` (reset on pause)
- Modify: `NyaViz/Managers/AudioPlayerManager.swift:442-443` (reset on stop)

**Step 1: Add the published property**

After line 63 (`@Published var frequencyBands`), add:

```swift
@Published var bassEnergy: Float = 0
```

Also add a smoothed backing field near `smoothedBands`:

```swift
private var smoothedBassEnergy: Float = 0
```

**Step 2: Compute bassEnergy in the FFT callback**

In `processAudioBuffer`, after the smoothing loop (line ~624) and before the throttle check (line ~627), add bass energy computation:

```swift
// Compute bass energy from lowest 20 bands
let bassRange = 0..<min(20, bandCount)
let bassSum = bassRange.reduce(Float(0)) { $0 + self.smoothedBands[$1] }
let rawBass = bassSum / Float(bassRange.count)

// Smooth bass energy
if rawBass > self.smoothedBassEnergy {
    self.smoothedBassEnergy = self.smoothedBassEnergy + (rawBass - self.smoothedBassEnergy) * 0.6
} else {
    self.smoothedBassEnergy = self.smoothedBassEnergy + (rawBass - self.smoothedBassEnergy) * 0.15
}
```

Then inside the existing `Task { @MainActor }` block (line ~631), add:

```swift
self?.bassEnergy = self?.smoothedBassEnergy ?? 0
```

**Step 3: Reset on pause and stop**

In `pause()` (around line 414), add after the band reset:
```swift
smoothedBassEnergy = 0
bassEnergy = 0
```

In `stop()` (around line 442), add after the band reset:
```swift
smoothedBassEnergy = 0
bassEnergy = 0
```

**Step 4: Build and verify no errors**

Run: `xcodebuild build -project NyaViz.xcodeproj -scheme NyaViz -quiet 2>&1 | tail -5`

**Step 5: Commit**

```
feat: add bassEnergy property to AudioPlayerManager
```

---

### Task 2: Add visualizerIntensity setting, remove bar settings

**Files:**
- Modify: `NyaViz/Managers/SettingsManager.swift:14-35` (Keys enum)
- Modify: `NyaViz/Managers/SettingsManager.swift:104-119` (Published properties)
- Modify: `NyaViz/Managers/SettingsManager.swift:193-208` (loadSavedSettings)

**Step 1: Update Keys enum**

Remove these keys from the Keys enum:
```swift
static let visualizerBarWidth = "visualizerBarWidth"
static let visualizerBarCount = "visualizerBarCount"
static let visualizerBarGap = "visualizerBarGap"
static let visualizerBarOpacity = "visualizerBarOpacity"
```

Add:
```swift
static let visualizerIntensity = "visualizerIntensity"
```

**Step 2: Replace published properties**

Remove these properties (lines 108-119):
```swift
@Published var visualizerBarWidth: CGFloat = 4 { ... }
@Published var visualizerBarCount: Int = 48 { ... }
@Published var visualizerBarGap: CGFloat = 3 { ... }
@Published var visualizerBarOpacity: Double = 0.5 { ... }
```

Add:
```swift
@Published var visualizerIntensity: Double = 0.5 {
    didSet { defaults.set(visualizerIntensity, forKey: Keys.visualizerIntensity) }
}
```

**Step 3: Update loadSavedSettings**

Remove the bar-related loading (lines 197-208). Add:

```swift
if defaults.object(forKey: Keys.visualizerIntensity) != nil {
    visualizerIntensity = defaults.double(forKey: Keys.visualizerIntensity)
}
```

**Step 4: Build and verify**

Run: `xcodebuild build -project NyaViz.xcodeproj -scheme NyaViz -quiet 2>&1 | tail -20`

Expect build errors from files still referencing old properties — that's fine, we'll fix those next.

**Step 5: Commit**

```
refactor: replace bar settings with visualizerIntensity
```

---

### Task 3: Delete AudioVisualizerView, remove references from MainPlayerView and FullScreenLyricsView

**Files:**
- Delete: `NyaViz/Views/AudioVisualizerView.swift`
- Modify: `NyaViz/Views/MainPlayerView.swift:20-24` (vertical layout visualizer)
- Modify: `NyaViz/Views/MainPlayerView.swift:76-80` (horizontal layout visualizer)
- Modify: `NyaViz/Views/FullScreenLyricsView.swift:88-93` (fullscreen visualizer)

**Step 1: Delete the file**

```bash
rm NyaViz/Views/AudioVisualizerView.swift
```

Also remove it from the Xcode project if needed (it should auto-detect in a folder-based project).

**Step 2: Remove from MainPlayerView**

In the vertical layout ZStack (around line 20-24), remove:
```swift
// Audio Visualizer at the bottom (full width in vertical mode)
if settings.showVisualizer {
    AudioVisualizerView()
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
}
```

In the horizontal layout ZStack (around line 76-80), remove:
```swift
// Audio Visualizer centered in lyrics area
if settings.showVisualizer {
    AudioVisualizerView()
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
}
```

**Step 3: Remove from FullScreenLyricsView**

Remove (around line 88-93):
```swift
// Audio Visualizer at the bottom
if settings.showVisualizer {
    AudioVisualizerView()
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
}
```

**Step 4: Build and verify**

Run: `xcodebuild build -project NyaViz.xcodeproj -scheme NyaViz -quiet 2>&1 | tail -20`

**Step 5: Commit**

```
refactor: remove bar visualizer from all views
```

---

### Task 4: Replace SnowfallView with DustMoteView in BackgroundView

**Files:**
- Modify: `NyaViz/Views/BackgroundView.swift` (replace SnowfallView entirely)

**Step 1: Replace SnowfallView with DustMoteView**

Replace the entire `SnowfallView` struct (lines 73-141) with a new `DustMoteView`:

```swift
// MARK: - Floating Dust Mote Effect

struct DustMoteView: View {
    let density: Double
    let bassEnergy: Float
    let intensity: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            Canvas { context, size in
                drawParticles(context: context, size: size, date: timeline.date)
            }
        }
        .allowsHitTesting(false)
    }

    private func hash(_ n: Int) -> Double {
        var x = UInt64(abs(n) &+ 1)
        x = ((x >> 16) ^ x) &* 0x45d9f3b
        x = ((x >> 16) ^ x) &* 0x45d9f3b
        x = (x >> 16) ^ x
        return Double(x % 10000) / 10000.0
    }

    private func drawParticles(context: GraphicsContext, size: CGSize, date: Date) {
        let particleCount = Int(40 * density)
        let time = date.timeIntervalSinceReferenceDate
        let bass = Double(bassEnergy) * intensity

        for i in 0..<particleCount {
            let xRandom = hash(i * 7919)
            let yRandom = hash(i * 6271)
            let speedRandom = hash(i * 5147)
            let sizeRandom = hash(i * 4219)
            let opacityRandom = hash(i * 3571)
            let driftXRandom = hash(i * 2957)
            let driftYRandom = hash(i * 2381)

            // Base particle properties
            let baseSize = 1.0 + sizeRandom * 2.0
            let baseOpacity = 0.15 + opacityRandom * 0.2

            // Beat-reactive: slight size and opacity boost
            let particleSize = baseSize + bass * 0.5
            let opacity = baseOpacity + bass * 0.1

            // Slow ambient drift in random directions (not just down)
            let speed = 5 + speedRandom * 10
            let driftAngle = driftXRandom * .pi * 2  // Random direction
            let dx = cos(driftAngle) * speed
            let dy = sin(driftAngle) * speed

            // Position with gentle wandering
            let baseX = xRandom * size.width
            let baseY = yRandom * size.height

            let wanderX = sin(time * 0.2 + Double(i) * 1.7) * (20 + driftYRandom * 30)
            let wanderY = cos(time * 0.15 + Double(i) * 2.3) * (15 + driftXRandom * 25)

            let x = (baseX + dx * time.truncatingRemainder(dividingBy: 200) + wanderX)
                .truncatingRemainder(dividingBy: size.width + 20) - 10
            let y = (baseY + dy * time.truncatingRemainder(dividingBy: 200) + wanderY)
                .truncatingRemainder(dividingBy: size.height + 20) - 10

            let rect = CGRect(
                x: x - particleSize / 2,
                y: y - particleSize / 2,
                width: particleSize,
                height: particleSize
            )

            context.fill(
                Circle().path(in: rect),
                with: .color(.white.opacity(opacity))
            )
        }
    }
}
```

**Step 2: Update BackgroundView to use DustMoteView**

Replace the snowfall section (around line 51-53):
```swift
// Snowfall particles
if settings.showParticles {
    SnowfallView(density: settings.particleDensity)
}
```

With:
```swift
// Floating dust motes
if settings.showParticles {
    DustMoteView(
        density: settings.particleDensity,
        bassEnergy: audioPlayer.bassEnergy,
        intensity: settings.showVisualizer ? settings.visualizerIntensity : 0
    )
}
```

Also add `@EnvironmentObject var audioPlayer: AudioPlayerManager` to BackgroundView (it currently only has `settings`).

**Step 3: Build and verify**

Run: `xcodebuild build -project NyaViz.xcodeproj -scheme NyaViz -quiet 2>&1 | tail -20`

**Step 4: Commit**

```
feat: replace snowfall with floating dust motes
```

---

### Task 5: Add breathing effects to BackgroundView (scale pulse + vignette)

**Files:**
- Modify: `NyaViz/Views/BackgroundView.swift` (add scale + vignette to body)

**Step 1: Add bassEnergy state tracking**

Add a state property for smooth animation:
```swift
@State private var currentBassScale: CGFloat = 1.0
```

**Step 2: Add scale breathing to background images**

Wrap both background image views (previous + current) in a container and apply scaleEffect. The key change is adding `.scaleEffect(currentBassScale)` to each image view. The scale should be `1.0 + Double(audioPlayer.bassEnergy) * 0.02 * settings.visualizerIntensity`.

For both `prevImage` and `displayedImage` GeometryReader blocks, add after `.opacity(...)`:
```swift
.scaleEffect(settings.showVisualizer ? 1.0 + Double(audioPlayer.bassEnergy) * 0.02 * settings.visualizerIntensity : 1.0)
```

To prevent clipping at edges during scale, change both `.frame(width: geo.size.width, height: geo.size.height)` to use slightly larger dimensions:
```swift
.frame(width: geo.size.width * 1.05, height: geo.size.height * 1.05)
```

And center them by adding `.position(x: geo.size.width / 2, y: geo.size.height / 2)` before `.clipped()`.

**Step 3: Add vignette overlay**

After the dark overlay (`Color.black.opacity(0.3)`) and before the particles, add:

```swift
// Beat-reactive vignette
if settings.showVisualizer {
    let vignetteStrength = 0.6 + Double(audioPlayer.bassEnergy) * 0.1 * settings.visualizerIntensity
    RadialGradient(
        gradient: Gradient(colors: [
            Color.black.opacity(0),
            Color.black.opacity(vignetteStrength)
        ]),
        center: .center,
        startRadius: 100,
        endRadius: 600
    )
    .allowsHitTesting(false)
}
```

**Step 4: Build and verify**

Run: `xcodebuild build -project NyaViz.xcodeproj -scheme NyaViz -quiet 2>&1 | tail -20`

**Step 5: Commit**

```
feat: add background breathing and vignette pulse
```

---

### Task 6: Update SettingsPanelView

**Files:**
- Modify: `NyaViz/Views/SettingsPanelView.swift:202-232` (Visualizer section)

**Step 1: Replace visualizer settings section**

Replace the entire Visualizer section content (lines 202-232):

```swift
// Visualizer Section
SettingsSection(title: "Visualizer") {
    VStack(spacing: 12) {
        SettingsToggle(title: "Show Visualizer", isOn: $settings.showVisualizer)

        if settings.showVisualizer {
            SettingsSlider(
                title: "Intensity",
                value: $settings.visualizerIntensity,
                range: 0.0...1.0
            )
        }
    }
}
```

**Step 2: Update particles label**

Change the particle toggle label from "Snow Particles" to "Particles" (line 104):
```swift
SettingsToggle(title: "Particles", isOn: $settings.showParticles)
```

**Step 3: Build and verify**

Run: `xcodebuild build -project NyaViz.xcodeproj -scheme NyaViz -quiet 2>&1 | tail -20`

**Step 4: Commit**

```
feat: update settings panel for ambient visualizer
```

---

### Task 7: Update VideoExporter

**Files:**
- Modify: `NyaViz/Managers/VideoExporter.swift` (multiple locations)

**Step 1: Update CapturedSettings**

In `CapturedSettings` struct (around line 750-755), remove:
```swift
let visualizerBarWidth: CGFloat
let visualizerBarCount: Int
let visualizerBarGap: CGFloat
let visualizerBarOpacity: Double
```

Add:
```swift
let visualizerIntensity: Double
```

In the init (around lines 772-775), remove the bar property assignments and add:
```swift
self.visualizerIntensity = settings.visualizerIntensity
```

**Step 2: Add bassEnergy to SimulatedAudioPlayer**

In `SimulatedAudioPlayer` (around line 796), add:
```swift
@Published var bassEnergy: Float = 0
```

In `generateVisualizerData(time:)` (around line 835), add bass energy calculation after the frequency band generation:
```swift
// Compute bass energy from first 20 bands
let bassSum = frequencyBands.prefix(20).reduce(Float(0), +)
bassEnergy = bassSum / 20.0
```

**Step 3: Update ExportableSnowfallViewStatic to ExportableDustMoteViewStatic**

Replace `ExportableSnowfallViewStatic` (starting around line 1037) with a dust mote version that matches the new DustMoteView but takes time/size as params instead of TimelineView:

```swift
struct ExportableDustMoteViewStatic: View {
    let density: Double
    let bassEnergy: Float
    let intensity: Double
    let time: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            drawParticles(context: context, size: size)
        }
    }

    private func hash(_ n: Int) -> Double {
        var x = UInt64(abs(n) &+ 1)
        x = ((x >> 16) ^ x) &* 0x45d9f3b
        x = ((x >> 16) ^ x) &* 0x45d9f3b
        x = (x >> 16) ^ x
        return Double(x % 10000) / 10000.0
    }

    private func drawParticles(context: GraphicsContext, size: CGSize) {
        let particleCount = Int(40 * density)
        let bass = Double(bassEnergy) * intensity

        for i in 0..<particleCount {
            let xRandom = hash(i * 7919)
            let yRandom = hash(i * 6271)
            let speedRandom = hash(i * 5147)
            let sizeRandom = hash(i * 4219)
            let opacityRandom = hash(i * 3571)
            let driftXRandom = hash(i * 2957)
            let driftYRandom = hash(i * 2381)

            let baseSize = 1.0 + sizeRandom * 2.0
            let baseOpacity = 0.15 + opacityRandom * 0.2
            let particleSize = baseSize + bass * 0.5
            let opacity = baseOpacity + bass * 0.1

            let speed = 5 + speedRandom * 10
            let driftAngle = driftXRandom * .pi * 2
            let dx = cos(driftAngle) * speed
            let dy = sin(driftAngle) * speed

            let baseX = xRandom * size.width
            let baseY = yRandom * size.height

            let wanderX = sin(time * 0.2 + Double(i) * 1.7) * (20 + driftYRandom * 30)
            let wanderY = cos(time * 0.15 + Double(i) * 2.3) * (15 + driftXRandom * 25)

            let x = (baseX + dx * time.truncatingRemainder(dividingBy: 200) + wanderX)
                .truncatingRemainder(dividingBy: size.width + 20) - 10
            let y = (baseY + dy * time.truncatingRemainder(dividingBy: 200) + wanderY)
                .truncatingRemainder(dividingBy: size.height + 20) - 10

            let rect = CGRect(
                x: x - particleSize / 2,
                y: y - particleSize / 2,
                width: particleSize,
                height: particleSize
            )

            context.fill(
                Circle().path(in: rect),
                with: .color(.white.opacity(opacity))
            )
        }
    }
}
```

**Step 4: Update all snowfall references to dust mote**

Replace `ExportableSnowfallView` (around line 1480) with:

```swift
struct ExportableDustMoteView: View {
    let density: Double
    let bassEnergy: Float
    let intensity: Double
    let time: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            // Same drawing logic as ExportableDustMoteViewStatic
            drawParticles(context: context, size: size)
        }
    }

    // (same hash + drawParticles as ExportableDustMoteViewStatic)
}
```

Note: To avoid duplication, consider extracting the draw logic into a shared static function, or just keep both for simplicity since the export code is self-contained.

**Step 5: Update ExportableBackgroundView**

In `ExportableBackgroundView` (around line 1452), update the snowfall reference to dust motes and add vignette + scale. The background image should get scaleEffect, a vignette RadialGradient should be added, and the snowfall call should become:

```swift
if settings.showParticles {
    ExportableDustMoteView(
        density: settings.particleDensity,
        bassEnergy: simulatedPlayer.bassEnergy,
        intensity: settings.showVisualizer ? settings.visualizerIntensity : 0,
        time: time,
        size: size
    )
}
```

Add `let simulatedPlayer: SimulatedAudioPlayer` to the struct and pass it from callers.

Add scaleEffect to the background image:
```swift
.scaleEffect(settings.showVisualizer ? 1.0 + Double(simulatedPlayer.bassEnergy) * 0.02 * settings.visualizerIntensity : 1.0)
```

Add vignette after `Color.black.opacity(0.3)`:
```swift
if settings.showVisualizer {
    let vignetteStrength = 0.6 + Double(simulatedPlayer.bassEnergy) * 0.1 * settings.visualizerIntensity
    RadialGradient(
        gradient: Gradient(colors: [
            Color.black.opacity(0),
            Color.black.opacity(vignetteStrength)
        ]),
        center: .center,
        startRadius: 100,
        endRadius: 600
    )
}
```

**Step 6: Remove ExportableVisualizerView and ExportableVisualizerViewStatic**

Delete both structs entirely (around lines 1325-1363 and 1677-1722).

**Step 7: Remove visualizer references from render functions**

In the static render function (around line 1011-1023), remove:
```swift
if capturedSettings.showVisualizer {
    ExportableVisualizerViewStatic(...)
}
```

In ExportableFullScreenView (around line 1433-1438), remove:
```swift
if settings.showVisualizer {
    ExportableVisualizerView(...)
}
```

**Step 8: Update ExportOptionsSheet**

In `ExportOptionsSheet` (around line 518-529), update the visualizer toggle description:
```swift
Toggle(isOn: $videoExporter.exportOptions.includeVisualizer) {
    VStack(alignment: .leading, spacing: 2) {
        Text("Include Visualizer Effects")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
        Text("Beat-reactive breathing and vignette")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.5))
    }
}
```

Update the particles toggle description:
```swift
Toggle(isOn: $videoExporter.exportOptions.includeParticles) {
    VStack(alignment: .leading, spacing: 2) {
        Text("Include Particles")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
        Text("Floating dust motes")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.5))
    }
}
```

**Step 9: Build and verify**

Run: `xcodebuild build -project NyaViz.xcodeproj -scheme NyaViz -quiet 2>&1 | tail -20`

**Step 10: Commit**

```
feat: update video exporter for ambient visualizer
```

---

### Task 8: Final build and manual test

**Step 1: Clean build**

```bash
xcodebuild clean build -project NyaViz.xcodeproj -scheme NyaViz -quiet 2>&1 | tail -10
```

**Step 2: Verify no references to old code remain**

```bash
grep -r "AudioVisualizerView\|visualizerBar\|SnowfallView\|ExportableSnowfallView" NyaViz/ --include="*.swift"
```

Should return nothing.

**Step 3: Commit any remaining fixes**

```
chore: clean up remaining old visualizer references
```
