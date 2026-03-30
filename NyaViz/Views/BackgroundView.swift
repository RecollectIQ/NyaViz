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
        ZStack {
            // Base dark background
            SettingsManager.background

            // Previous image (fading out during crossfade)
            if let prevImage = previousImage {
                GeometryReader { geo in
                    let drift = AmbientVisualizerTuning.backgroundDrift(
                        size: geo.size,
                        time: audioPlayer.currentTime
                    )
                    Image(nsImage: prevImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: geo.size.width * AmbientVisualizerTuning.backgroundFrameExpansion,
                            height: geo.size.height * AmbientVisualizerTuning.backgroundFrameExpansion
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .offset(drift)
                        .clipped()
                        .blur(radius: settings.backgroundBlur)
                        .opacity(settings.backgroundOpacity * (1.0 - crossfadeOpacity))
                        .scaleEffect(
                            settings.showVisualizer
                            ? AmbientVisualizerTuning.backgroundScale(
                                bassEnergy: audioPlayer.bassEnergy,
                                intensity: settings.visualizerIntensity
                            )
                            : 1.0
                        )
                }
            }

            // Current background image (fading in)
            if let image = displayedImage {
                GeometryReader { geo in
                    let drift = AmbientVisualizerTuning.backgroundDrift(
                        size: geo.size,
                        time: audioPlayer.currentTime
                    )
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: geo.size.width * AmbientVisualizerTuning.backgroundFrameExpansion,
                            height: geo.size.height * AmbientVisualizerTuning.backgroundFrameExpansion
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .offset(drift)
                        .clipped()
                        .blur(radius: settings.backgroundBlur)
                        .opacity(settings.backgroundOpacity * crossfadeOpacity)
                        .scaleEffect(
                            settings.showVisualizer
                            ? AmbientVisualizerTuning.backgroundScale(
                                bassEnergy: audioPlayer.bassEnergy,
                                intensity: settings.visualizerIntensity
                            )
                            : 1.0
                        )
                }
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

#Preview {
    BackgroundView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(SettingsManager())
}
