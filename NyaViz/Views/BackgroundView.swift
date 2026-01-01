//
//  BackgroundView.swift
//  NyaViz
//

import SwiftUI

struct BackgroundView: View {
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        ZStack {
            // Base dark background
            SettingsManager.background
            
            // Background image
            if let image = settings.backgroundImage {
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: settings.backgroundBlur)
                        .opacity(settings.backgroundOpacity)
                }
            }
            
            // Dark overlay for better text contrast
            Color.black.opacity(0.3)
            
            // Snowfall particles
            if settings.showParticles {
                SnowfallView(density: settings.particleDensity)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Snowfall Particle Effect

struct SnowfallView: View {
    let density: Double
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            Canvas { context, size in
                drawParticles(context: context, size: size, date: timeline.date)
            }
        }
        .allowsHitTesting(false)
    }
    
    // Simple hash function for deterministic randomness
    private func hash(_ n: Int) -> Double {
        var x = UInt64(abs(n) &+ 1)
        x = ((x >> 16) ^ x) &* 0x45d9f3b
        x = ((x >> 16) ^ x) &* 0x45d9f3b
        x = (x >> 16) ^ x
        return Double(x % 10000) / 10000.0
    }
    
    private func drawParticles(context: GraphicsContext, size: CGSize, date: Date) {
        let particleCount = Int(60 * density)
        let time = date.timeIntervalSinceReferenceDate
        
        for i in 0..<particleCount {
            // Use hash for truly scattered distribution
            let xRandom = hash(i * 7919)  // Prime multipliers for variety
            let yRandom = hash(i * 6271)
            let speedRandom = hash(i * 5147)
            let sizeRandom = hash(i * 4219)
            let opacityRandom = hash(i * 3571)
            let driftRandom = hash(i * 2957)
            
            // Particle properties
            let speed = 15 + speedRandom * 25
            let particleSize = 1.0 + sizeRandom * 2.5
            let opacity = 0.1 + opacityRandom * 0.3
            let driftAmount = (driftRandom - 0.5) * 40
            
            // Position - scattered across full width
            let baseX = xRandom * size.width
            let startY = yRandom * size.height
            
            // Falling animation with wrap-around
            let fallDistance = time * speed
            let y = (startY + fallDistance).truncatingRemainder(dividingBy: size.height + 50) - 25
            
            // Gentle horizontal drift
            let xDrift = sin(time * 0.3 + Double(i)) * driftAmount
            let x = baseX + xDrift
            
            // Skip if off-screen
            guard x >= -10 && x <= size.width + 10 else { continue }
            
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
        .environmentObject(SettingsManager())
}
