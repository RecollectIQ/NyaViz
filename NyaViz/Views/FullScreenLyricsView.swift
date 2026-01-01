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
            ZStack {
                // Centered lyrics
                if audioPlayer.hasLyrics {
                    FullScreenSmoothLyrics(containerHeight: geo.size.height)
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

// MARK: - Full Screen Smooth Lyrics

struct FullScreenSmoothLyrics: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    let containerHeight: CGFloat
    
    private let lineSpacing: CGFloat = 20
    
    private var fontSize: CGFloat {
        settings.lyricFontSize * 1.2
    }
    
    private var lineHeight: CGFloat {
        fontSize * 1.4
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
                    let relativeOffset = CGFloat(offset) - (smoothIndex - CGFloat(audioPlayer.currentLyricIndex))
                    
                    FullScreenLyricLine(
                        text: audioPlayer.lyrics[index].text,
                        relativePosition: relativeOffset,
                        fontSize: fontSize,
                        maxDistance: CGFloat(visibleRange)
                    )
                    .frame(height: lineHeight)
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
        Text(text)
            .font(.system(size: isActive ? fontSize * 1.08 : fontSize * 0.85, weight: isActive ? .heavy : .bold, design: .default))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .foregroundColor(.white.opacity(opacity))
            .scaleEffect(scale)
            .blur(radius: blur)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Floating Controls

struct FloatingControlsView: View {
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
            
            // Exit fullscreen
            Button(action: { settings.isFullScreen = false }) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.4))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

#Preview {
    FullScreenLyricsView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(SettingsManager())
        .background(Color.black)
}
