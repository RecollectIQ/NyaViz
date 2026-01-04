//
//  GameDialogLyricsView.swift
//  NyaViz
//

import SwiftUI

// MARK: - Game Dialog Lyrics View (Game conversation overlay style)

struct GameDialogLyricsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    // Use oneLineModeLyric to respect SRT end times (like minimal mode)
    private var currentLyric: String? {
        audioPlayer.oneLineModeLyric?.mainText
    }
    
    private var hasCurrentLyric: Bool {
        currentLyric != nil && !currentLyric!.isEmpty
    }
    
    private var displayName: String {
        settings.dialogCharacterName.isEmpty ? "CHARACTER" : settings.dialogCharacterName
    }
    
    var body: some View {
        GeometryReader { geo in
            let fontSize = settings.lyricFontSize * 0.85
            let dialogMaxWidth = geo.size.width * settings.dialogMaxWidth
            let dialogMaxHeight = geo.size.height * settings.dialogMaxHeight
            let horizontalMargin = (geo.size.width - dialogMaxWidth) / 2
            let nameTagFontSize = max(11, min(14, geo.size.width * 0.012))
            
            // Position calculation: dialogPosition is 0.5-0.9 where higher = lower on screen
            let topSpacerHeight = geo.size.height * settings.dialogPosition - (dialogMaxHeight / 2)
            
            VStack {
                // Top spacer (pushes dialog down)
                Spacer()
                    .frame(height: max(0, topSpacerHeight))
                
                // Game dialog box container - centered horizontally
                HStack {
                    Spacer(minLength: max(horizontalMargin, 24))
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // Character name tag - positioned at top left
                        HStack {
                            Text(displayName.uppercased())
                                .font(.custom("MollenTrial-Bold", size: nameTagFontSize))
                                .tracking(2)
                                .foregroundColor(.white.opacity(0.95))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    Rectangle()
                                        .fill(Color.white.opacity(0.12))
                                )
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                )
                                .offset(x: -2, y: -1)
                            
                            Spacer()
                        }
                        .offset(y: 1)
                        
                        // Main dialog box - centered text, dynamic width
                        VStack(spacing: 0) {
                            if let lyric = currentLyric {
                                Text(lyric.uppercased())
                                    .font(.custom("MollenTrial-Bold", size: fontSize))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(4)
                                    .minimumScaleFactor(0.5)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                                    .id("dialog-\(lyric)")
                                    .transition(.opacity)
                            } else {
                                // Empty state with placeholder (when between lyrics or SRT ended)
                                Text("...")
                                    .font(.custom("MollenTrial-Bold", size: fontSize))
                                    .foregroundColor(.white.opacity(0.3))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                        .frame(maxWidth: dialogMaxWidth, maxHeight: dialogMaxHeight)
                        .background(
                            // Dialog box background with wide border
                            Rectangle()
                                .fill(Color.black.opacity(0.65))
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.white.opacity(0.35), lineWidth: 3)
                                )
                                .overlay(
                                    // Inner border for depth
                                    Rectangle()
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        .padding(4)
                                )
                        )
                    }
                    .frame(maxWidth: dialogMaxWidth)
                    
                    Spacer(minLength: max(horizontalMargin, 24))
                }
                
                // Bottom spacer
                Spacer()
            }
        }
        .animation(.easeOut(duration: 0.15), value: currentLyric)
    }
}

// MARK: - Full Screen Game Dialog View (wrapper for fullscreen mode)

struct FullScreenGameDialogLyrics: View {
    var body: some View {
        GameDialogLyricsView()
    }
}

#Preview {
    ZStack {
        Color.black
        GameDialogLyricsView()
            .environmentObject(AudioPlayerManager())
            .environmentObject(SettingsManager())
    }
    .frame(width: 1200, height: 800)
}

