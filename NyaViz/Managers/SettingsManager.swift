//
//  SettingsManager.swift
//  NyaViz
//

import SwiftUI
import Combine

@MainActor
class SettingsManager: ObservableObject {
    private let defaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private enum Keys {
        static let backgroundOpacity = "backgroundOpacity"
        static let backgroundBlur = "backgroundBlur"
        static let showArtwork = "showArtwork"
        static let showTrackTitle = "showTrackTitle"
        static let showParticles = "showParticles"
        static let particleDensity = "particleDensity"
        static let lyricFontSize = "lyricFontSize"
        static let lyricLinesVisible = "lyricLinesVisible"
        static let dialogCharacterName = "dialogCharacterName"
        static let dialogMaxWidth = "dialogMaxWidth"
        static let dialogMaxHeight = "dialogMaxHeight"
        static let dialogPosition = "dialogPosition"
        // Visualizer
        static let showVisualizer = "showVisualizer"
        static let visualizerBarWidth = "visualizerBarWidth"
        static let visualizerBarCount = "visualizerBarCount"
        static let visualizerBarGap = "visualizerBarGap"
        static let visualizerBarOpacity = "visualizerBarOpacity"
    }
    
    // File names for cached images
    private let backgroundImageFileName = "background_image.png"
    private let artworkImageFileName = "artwork_image.png"
    
    // Background
    @Published var backgroundImage: NSImage?
    @Published var backgroundOpacity: Double = 1.0 {
        didSet { defaults.set(backgroundOpacity, forKey: Keys.backgroundOpacity) }
    }
    @Published var backgroundBlur: Double = 0 {
        didSet { defaults.set(backgroundBlur, forKey: Keys.backgroundBlur) }
    }
    
    // Artwork
    @Published var artworkImage: NSImage?
    @Published var showArtwork: Bool = true {
        didSet { defaults.set(showArtwork, forKey: Keys.showArtwork) }
    }
    @Published var showTrackTitle: Bool = true {
        didSet { defaults.set(showTrackTitle, forKey: Keys.showTrackTitle) }
    }
    
    // Particles
    @Published var showParticles: Bool = true {
        didSet { defaults.set(showParticles, forKey: Keys.showParticles) }
    }
    @Published var particleDensity: Double = 1.0 {
        didSet { defaults.set(particleDensity, forKey: Keys.particleDensity) }
    }
    
    // UI State (not persisted)
    @Published var isFullScreen: Bool = false
    @Published var showSettings: Bool = false
    
    // Layout
    @Published var verticalLayout: Bool = false {
        didSet { defaults.set(verticalLayout, forKey: "verticalLayout") }
    }
    
    // Lyrics
    @Published var lyricFontSize: CGFloat = 48 {
        didSet { defaults.set(Double(lyricFontSize), forKey: Keys.lyricFontSize) }
    }
    @Published var lyricLinesVisible: Int = 2 {
        didSet { defaults.set(lyricLinesVisible, forKey: Keys.lyricLinesVisible) }
    }
    
    // Dialog Mode (game-style conversation overlay)
    @Published var dialogCharacterName: String = "CHARACTER" {
        didSet { defaults.set(dialogCharacterName, forKey: Keys.dialogCharacterName) }
    }
    @Published var dialogMaxWidth: Double = 0.84 {
        didSet { defaults.set(dialogMaxWidth, forKey: Keys.dialogMaxWidth) }
    }
    @Published var dialogMaxHeight: Double = 0.25 {
        didSet { defaults.set(dialogMaxHeight, forKey: Keys.dialogMaxHeight) }
    }
    @Published var dialogPosition: Double = 0.75 {
        didSet { defaults.set(dialogPosition, forKey: Keys.dialogPosition) }
    }
    @Published var showDialogSettings: Bool = false
    
    // Visualizer
    @Published var showVisualizer: Bool = true {
        didSet { defaults.set(showVisualizer, forKey: Keys.showVisualizer) }
    }
    @Published var visualizerBarWidth: CGFloat = 4 {
        didSet { defaults.set(Double(visualizerBarWidth), forKey: Keys.visualizerBarWidth) }
    }
    @Published var visualizerBarCount: Int = 48 {
        didSet { defaults.set(visualizerBarCount, forKey: Keys.visualizerBarCount) }
    }
    @Published var visualizerBarGap: CGFloat = 3 {
        didSet { defaults.set(Double(visualizerBarGap), forKey: Keys.visualizerBarGap) }
    }
    @Published var visualizerBarOpacity: Double = 0.5 {
        didSet { defaults.set(visualizerBarOpacity, forKey: Keys.visualizerBarOpacity) }
    }
    
    // Static colors
    static let accent = Color(hex: "e5e5e5")
    static let accentDim = Color(hex: "737373")
    static let background = Color(hex: "0a0a0a")
    static let surface = Color(hex: "1a1a1a")
    static let surfaceLight = Color(hex: "262626")
    
    // App support directory for storing images
    private var appSupportDirectory: URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appDirectory = appSupport.appendingPathComponent("NyaViz", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }
        
        return appDirectory
    }
    
    init() {
        loadSavedSettings()
    }
    
    private func loadSavedSettings() {
        // Load values from UserDefaults with defaults
        if defaults.object(forKey: Keys.backgroundOpacity) != nil {
            backgroundOpacity = defaults.double(forKey: Keys.backgroundOpacity)
        }
        if defaults.object(forKey: Keys.backgroundBlur) != nil {
            backgroundBlur = defaults.double(forKey: Keys.backgroundBlur)
        }
        if defaults.object(forKey: Keys.showArtwork) != nil {
            showArtwork = defaults.bool(forKey: Keys.showArtwork)
        }
        if defaults.object(forKey: Keys.showTrackTitle) != nil {
            showTrackTitle = defaults.bool(forKey: Keys.showTrackTitle)
        }
        if defaults.object(forKey: Keys.showParticles) != nil {
            showParticles = defaults.bool(forKey: Keys.showParticles)
        }
        if defaults.object(forKey: Keys.particleDensity) != nil {
            particleDensity = defaults.double(forKey: Keys.particleDensity)
        }
        if defaults.object(forKey: Keys.lyricFontSize) != nil {
            lyricFontSize = CGFloat(defaults.double(forKey: Keys.lyricFontSize))
        }
        if defaults.object(forKey: Keys.lyricLinesVisible) != nil {
            lyricLinesVisible = defaults.integer(forKey: Keys.lyricLinesVisible)
        }
        if let savedName = defaults.string(forKey: Keys.dialogCharacterName) {
            dialogCharacterName = savedName
        }
        if defaults.object(forKey: Keys.dialogMaxWidth) != nil {
            dialogMaxWidth = defaults.double(forKey: Keys.dialogMaxWidth)
        }
        if defaults.object(forKey: Keys.dialogMaxHeight) != nil {
            dialogMaxHeight = defaults.double(forKey: Keys.dialogMaxHeight)
        }
        if defaults.object(forKey: Keys.dialogPosition) != nil {
            dialogPosition = defaults.double(forKey: Keys.dialogPosition)
        }
        if defaults.object(forKey: "verticalLayout") != nil {
            verticalLayout = defaults.bool(forKey: "verticalLayout")
        }
        
        // Visualizer settings
        if defaults.object(forKey: Keys.showVisualizer) != nil {
            showVisualizer = defaults.bool(forKey: Keys.showVisualizer)
        }
        if defaults.object(forKey: Keys.visualizerBarWidth) != nil {
            visualizerBarWidth = CGFloat(defaults.double(forKey: Keys.visualizerBarWidth))
        }
        if defaults.object(forKey: Keys.visualizerBarCount) != nil {
            visualizerBarCount = defaults.integer(forKey: Keys.visualizerBarCount)
        }
        if defaults.object(forKey: Keys.visualizerBarGap) != nil {
            visualizerBarGap = CGFloat(defaults.double(forKey: Keys.visualizerBarGap))
        }
        if defaults.object(forKey: Keys.visualizerBarOpacity) != nil {
            visualizerBarOpacity = defaults.double(forKey: Keys.visualizerBarOpacity)
        }
        
        // Load cached images from app support directory
        loadCachedImages()
    }
    
    private func loadCachedImages() {
        guard let appSupport = appSupportDirectory else { return }
        
        // Load background image
        let backgroundURL = appSupport.appendingPathComponent(backgroundImageFileName)
        if let image = NSImage(contentsOf: backgroundURL) {
            backgroundImage = image
        }
        
        // Load artwork image
        let artworkURL = appSupport.appendingPathComponent(artworkImageFileName)
        if let image = NSImage(contentsOf: artworkURL) {
            artworkImage = image
        }
    }
    
    private func saveImageToCache(_ image: NSImage, fileName: String) {
        guard let appSupport = appSupportDirectory else { return }
        
        let fileURL = appSupport.appendingPathComponent(fileName)
        
        // Convert NSImage to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return
        }
        
        // Write to file
        do {
            try pngData.write(to: fileURL)
        } catch {
            print("Error saving image: \(error)")
        }
    }
    
    private func deleteImageFromCache(_ fileName: String) {
        guard let appSupport = appSupportDirectory else { return }
        
        let fileURL = appSupport.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func loadBackgroundImage(from url: URL) {
        if let image = NSImage(contentsOf: url) {
            backgroundImage = image
            saveImageToCache(image, fileName: backgroundImageFileName)
        }
    }
    
    func loadArtworkImage(from url: URL) {
        if let image = NSImage(contentsOf: url) {
            artworkImage = image
            saveImageToCache(image, fileName: artworkImageFileName)
        }
    }
    
    func clearBackgroundImage() {
        backgroundImage = nil
        deleteImageFromCache(backgroundImageFileName)
    }
    
    func clearArtworkImage() {
        artworkImage = nil
        deleteImageFromCache(artworkImageFileName)
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
