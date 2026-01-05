//
//  LyricsView.swift
//  NyaViz
//

import SwiftUI

// MARK: - Styled Text View

/// A view that renders a StyledLine with colors, bold, and italic formatting
struct StyledTextView: View {
    let styledLine: StyledLine
    let baseFont: Font
    let baseOpacity: Double
    let uppercased: Bool
    
    init(_ styledLine: StyledLine, font: Font, opacity: Double = 1.0, uppercased: Bool = false) {
        self.styledLine = styledLine
        self.baseFont = font
        self.baseOpacity = opacity
        self.uppercased = uppercased
    }
    
    var body: some View {
        styledLine.segments.reduce(Text("")) { result, segment in
            let displayText = uppercased ? segment.text.uppercased() : segment.text
            var text = Text(displayText)
            
            // Apply color (default white if no color specified)
            let color = segment.color ?? .white
            text = text.foregroundColor(color.opacity(baseOpacity))
            
            // Apply bold
            if segment.isBold {
                text = text.bold()
            }
            
            // Apply italic
            if segment.isItalic {
                text = text.italic()
            }
            
            return result + text
        }
        .font(baseFont)
    }
}

/// Creates an attributed Text from a StyledLine
extension StyledLine {
    /// Render styled text with colors
    /// - Parameters:
    ///   - font: The base font to use
    ///   - opacity: Overall opacity for the text (0.0 - 1.0)
    ///   - brightness: Brightness/saturation for colors (0.0 = white/no color, 1.0 = full color)
    ///   - uppercased: Whether to uppercase the text
    func attributedText(font: Font, opacity: Double = 1.0, brightness: Double = 1.0, uppercased: Bool = false) -> Text {
        segments.reduce(Text("")) { result, segment in
            let displayText = uppercased ? segment.text.uppercased() : segment.text
            var text = Text(displayText)
            
            // Apply color with brightness adjustment
            if let segmentColor = segment.color {
                // For colored segments, blend toward white based on brightness
                // brightness 1.0 = full color, 0.0 = white
                let adjustedColor = segmentColor.blendedTowardWhite(amount: 1.0 - brightness)
                text = text.foregroundColor(adjustedColor.opacity(opacity))
            } else {
                // Non-styled segments use white
                text = text.foregroundColor(Color.white.opacity(opacity))
            }
            
            if segment.isBold {
                text = text.bold()
            }
            if segment.isItalic {
                text = text.italic()
            }
            
            return result + text
        }
        .font(font)
    }
}

// MARK: - Color Brightness Extension

extension Color {
    /// Blend this color toward white
    /// - Parameter amount: 0.0 = original color, 1.0 = pure white
    func blendedTowardWhite(amount: Double) -> Color {
        // Clamp amount between 0 and 1
        let t = max(0, min(1, amount))
        
        // Get NSColor components
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else {
            return self
        }
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Interpolate toward white (1, 1, 1)
        let newR = r + (1.0 - r) * t
        let newG = g + (1.0 - g) * t
        let newB = b + (1.0 - b) * t
        
        return Color(red: newR, green: newG, blue: newB)
    }
}

// MARK: - Lyrics View

struct LyricsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if audioPlayer.hasLyrics {
                    if settings.lyricLinesVisible == 4 {
                        // Dialog mode: game-style conversation overlay
                        GameDialogLyricsView()
                    } else if settings.lyricLinesVisible == 1 {
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
                    // Main lyric (top, bold, all caps) - with styled text support
                    if lyric.hasStyles {
                        lyric.styledMainText.attributedText(
                            font: .custom("MollenTrial-Bold", size: settings.lyricFontSize * 1.1),
                            brightness: settings.colorBrightness,
                            uppercased: true
                        )
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    } else {
                        Text(lyric.mainText.uppercased())
                            .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 1.1))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    
                    // Background vocal (bottom, smaller, dimmer)
                    if let styledBackground = lyric.styledBackgroundText {
                        if styledBackground.hasStyles {
                            styledBackground.attributedText(
                                font: .custom("MollenTrial-Bold", size: settings.lyricFontSize * 0.7),
                                opacity: 0.5,
                                brightness: settings.colorBrightness,
                                uppercased: true
                            )
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            Text(styledBackground.plainText.uppercased())
                                .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 0.7))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
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
    
    private let lineSpacing: CGFloat = 20
    
    private var lineHeight: CGFloat {
        // Account for potential secondary line (translation)
        settings.lyricFontSize * 1.8
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
                    
                    LyricLineView(
                        lyric: lyric,
                        relativePosition: relativeOffset,
                        fontSize: settings.lyricFontSize,
                        maxDistance: CGFloat(visibleRange),
                        colorBrightness: settings.colorBrightness
                    )
                    .frame(minHeight: lineHeight)
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
    let lyric: Lyric
    let relativePosition: CGFloat
    let fontSize: CGFloat
    let maxDistance: CGFloat
    let colorBrightness: Double
    
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
        VStack(spacing: 4) {
            // Main lyric with styled text support
            if lyric.hasStyles {
                lyric.styledText.attributedText(
                    font: .system(size: isActive ? fontSize * 1.05 : fontSize * 0.9, weight: isActive ? .bold : .semibold, design: .default),
                    opacity: opacity,
                    brightness: colorBrightness
                )
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            } else {
                Text(lyric.text)
                    .font(.system(size: isActive ? fontSize * 1.05 : fontSize * 0.9, weight: isActive ? .bold : .semibold, design: .default))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundColor(.white.opacity(opacity))
            }
            
            // Secondary lyric (translation) - slightly smaller and dimmer
            if let styledSecondary = lyric.styledSecondaryText {
                if styledSecondary.hasStyles {
                    styledSecondary.attributedText(
                        font: .system(size: isActive ? fontSize * 0.75 : fontSize * 0.65, weight: isActive ? .medium : .regular, design: .default),
                        opacity: opacity * 0.6,
                        brightness: colorBrightness
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                } else {
                    Text(styledSecondary.plainText)
                        .font(.system(size: isActive ? fontSize * 0.75 : fontSize * 0.65, weight: isActive ? .medium : .regular, design: .default))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundColor(.white.opacity(opacity * 0.6))
                }
            }
        }
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
