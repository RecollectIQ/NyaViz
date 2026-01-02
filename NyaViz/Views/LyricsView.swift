//
//  LyricsView.swift
//  NyaViz
//

import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if audioPlayer.hasLyrics {
                    if settings.lyricLinesVisible == 1 {
                        // One-line mode: single centered lyric in Mollen Bold, all caps
                        OneLineLyricView()
                    } else {
                        SmoothLyricsView(containerHeight: geo.size.height)
                    }
                } else {
                    // Minimal empty state
                    Image(systemName: "text.quote")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundColor(Color.white.opacity(0.1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - One Line Lyric View (Minimal mode)

struct OneLineLyricView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
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
                        .minimumScaleFactor(0.6)
                    
                    // Background vocal (bottom, smaller, dimmer)
                    if let background = lyric.backgroundText {
                        Text(background.uppercased())
                            .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 0.7))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 40)
                .id(lyric.displayId)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: audioPlayer.oneLineModeLyric?.displayId)
    }
}

// MARK: - Smooth Scrolling Lyrics

struct SmoothLyricsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    let containerHeight: CGFloat
    
    private let lineSpacing: CGFloat = 16
    
    private var lineHeight: CGFloat {
        settings.lyricFontSize * 1.3
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
                    
                    LyricLineView(
                        text: audioPlayer.lyrics[index].text,
                        relativePosition: relativeOffset,
                        fontSize: settings.lyricFontSize,
                        maxDistance: CGFloat(visibleRange)
                    )
                    .frame(height: lineHeight)
                    .offset(y: relativeOffset * totalLineHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .padding(.horizontal, 40)
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

struct LyricLineView: View {
    let text: String
    let relativePosition: CGFloat
    let fontSize: CGFloat
    let maxDistance: CGFloat
    
    private var opacity: Double {
        let distance = abs(relativePosition)
        if distance < 0.1 { return 1.0 }
        // Fade based on distance from center
        let normalized = distance / max(maxDistance, 1)
        return max(0.08, 0.4 - normalized * 0.25)
    }
    
    private var scale: CGFloat {
        let distance = abs(relativePosition)
        if distance < 0.1 { return 1.0 }
        let normalized = distance / max(maxDistance, 1)
        return max(0.75, 0.92 - normalized * 0.1)
    }
    
    private var blur: CGFloat {
        let distance = abs(relativePosition)
        if distance < 0.1 { return 0 }
        return min(distance * 0.5, 1.5)
    }
    
    private var isActive: Bool {
        abs(relativePosition) < 0.5
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: isActive ? fontSize * 1.05 : fontSize * 0.9, weight: isActive ? .bold : .semibold, design: .default))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .foregroundColor(.white.opacity(opacity))
            .scaleEffect(scale)
            .blur(radius: blur)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    LyricsView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(SettingsManager())
        .background(Color.black)
        .frame(width: 600, height: 700)
}
