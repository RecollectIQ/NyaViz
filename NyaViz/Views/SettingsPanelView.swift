//
//  SettingsPanelView.swift
//  NyaViz
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SettingsPanelView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    private var linesLabel: String {
        switch settings.lyricLinesVisible {
        case 1: return "1 + 1"
        case 2: return "2 + 2"
        default: return "3 + 3"
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    Button(action: { settings.showSettings = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Files Section
                        SettingsSection(title: "Files") {
                            VStack(spacing: 10) {
                                SettingsButton(
                                    icon: "music.note",
                                    title: "Open Audio",
                                    subtitle: audioPlayer.audioFileName.isEmpty ? "No file" : audioPlayer.audioFileName
                                ) {
                                    openAudioFile()
                                }
                                
                                SettingsButton(
                                    icon: "text.alignleft",
                                    title: "Open SRT",
                                    subtitle: audioPlayer.hasLyrics ? "\(audioPlayer.lyrics.count) lines" : "No file"
                                ) {
                                    openSRTFile()
                                }
                            }
                        }
                        
                        // Background Section
                        SettingsSection(title: "Background") {
                            VStack(spacing: 12) {
                                // Background image
                                SettingsButton(
                                    icon: "photo",
                                    title: "Background Image",
                                    subtitle: settings.backgroundImage != nil ? "Set" : "None"
                                ) {
                                    openBackgroundImage()
                                }
                                
                                // Blur
                                SettingsSlider(
                                    title: "Blur",
                                    value: $settings.backgroundBlur,
                                    range: 0...30
                                )
                                
                                // Opacity
                                SettingsSlider(
                                    title: "Opacity",
                                    value: $settings.backgroundOpacity,
                                    range: 0...1
                                )
                                
                                // Particles
                                SettingsToggle(title: "Snow Particles", isOn: $settings.showParticles)
                                
                                if settings.showParticles {
                                    SettingsSlider(
                                        title: "Particle Density",
                                        value: $settings.particleDensity,
                                        range: 0.2...2.0
                                    )
                                }
                            }
                        }
                        
                        // Player Section
                        SettingsSection(title: "Player") {
                            VStack(spacing: 12) {
                                SettingsToggle(title: "Vertical Layout", isOn: $settings.verticalLayout)
                                SettingsToggle(title: "Show Artwork", isOn: $settings.showArtwork)
                                
                                if settings.showArtwork {
                                    SettingsButton(
                                        icon: "square",
                                        title: "Set Artwork",
                                        subtitle: settings.artworkImage != nil ? "Custom" : "None"
                                    ) {
                                        openArtworkImage()
                                    }
                                }
                                
                                SettingsToggle(title: "Show Track Title", isOn: $settings.showTrackTitle)
                                SettingsToggle(title: "Loop Audio", isOn: $audioPlayer.isLooping)
                            }
                        }
                        
                        // Lyrics Section
                        SettingsSection(title: "Lyrics") {
                            VStack(spacing: 12) {
                                SettingsSlider(
                                    title: "Font Size",
                                    value: $settings.lyricFontSize,
                                    range: 28...72
                                )
                                
                                // Lines visible
                                VStack(spacing: 6) {
                                    HStack {
                                        Text("Visible Lines")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.7))
                                        
                                        Spacer()
                                        
                                        Text(linesLabel)
                                            .font(.system(size: 11))
                                            .foregroundColor(SettingsManager.accentDim)
                                    }
                                    
                                    Picker("", selection: $settings.lyricLinesVisible) {
                                        Text("Minimal").tag(1)
                                        Text("Normal").tag(2)
                                        Text("Max").tag(3)
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }
                        
                        // Visualizer Section
                        SettingsSection(title: "Visualizer") {
                            VStack(spacing: 12) {
                                SettingsToggle(title: "Show Visualizer", isOn: $settings.showVisualizer)
                                
                                if settings.showVisualizer {
                                    SettingsSlider(
                                        title: "Bar Width",
                                        value: $settings.visualizerBarWidth,
                                        range: 2...12
                                    )
                                    
                                    SettingsIntSlider(
                                        title: "Bar Count",
                                        value: $settings.visualizerBarCount,
                                        range: 8...120
                                    )
                                    
                                    SettingsSlider(
                                        title: "Bar Gap",
                                        value: $settings.visualizerBarGap,
                                        range: 1...10
                                    )
                                    
                                    SettingsSlider(
                                        title: "Opacity",
                                        value: $settings.visualizerBarOpacity,
                                        range: 0.1...1.0
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 260)
        }
    }
    
    private func openAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff, UTType(filenameExtension: "m4a")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an audio file"
        
        if panel.runModal() == .OK, let url = panel.url {
            audioPlayer.loadAudio(from: url)
        }
    }
    
    private func openSRTFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt")!, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an SRT file"
        
        if panel.runModal() == .OK, let url = panel.url {
            audioPlayer.loadSRT(from: url)
        }
    }
    
    private func openBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select background image"
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.loadBackgroundImage(from: url)
        }
    }
    
    private func openArtworkImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select artwork image"
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.loadArtworkImage(from: url)
        }
    }
}

// MARK: - Settings Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1)
            
            VStack(spacing: 12) {
                content
            }
        }
    }
}

struct SettingsButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .buttonStyle(.plain)
    }
}

struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
            
            Spacer()
            
            Button(action: { isOn.toggle() }) {
                Text(isOn ? "On" : "Off")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isOn ? .white.opacity(0.9) : .white.opacity(0.35))
                    .frame(width: 28, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
    }
}

struct SettingsSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    
    init(title: String, value: Binding<Double>, range: ClosedRange<Double>) {
        self.title = title
        self._value = value
        self.range = range
    }
    
    init(title: String, value: Binding<CGFloat>, range: ClosedRange<Double>) {
        self.title = title
        self._value = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = CGFloat($0) }
        )
        self.range = range
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                Text(String(format: "%.1f", value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            Slider(value: $value, in: range)
                .tint(.white.opacity(0.5))
        }
    }
}

struct SettingsIntSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                Text("\(value)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(.white.opacity(0.5))
        }
    }
}

// MARK: - Visual Effect Blur (NSVisualEffectView wrapper)

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    SettingsPanelView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(SettingsManager())
        .background(Color.black)
        .frame(height: 700)
}
