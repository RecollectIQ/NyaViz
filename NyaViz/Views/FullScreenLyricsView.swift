//
//  FullScreenLyricsView.swift
//  NyaViz
//

import SwiftUI

struct FullScreenLyricsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var library: LibraryManager
    @Environment(\.uiScale) private var scale

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Centered lyrics with crossfade between modes
                if audioPlayer.hasLyrics {
                    Group {
                        if settings.lyricLinesVisible == 4 {
                            FullScreenGameDialogLyrics()
                        } else if settings.lyricLinesVisible == 1 {
                            FullScreenOneLineLyric()
                        } else {
                            FullScreenSmoothLyrics(containerHeight: geo.size.height)
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.8), value: settings.lyricLinesVisible)
                } else {
                    Image(systemName: "text.quote")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundColor(Color.white.opacity(0.1))
                }

                // Track info card and track picker at top left (if enabled).
                // All sizing comes from the shared `uiScale` — see `UIScale`.
                if settings.showTrackTitle && !audioPlayer.audioFileName.isEmpty {
                    VStack {
                        FullScreenTrackInfoView()
                        Spacer()
                    }
                }

                // Audio Visualizer at the bottom
                if settings.showVisualizer {
                    AudioVisualizerView()
                        .padding(.horizontal, 24 * scale)
                        .padding(.bottom, 12 * scale)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Full Screen Track Info + Track Picker

/// The track-info card pinned to the top-left of full-screen lyrics mode: a
/// progress ring that doubles as play/pause, the track title and elapsed time,
/// and a chevron that reveals the track picker.
///
/// The chevron only fades in while the pointer is over the card, keeping the
/// full-screen presentation clean until the user goes looking for it.
///
/// Double-clicking the title renames the track.  Titles start out as the audio
/// filename, which is often not something anyone would choose to read
/// (`Nightcore_Bound_to_Break_sped_up_NV_`), so renaming is worth having close
/// to where the name is actually displayed.
struct FullScreenTrackInfoView: View {

    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var library: LibraryManager
    @Environment(\.uiScale) private var scale

    @State private var isHovered = false
    @State private var isExpanded = false

    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @FocusState private var titleFieldFocused: Bool

    /// The library entry's title once there is one, falling back to the audio
    /// filename for audio that has not been imported.
    private var displayTitle: String {
        library.currentEntry?.title ?? audioPlayer.audioFileName
    }

    /// Renaming writes to a library entry, so it is only offered when one exists.
    private var canRename: Bool {
        library.currentEntry != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            HStack(alignment: .center, spacing: 12 * scale) {
                // Progress ring (tap to play/pause)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 2 * scale)
                        .frame(width: 32 * scale, height: 32 * scale)

                    Circle()
                        .trim(from: 0, to: audioPlayer.progress)
                        .stroke(
                            Color.white.opacity(0.8),
                            style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round)
                        )
                        .frame(width: 32 * scale, height: 32 * scale)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 9 * scale))
                        .foregroundColor(.white.opacity(0.8))
                }
                .contentShape(Circle())
                .onTapGesture {
                    audioPlayer.togglePlayPause()
                }

                VStack(alignment: .leading, spacing: 2 * scale) {
                    if isEditingTitle {
                        TextField("Track title", text: $draftTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14 * scale, weight: .medium, design: .default))
                            .foregroundColor(.white)
                            .focused($titleFieldFocused)
                            .frame(maxWidth: 320 * scale)
                            .padding(.horizontal, 6 * scale)
                            .padding(.vertical, 2 * scale)
                            .background(
                                RoundedRectangle(cornerRadius: 4 * scale)
                                    .fill(Color.white.opacity(0.12))
                            )
                            .onSubmit { commitTitle() }
                            .onExitCommand { cancelTitle() }
                    } else {
                        Text(displayTitle)
                            .font(.system(size: 14 * scale, weight: .medium, design: .default))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                            .onTapGesture(count: 2) { beginEditingTitle() }
                            .help(canRename ? "Double-click to rename" : "")
                    }

                    Text(formatTime(audioPlayer.currentTime) + " / " + formatTime(audioPlayer.duration))
                        .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                // Track picker chevron — visible on hover, or while the list is open
                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 22 * scale, height: 22 * scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isExpanded ? 1 : 0)
                .help("Choose a track")

                Spacer(minLength: 0)
            }

            // Track list, reading as a continuation of the title above it.
            // Indented past the progress ring so its left edge lines up with
            // the track title rather than the ring.
            if isExpanded {
                FullScreenTrackListView { isExpanded = false }
                    .padding(.leading, 44 * scale)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(.horizontal, 24 * scale)
        .padding(.top, 20 * scale)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isExpanded)
        // Collapse on Escape. The button is invisible but its shortcut stays live.
        .background(
            Button("") { isExpanded = false }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
                .disabled(!isExpanded || isEditingTitle)
        )
    }

    private func toggleExpanded() {
        isExpanded.toggle()
    }

    // MARK: - Renaming

    private func beginEditingTitle() {
        guard canRename else { return }
        draftTitle = displayTitle
        isEditingTitle = true
        titleFieldFocused = true
    }

    /// Saves the edited title. An empty or unchanged title simply closes the
    /// field — ``LibraryManager/renameEntry(id:to:)`` rejects the former.
    private func commitTitle() {
        defer { endEditing() }
        guard let id = library.currentEntryId else { return }
        library.renameEntry(id: id, to: draftTitle)
    }

    private func cancelTitle() {
        endEditing()
    }

    private func endEditing() {
        isEditingTitle = false
        titleFieldFocused = false
        draftTitle = ""
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
                    // Main lyric (top, bold, all caps) - with styled text support
                    if lyric.hasStyles {
                        lyric.styledMainText.attributedText(
                            font: .custom("MollenTrial-Bold", size: settings.lyricFontSize * 1.3),
                            brightness: settings.colorBrightness,
                            uppercased: true
                        )
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                    } else {
                        Text(lyric.mainText.uppercased())
                            .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 1.3))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                    }
                    
                    // Background vocal (bottom, smaller, dimmer)
                    if let styledBackground = lyric.styledBackgroundText {
                        if styledBackground.hasStyles {
                            styledBackground.attributedText(
                                font: .custom("MollenTrial-Bold", size: settings.lyricFontSize * 0.85),
                                opacity: 0.5,
                                brightness: settings.colorBrightness,
                                uppercased: true
                            )
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            Text(styledBackground.plainText.uppercased())
                                .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 0.85))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
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
                        lyric: lyric,
                        relativePosition: relativeOffset,
                        fontSize: fontSize,
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
    let lyric: Lyric
    let relativePosition: CGFloat
    let fontSize: CGFloat
    let maxDistance: CGFloat
    let colorBrightness: Double
    
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
            // Main lyric with styled text support
            if lyric.hasStyles {
                lyric.styledText.attributedText(
                    font: .system(size: isActive ? fontSize * 1.08 : fontSize * 0.85, weight: isActive ? .heavy : .bold, design: .default),
                    opacity: opacity,
                    brightness: colorBrightness
                )
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            } else {
                Text(lyric.text)
                    .font(.system(size: isActive ? fontSize * 1.08 : fontSize * 0.85, weight: isActive ? .heavy : .bold, design: .default))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundColor(.white.opacity(opacity))
            }
            
            // Secondary lyric (translation) - slightly smaller and dimmer
            if let styledSecondary = lyric.styledSecondaryText {
                if styledSecondary.hasStyles {
                    styledSecondary.attributedText(
                        font: .system(size: isActive ? fontSize * 0.8 : fontSize * 0.65, weight: isActive ? .semibold : .medium, design: .default),
                        opacity: opacity * 0.6,
                        brightness: colorBrightness
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                } else {
                    Text(styledSecondary.plainText)
                        .font(.system(size: isActive ? fontSize * 0.8 : fontSize * 0.65, weight: isActive ? .semibold : .medium, design: .default))
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

// MARK: - Floating Controls

struct FloatingControlsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.uiScale) private var scale
    @StateObject private var videoExporter = VideoExporter()
    @State private var showExportAlert = false
    @State private var exportMessage = ""
    @State private var exportSuccess = false
    
    var body: some View {
        VStack(spacing: 12 * scale) {
            // Export progress indicator
            if videoExporter.isExporting {
                VStack(spacing: 8 * scale) {
                    Text(videoExporter.statusMessage)
                        .font(.system(size: 12 * scale, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2 * scale)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 4 * scale)
                            
                            RoundedRectangle(cornerRadius: 2 * scale)
                                .fill(Color.white)
                                .frame(width: geo.size.width * videoExporter.progress, height: 4 * scale)
                        }
                    }
                    .frame(width: 200 * scale, height: 4 * scale)
                    
                    Text("\(Int(videoExporter.progress * 100))%")
                        .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 24 * scale)
                .padding(.vertical, 8 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 12 * scale)
                        .fill(Color.black.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12 * scale)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            
            // Main controls
            HStack(spacing: 18 * scale) {
                // Loop
                Button(action: { audioPlayer.toggleLoop() }) {
                    Image(systemName: audioPlayer.isLooping ? "repeat.1" : "repeat")
                        .font(.system(size: 12 * scale))
                        .foregroundColor(audioPlayer.isLooping ? .white : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(videoExporter.isExporting)

                // Previous song
                Button(action: { audioPlayer.playPreviousSong() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 12 * scale))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(videoExporter.isExporting)

                // Play/Pause
                Button(action: { audioPlayer.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 36 * scale, height: 36 * scale)

                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13 * scale))
                            .foregroundColor(.black)
                            .offset(x: audioPlayer.isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(.plain)
                .disabled(videoExporter.isExporting)

                // Next song
                Button(action: { audioPlayer.playNextSong() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12 * scale))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(videoExporter.isExporting)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1, height: 16 * scale)

                // Export video button
                Button(action: { startExport() }) {
                    Image(systemName: videoExporter.isExporting ? "arrow.clockwise" : "square.and.arrow.up")
                        .font(.system(size: 12 * scale))
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
                        .font(.system(size: 12 * scale))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(videoExporter.isExporting)
            }
            .padding(.horizontal, 20 * scale)
            .padding(.vertical, 10 * scale)
        }
        .alert(exportSuccess ? "Export Complete" : "Export Failed", isPresented: $showExportAlert) {
            Button("OK") { }
        } message: {
            Text(exportMessage)
        }
        .sheet(isPresented: $videoExporter.showExportOptions) {
            ExportOptionsSheet(videoExporter: videoExporter)
        }
    }
    
    private func startExport() {
        // Pause playback during export
        if audioPlayer.isPlaying {
            audioPlayer.pause()
        }
        
        videoExporter.showExportOptionsAndExport(
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

// MARK: - Export Options Sheet

struct ExportOptionsSheet: View {
    @ObservedObject var videoExporter: VideoExporter
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Options")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Options
            VStack(spacing: 20) {
                // Resolution picker - use menu style for better fit
                VStack(alignment: .leading, spacing: 10) {
                    Text("Resolution")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    HStack(spacing: 8) {
                        ForEach(ExportOptions.Resolution.allCases, id: \.self) { res in
                            ResolutionButton(
                                resolution: res,
                                isSelected: videoExporter.exportOptions.resolution == res
                            ) {
                                videoExporter.exportOptions.resolution = res
                            }
                        }
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Visualizer toggle
                Toggle(isOn: $videoExporter.exportOptions.includeVisualizer) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Audio Visualizer")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Shows frequency bars at bottom")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .toggleStyle(.switch)
                .tint(.blue)
                
                // Particles toggle
                Toggle(isOn: $videoExporter.exportOptions.includeParticles) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Snow Particles")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Animated falling particles")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .toggleStyle(.switch)
                .tint(.blue)
            }
            .padding(24)
            
            Spacer()
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    videoExporter.cancelExport()
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                
                Button("Export") {
                    videoExporter.confirmExport()
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .padding(24)
        }
        .frame(width: 420, height: 400)
        .background(Color(hex: "1a1a1a"))
    }
}

struct ResolutionButton: View {
    let resolution: ExportOptions.Resolution
    let isSelected: Bool
    let action: () -> Void
    
    private var shortLabel: String {
        switch resolution {
        case .r2160p: return "4K"
        case .r1080p: return "1080p"
        case .r720p: return "720p"
        case .r480p: return "480p"
        }
    }
    
    private var sizeLabel: String {
        "\(resolution.width)×\(resolution.height)"
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(shortLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                Text(sizeLabel)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.blue : Color.white.opacity(0.08))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FullScreenLyricsView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(SettingsManager())
        .background(Color.black)
}
