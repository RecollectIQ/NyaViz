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
    
    private func drawParticles(context: GraphicsContext, size: CGSize, date: Date) {
        let particleCount = Int(50 * density)
        let time = date.timeIntervalSinceReferenceDate
        
        for i in 0..<particleCount {
            let seed = Double(i) * 1.618033988749
            
            // Deterministic but varied properties based on seed
            let speed = 0.3 + (seed.truncatingRemainder(dividingBy: 1.0)) * 0.7
            let drift = sin(seed * 10) * 0.5
            let particleSize = 1.5 + (seed * 2.5).truncatingRemainder(dividingBy: 3)
            let opacity = 0.15 + (seed * 0.4).truncatingRemainder(dividingBy: 0.35)
            
            // Calculate position
            let baseY = (time * speed * 30 + seed * size.height).truncatingRemainder(dividingBy: size.height + 40) - 20
            let baseX = (seed * size.width).truncatingRemainder(dividingBy: size.width)
            let xOffset = sin(time * 0.5 + seed * 10) * 20 * drift
            
            let x = (baseX + xOffset).truncatingRemainder(dividingBy: size.width)
            let y = baseY
            
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
