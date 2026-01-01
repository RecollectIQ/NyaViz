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
                
                // Right Panel - Lyrics
                LyricsView()
                    .frame(maxWidth: .infinity)
            }
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
            
            // Settings
            Button(action: { settings.showSettings.toggle() }) {
                Image(systemName: "slider.horizontal.3")
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
