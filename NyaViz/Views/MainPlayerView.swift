//
//  MainPlayerView.swift
//  NyaViz
//

import SwiftUI

struct MainPlayerView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        GeometryReader { geo in
            if settings.verticalLayout {
                // Vertical Layout - Title top, lyrics center, controls bottom on hover
                ZStack(alignment: .bottom) {
                    VerticalModeView()
                    
                    // Audio Visualizer at the bottom (full width in vertical mode)
                    if settings.showVisualizer {
                        AudioVisualizerView()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    }
                }
            } else {
                // Horizontal Layout - Original
                HStack(spacing: 0) {
                    // Left Panel - Now Playing Info
                    VStack(spacing: 20) {
                        Spacer()
                        
                        // Square Artwork (hideable)
                        if settings.showArtwork {
                            ArtworkView()
                        }
                        
                        // Track Title (hideable)
                        if settings.showTrackTitle && !audioPlayer.audioFileName.isEmpty {
                            Text(audioPlayer.audioFileName)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .padding(.top, 4)
                        }
                        
                        // Progress Bar
                        ProgressBarView()
                            .padding(.horizontal, 32)
                            .padding(.top, settings.showTrackTitle ? 8 : 16)
                        
                        // Playback Controls
                        PlaybackControlsView()
                            .padding(.top, 8)
                        
                        // Additional Controls
                        AdditionalControlsView()
                            .padding(.top, 8)
                        
                        Spacer()
                    }
                    .frame(width: min(340, geo.size.width * 0.35))
                    .padding(.horizontal, 24)
                    
                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                    
                    // Right Panel - Lyrics with Visualizer
                    ZStack(alignment: .bottom) {
                        LyricsView()
                            .frame(maxWidth: .infinity)
                        
                        // Audio Visualizer centered in lyrics area
                        if settings.showVisualizer {
                            AudioVisualizerView()
                                .padding(.horizontal, 24)
                                .padding(.bottom, 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Vertical Mode View

struct VerticalModeView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    @State private var showControls = false
    @State private var controlsTimer: Timer?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 0) {
                    // Top - Title and Progress (narrower, centered)
                    VStack(spacing: 10) {
                        // Track Title (centered)
                        if settings.showTrackTitle && !audioPlayer.audioFileName.isEmpty {
                            Text(audioPlayer.audioFileName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        
                        // Progress bar with time (narrower)
                        HStack(spacing: 10) {
                            Text(formatTime(audioPlayer.currentTime))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(height: 2)
                                    
                                    Capsule()
                                        .fill(Color.white.opacity(0.6))
                                        .frame(width: max(0, geometry.size.width * audioPlayer.progress), height: 2)
                                }
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onEnded { value in
                                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                                            audioPlayer.seek(to: progress * audioPlayer.duration)
                                        }
                                )
                            }
                            .frame(height: 2)
                            
                            Text(formatTime(audioPlayer.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .frame(maxWidth: min(500, geo.size.width * 0.5))
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                    
                    // Divider (narrower)
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: min(600, geo.size.width * 0.6), height: 1)
                    
                    // Spacer to push lyrics down slightly
                    Spacer()
                        .frame(height: geo.size.height * 0.015)
                    
                    // Lyrics area (current + future only)
                    VerticalLyricsContent()
                        .frame(maxWidth: .infinity)
                    
                    Spacer()
                }
                
                // Floating controls at bottom (show on hover) - same position as fullscreen
                VStack {
                    Spacer()
                    
                    VerticalFloatingControls()
                        .opacity(showControls ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: showControls)
                }
                .padding(.bottom, 40)
            }
        }
        .onHover { hovering in
            showControls = hovering
            if hovering {
                resetControlsTimer()
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }
}

// MARK: - Vertical Floating Controls (matches FloatingControlsView exactly)

struct VerticalFloatingControls: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        HStack(spacing: 20) {
            // Loop
            Button(action: { audioPlayer.toggleLoop() }) {
                Image(systemName: audioPlayer.isLooping ? "repeat.1" : "repeat")
                    .font(.system(size: 14))
                    .foregroundColor(audioPlayer.isLooping ? .white : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            
            // Seek back
            Button(action: { audioPlayer.seekBackward(10) }) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            
            // Play/Pause
            Button(action: { audioPlayer.togglePlayPause() }) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.black)
                        .offset(x: audioPlayer.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)
            
            // Seek forward
            Button(action: { audioPlayer.seekForward(10) }) {
                Image(systemName: "goforward.10")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            
            // Fullscreen
            Button(action: { settings.isFullScreen = true }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - Vertical Lyrics Content (Current + Future only)

struct VerticalLyricsContent: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    private let lineSpacing: CGFloat = 28
    
    private var visibleFutureLines: Int {
        settings.lyricLinesVisible + 1
    }
    
    private var isOneLineMode: Bool {
        settings.lyricLinesVisible == 1
    }
    
    var body: some View {
        if audioPlayer.hasLyrics {
            if isOneLineMode {
                // One-line mode: main lyric on top, background vocal below
                VStack {
                    Spacer()
                    
                    if let lyric = audioPlayer.oneLineModeLyric {
                        VStack(spacing: 8) {
                            // Main lyric (top, bold, all caps)
                            Text(lyric.mainText.uppercased())
                                .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 1.1))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.5)
                            
                            // Background vocal (bottom, smaller, dimmer)
                            if let background = lyric.backgroundText {
                                Text(background.uppercased())
                                    .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 0.7))
                                    .foregroundColor(.white.opacity(0.5))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.horizontal, 60)
                        .id(lyric.displayId)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.2), value: audioPlayer.oneLineModeLyric?.displayId)
            } else {
                VStack(spacing: lineSpacing) {
                    // Current lyric (bright, bold)
                    if audioPlayer.currentLyricIndex >= 0 && audioPlayer.currentLyricIndex < audioPlayer.lyrics.count {
                        Text(audioPlayer.lyrics[audioPlayer.currentLyricIndex].text)
                            .font(.system(size: settings.lyricFontSize, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 60)
                            .id("current-\(audioPlayer.currentLyricIndex)")
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 15)),
                                removal: .opacity.combined(with: .offset(y: -15))
                            ))
                    }
                
                    // Future lyrics (gray, progressively fading)
                    ForEach(1...visibleFutureLines, id: \.self) { offset in
                        let index = audioPlayer.currentLyricIndex + offset
                        if index >= 0 && index < audioPlayer.lyrics.count {
                            let opacity = 0.35 - Double(offset - 1) * 0.1
                            
                            Text(audioPlayer.lyrics[index].text)
                                .font(.system(size: settings.lyricFontSize * 0.75, weight: .medium))
                                .foregroundColor(.white.opacity(max(0.06, opacity)))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 60)
                                .id("future-\(index)")
                        }
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: audioPlayer.currentLyricIndex)
            }
        } else {
            Image(systemName: "text.quote")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(Color.white.opacity(0.1))
        }
    }
}

// MARK: - Square Artwork View

struct ArtworkView: View {
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        ZStack {
            // Square container
            RoundedRectangle(cornerRadius: 12)
                .fill(SettingsManager.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            
            // Artwork image or placeholder
            if let artwork = settings.artworkImage {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Minimal placeholder
                Image(systemName: "music.note")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundColor(Color.white.opacity(0.2))
            }
        }
        .frame(width: 200, height: 200)
    }
}

// MARK: - Progress Bar

struct ProgressBarView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)
                    
                    // Progress track
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: max(0, geometry.size.width * (isDragging ? dragProgress : audioPlayer.progress)), height: 4)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragProgress = max(0, min(1, value.location.x / geometry.size.width))
                        }
                        .onEnded { _ in
                            audioPlayer.seek(to: dragProgress * audioPlayer.duration)
                            isDragging = false
                        }
                )
            }
            .frame(height: 4)
            
            // Time labels
            HStack {
                Text(formatTime(audioPlayer.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(SettingsManager.accentDim)
                
                Spacer()
                
                Text(formatTime(audioPlayer.duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(SettingsManager.accentDim)
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Playback Controls

struct PlaybackControlsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    
    var body: some View {
        HStack(spacing: 32) {
            // Seek Back
            Button(action: { audioPlayer.seekBackward(10) }) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 20))
                    .foregroundColor(SettingsManager.accentDim)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.leftArrow, modifiers: [])
            
            // Play/Pause
            Button(action: { audioPlayer.togglePlayPause() }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(SettingsManager.background)
                        .offset(x: audioPlayer.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            
            // Seek Forward
            Button(action: { audioPlayer.seekForward(10) }) {
                Image(systemName: "goforward.10")
                    .font(.system(size: 20))
                    .foregroundColor(SettingsManager.accentDim)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }
}

// MARK: - Additional Controls

struct AdditionalControlsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        HStack(spacing: 24) {
            // Loop toggle
            Button(action: { audioPlayer.toggleLoop() }) {
                Image(systemName: audioPlayer.isLooping ? "repeat.1" : "repeat")
                    .font(.system(size: 16))
                    .foregroundColor(audioPlayer.isLooping ? .white : SettingsManager.accentDim)
            }
            .buttonStyle(.plain)
            
            // Volume
            HStack(spacing: 8) {
                Image(systemName: audioPlayer.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(SettingsManager.accentDim)
                
                Slider(value: $audioPlayer.volume, in: 0...1)
                    .frame(width: 70)
                    .tint(.white)
            }
            
            // Fullscreen lyrics
            Button(action: { settings.isFullScreen.toggle() }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16))
                    .foregroundColor(SettingsManager.accentDim)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    MainPlayerView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(SettingsManager())
        .frame(width: 1000, height: 700)
        .background(Color.black)
}
