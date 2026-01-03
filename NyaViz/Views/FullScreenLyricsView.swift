//
//  FullScreenLyricsView.swift
//  NyaViz
//

import SwiftUI

struct FullScreenLyricsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Centered lyrics
                if audioPlayer.hasLyrics {
                    if settings.lyricLinesVisible == 1 {
                        // One-line mode: single centered lyric in Mollen Bold, all caps
                        FullScreenOneLineLyric()
                    } else {
                        FullScreenSmoothLyrics(containerHeight: geo.size.height)
                    }
                } else {
                    Image(systemName: "text.quote")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundColor(Color.white.opacity(0.1))
                }
                
                // Track info at top left (if enabled)
                if settings.showTrackTitle && !audioPlayer.audioFileName.isEmpty {
                    VStack {
                        HStack(alignment: .center, spacing: 12) {
                            // Progress ring
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 2)
                                    .frame(width: 32, height: 32)
                                
                                Circle()
                                    .trim(from: 0, to: audioPlayer.progress)
                                    .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .frame(width: 32, height: 32)
                                    .rotationEffect(.degrees(-90))
                                
                                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .onTapGesture {
                                audioPlayer.togglePlayPause()
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(audioPlayer.audioFileName)
                                    .font(.system(size: 14, weight: .medium, design: .default))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Text(formatTime(audioPlayer.currentTime) + " / " + formatTime(audioPlayer.duration))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        
                        Spacer()
                    }
                }
                
                // Audio Visualizer at the bottom
                if settings.showVisualizer {
                    AudioVisualizerView()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Full Screen One Line Lyric (Minimal mode)

struct FullScreenOneLineLyric: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        VStack {
            Spacer()
            
            if let lyric = audioPlayer.oneLineModeLyric {
                VStack(spacing: 10) {
                    // Main lyric (top, bold, all caps)
                    Text(lyric.mainText.uppercased())
                        .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 1.3))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                    
                    // Background vocal (bottom, smaller, dimmer)
                    if let background = lyric.backgroundText {
                        Text(background.uppercased())
                            .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 0.85))
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
    }
}

// MARK: - Full Screen Smooth Lyrics

struct FullScreenSmoothLyrics: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    let containerHeight: CGFloat
    
    private let lineSpacing: CGFloat = 24
    
    private var fontSize: CGFloat {
        settings.lyricFontSize * 1.2
    }
    
    private var lineHeight: CGFloat {
        // Account for potential secondary line (translation)
        fontSize * 2.0
    }
    
    private var totalLineHeight: CGFloat {
        lineHeight + lineSpacing
    }
    
    private var visibleRange: Int {
        settings.lyricLinesVisible
    }
    
    @State private var smoothIndex: CGFloat = 0
    
    var body: some View {
        ZStack {
            ForEach(-visibleRange...visibleRange, id: \.self) { offset in
                let index = audioPlayer.currentLyricIndex + offset
                if index >= 0 && index < audioPlayer.lyrics.count {
                    let lyric = audioPlayer.lyrics[index]
                    let relativeOffset = CGFloat(offset) - (smoothIndex - CGFloat(audioPlayer.currentLyricIndex))
                    
                    FullScreenLyricLine(
                        text: lyric.text,
                        secondaryText: lyric.secondaryText,
                        relativePosition: relativeOffset,
                        fontSize: fontSize,
                        maxDistance: CGFloat(visibleRange)
                    )
                    .frame(minHeight: lineHeight)
                    .offset(y: relativeOffset * totalLineHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .padding(.horizontal, 60)
        .onChange(of: audioPlayer.currentLyricIndex) { _, newValue in
            withAnimation(.easeOut(duration: 0.3)) {
                smoothIndex = CGFloat(newValue)
            }
        }
        .onAppear {
            smoothIndex = CGFloat(audioPlayer.currentLyricIndex)
        }
    }
}

struct FullScreenLyricLine: View {
    let text: String
    let secondaryText: String?
    let relativePosition: CGFloat
    let fontSize: CGFloat
    let maxDistance: CGFloat
    
    private var opacity: Double {
        let distance = abs(relativePosition)
        if distance < 0.1 { return 1.0 }
        let normalized = distance / max(maxDistance, 1)
        return max(0.06, 0.35 - normalized * 0.2)
    }
    
    private var scale: CGFloat {
        let distance = abs(relativePosition)
        if distance < 0.1 { return 1.0 }
        let normalized = distance / max(maxDistance, 1)
        return max(0.72, 0.9 - normalized * 0.12)
    }
    
    private var blur: CGFloat {
        let distance = abs(relativePosition)
        if distance < 0.1 { return 0 }
        return min(distance * 0.6, 2.0)
    }
    
    private var isActive: Bool {
        abs(relativePosition) < 0.5
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Main lyric
            Text(text)
                .font(.system(size: isActive ? fontSize * 1.08 : fontSize * 0.85, weight: isActive ? .heavy : .bold, design: .default))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .foregroundColor(.white.opacity(opacity))
            
            // Secondary lyric (translation) - slightly smaller and dimmer
            if let secondary = secondaryText {
                Text(secondary)
                    .font(.system(size: isActive ? fontSize * 0.8 : fontSize * 0.65, weight: isActive ? .semibold : .medium, design: .default))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundColor(.white.opacity(opacity * 0.6))
            }
        }
        .scaleEffect(scale)
        .blur(radius: blur)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Floating Controls

struct FloatingControlsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var videoExporter = VideoExporter()
    @State private var showExportAlert = false
    @State private var exportMessage = ""
    @State private var exportSuccess = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Export progress indicator
            if videoExporter.isExporting {
                VStack(spacing: 8) {
                    Text(videoExporter.statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 4)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                                .frame(width: geo.size.width * videoExporter.progress, height: 4)
                        }
                    }
                    .frame(width: 200, height: 4)
                    
                    Text("\(Int(videoExporter.progress * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            
            // Main controls
            HStack(spacing: 20) {
                // Loop
                Button(action: { audioPlayer.toggleLoop() }) {
                    Image(systemName: audioPlayer.isLooping ? "repeat.1" : "repeat")
                        .font(.system(size: 14))
                        .foregroundColor(audioPlayer.isLooping ? .white : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(videoExporter.isExporting)
                
                // Seek back
                Button(action: { audioPlayer.seekBackward(10) }) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(videoExporter.isExporting)
                
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
                .disabled(videoExporter.isExporting)
                
                // Seek forward
                Button(action: { audioPlayer.seekForward(10) }) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(videoExporter.isExporting)
                
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1, height: 20)
                
                // Export video button
                Button(action: { startExport() }) {
                    Image(systemName: videoExporter.isExporting ? "arrow.clockwise" : "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundColor(videoExporter.isExporting ? .white.opacity(0.3) : .white.opacity(0.5))
                        .rotationEffect(.degrees(videoExporter.isExporting ? 360 : 0))
                        .animation(videoExporter.isExporting ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: videoExporter.isExporting)
                }
                .buttonStyle(.plain)
                .disabled(videoExporter.isExporting || !audioPlayer.hasAudio)
                .help("Export video")
                
                // Exit fullscreen
                Button(action: { settings.isFullScreen = false }) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(videoExporter.isExporting)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .alert(exportSuccess ? "Export Complete" : "Export Failed", isPresented: $showExportAlert) {
            Button("OK") { }
        } message: {
            Text(exportMessage)
        }
    }
    
    private func startExport() {
        // Pause playback during export
        if audioPlayer.isPlaying {
            audioPlayer.pause()
        }
        
        videoExporter.exportVideo(
            audioPlayer: audioPlayer,
            settings: settings
        ) { result in
            switch result {
            case .success(let url):
                exportSuccess = true
                exportMessage = "Video saved to:\n\(url.lastPathComponent)"
                showExportAlert = true
            case .failure(let error):
                exportSuccess = false
                exportMessage = error.localizedDescription
                showExportAlert = true
            }
        }
    }
}

#Preview {
    FullScreenLyricsView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(SettingsManager())
        .background(Color.black)
}
