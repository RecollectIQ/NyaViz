//
//  SettingsManager.swift
//  NyaViz
//

import SwiftUI
import Combine

@MainActor
class SettingsManager: ObservableObject {
    // Background
    @Published var backgroundImage: NSImage?
    @Published var backgroundOpacity: Double = 1.0
    @Published var backgroundBlur: Double = 0
    
    // Artwork
    @Published var artworkImage: NSImage?
    @Published var showArtwork: Bool = true
    @Published var showTrackTitle: Bool = true
    
    // Particles
    @Published var showParticles: Bool = true
    @Published var particleDensity: Double = 1.0
    
    // UI State
    @Published var isFullScreen: Bool = false
    @Published var showSettings: Bool = false
    
    // Lyrics
    @Published var lyricFontSize: CGFloat = 48
    @Published var lyricLinesVisible: Int = 2  // 1 = minimal (1+1), 2 = normal (2+2), 3 = max (3+3)
    
    // Static colors
    static let accent = Color(hex: "e5e5e5")
    static let accentDim = Color(hex: "737373")
    static let background = Color(hex: "0a0a0a")
    static let surface = Color(hex: "1a1a1a")
    static let surfaceLight = Color(hex: "262626")
    
    func loadBackgroundImage(from url: URL) {
        if let image = NSImage(contentsOf: url) {
            backgroundImage = image
        }
    }
    
    func loadArtworkImage(from url: URL) {
        if let image = NSImage(contentsOf: url) {
            artworkImage = image
        }
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
