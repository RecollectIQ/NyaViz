//
//  BackgroundView.swift
//  NyaViz
//

import SwiftUI

struct BackgroundView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var audioPlayer: AudioPlayerManager

    // Track the previous image for crossfade
    @State private var displayedImage: NSImage?
    @State private var previousImage: NSImage?
    @State private var crossfadeOpacity: Double = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            let liveDriftPhase = AmbientVisualizerTuning.backgroundDriftPhase(
                time: timeline.date.timeIntervalSinceReferenceDate
            )

            ZStack {
                // Base dark background
                SettingsManager.background

                // Previous image (fading out during crossfade)
                if let prevImage = previousImage {
                    BackgroundImageLayer(
                        image: prevImage,
                        opacity: settings.backgroundOpacity * (1.0 - crossfadeOpacity),
                        blur: settings.backgroundBlur,
                        driftPhase: liveDriftPhase
                    )
                }

                // Current background image (fading in)
                if let image = displayedImage {
                    BackgroundImageLayer(
                        image: image,
                        opacity: settings.backgroundOpacity * crossfadeOpacity,
                        blur: settings.backgroundBlur,
                        driftPhase: liveDriftPhase
                    )
                }

                // Dark overlay for better text contrast
                Color.black.opacity(0.3)

                // Floating dust motes
                if settings.showParticles {
                    DustMoteView(
                        density: settings.particleDensity,
                        bassEnergy: audioPlayer.bassEnergy,
                        intensity: settings.showVisualizer ? settings.visualizerIntensity : 0
                    )
                }
            }
            .ignoresSafeArea()
            .onChange(of: settings.backgroundImage) { _, newValue in
                guard newValue !== displayedImage else { return }
                previousImage = displayedImage
                displayedImage = newValue
                crossfadeOpacity = 0
                withAnimation(.easeInOut(duration: 0.8)) {
                    crossfadeOpacity = 1.0
                }
            }
            .onAppear {
                displayedImage = settings.backgroundImage
            }
        }
    }
}

private struct BackgroundImageLayer: View {
    let image: NSImage
    let opacity: Double
    let blur: Double
    let driftPhase: Double

    var body: some View {
        GeometryReader { geo in
            let drift = AmbientVisualizerTuning.backgroundDrift(
                size: geo.size,
                phase: driftPhase
            )

            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: geo.size.width * AmbientVisualizerTuning.backgroundFrameExpansion,
                        height: geo.size.height * AmbientVisualizerTuning.backgroundFrameExpansion
                    )
                    .offset(drift)
                    .blur(radius: blur)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .opacity(opacity)
        }
    }
}

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
        let particleCount = AmbientVisualizerTuning.particleCount(density: density)
        let time = date.timeIntervalSinceReferenceDate

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
            let particleSize = AmbientVisualizerTuning.particleSize(
                baseSize: baseSize,
                bassEnergy: bassEnergy,
                intensity: intensity
            )
            let opacity = AmbientVisualizerTuning.particleOpacity(
                baseOpacity: baseOpacity,
                bassEnergy: bassEnergy,
                intensity: intensity
            )

            // Slow ambient drift in random directions
            let speed = 5 + speedRandom * 10
            let driftAngle = driftXRandom * .pi * 2
            let dx = cos(driftAngle) * speed
            let dy = sin(driftAngle) * speed
            let beatOffset = AmbientVisualizerTuning.particleBeatOffset(
                bassEnergy: bassEnergy,
                intensity: intensity,
                direction: driftAngle + driftYRandom * 1.2,
                variance: sizeRandom
            )

            // Position with gentle wandering
            let baseX = xRandom * size.width
            let baseY = yRandom * size.height

            let wanderX = sin(time * 0.2 + Double(i) * 1.7) * (20 + driftYRandom * 30)
            let wanderY = cos(time * 0.15 + Double(i) * 2.3) * (15 + driftXRandom * 25)

            let x = (baseX + dx * time.truncatingRemainder(dividingBy: 200) + wanderX)
                .truncatingRemainder(dividingBy: size.width + 20) - 10
            let y = (baseY + dy * time.truncatingRemainder(dividingBy: 200) + wanderY)
                .truncatingRemainder(dividingBy: size.height + 20) - 10
            let pulsedX = x + beatOffset.width
            let pulsedY = y + beatOffset.height

            let rect = CGRect(
                x: pulsedX - particleSize / 2,
                y: pulsedY - particleSize / 2,
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

#Preview {
    BackgroundView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(SettingsManager())
}
