//
//  LibraryDrawerView.swift
//  NyaViz
//

import SwiftUI

// MARK: - Date Formatting

private func relativeLabel(for date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

// MARK: - Library Drawer View

/// A slide-up bottom drawer that lists all entries in the song library.
///
/// The drawer always shows a controls bar (prev, play/pause, next, loop toggle)
/// at the bottom of the screen. Tapping the pill handle expands the drawer to
/// also reveal a scrollable song list below the controls bar.
struct LibraryDrawerView: View {

    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var audioPlayer: AudioPlayerManager

    @State private var isExpanded = false

    // Height of the scrollable song list portion (shown when expanded)
    private let songListHeight: CGFloat = 250

    // Pill handle dimensions
    private let pillWidth: CGFloat = 40
    private let pillHeight: CGFloat = 4

    // Sorted entries — most recently played first
    private var sortedEntries: [LibraryEntry] {
        library.entries.sorted { $0.lastPlayed > $1.lastPlayed }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            drawerContainer
        }
    }

    // MARK: - Outer Container

    /// The full drawer panel: translucent background wrapping the pill, controls,
    /// and (when expanded) the song list.
    private var drawerContainer: some View {
        VStack(spacing: 0) {
            // Pill handle — toggles expanded/collapsed song list
            pillHandle
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                }

            // Inline playback controls (always visible inside the drawer)
            controlsBar

            // Song list — only shown when expanded
            if isExpanded && !sortedEntries.isEmpty {
                songList
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(drawerBackground)
    }

    // MARK: - Background

    private var drawerBackground: some View {
        ZStack {
            // Thin material blur layer
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.6)

            // Dark tint on top so text stays readable
            Color.black.opacity(0.5)
        }
        .overlay(
            // Top separator line
            VStack {
                Divider()
                    .background(Color.white.opacity(0.12))
                Spacer()
            }
        )
    }

    // MARK: - Pill Handle

    private var pillHandle: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: pillHeight / 2)
                .fill(Color.white.opacity(0.25))
                .frame(width: pillWidth, height: pillHeight)
            Spacer()
        }
        .contentShape(Rectangle())
        .frame(height: 20)
        .padding(.top, 8)
    }

    // MARK: - Controls Bar

    /// Prev / Play-Pause / Next / Loop — always visible at the bottom of the screen.
    private var controlsBar: some View {
        HStack(spacing: 28) {
            // Previous song
            Button(action: { audioPlayer.playPreviousSong() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(!audioPlayer.hasAudio && library.entries.isEmpty)

            // Play / Pause
            Button(action: { audioPlayer.togglePlayPause() }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .offset(x: audioPlayer.isPlaying ? 0 : 1.5)
                }
            }
            .buttonStyle(.plain)

            // Next song
            Button(action: { audioPlayer.playNextSong() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(!audioPlayer.hasAudio && library.entries.isEmpty)

            // Separator
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 18)

            // Loop toggle
            Button(action: { audioPlayer.toggleLoop() }) {
                Image(systemName: audioPlayer.isLooping ? "repeat.1" : "repeat")
                    .font(.system(size: 14))
                    .foregroundColor(audioPlayer.isLooping ? .white : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
    }

    // MARK: - Song List

    private var songList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(sortedEntries) { entry in
                    LibraryRowView(entry: entry)
                        .onTapGesture {
                            audioPlayer.loadLibraryEntry(entry)
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: songListHeight)
    }
}

// MARK: - Library Row View

/// A single row inside the library drawer representing one ``LibraryEntry``.
private struct LibraryRowView: View {

    let entry: LibraryEntry

    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var audioPlayer: AudioPlayerManager

    @State private var isHovered = false

    private var isCurrentEntry: Bool {
        library.currentEntryId == entry.id
    }

    var body: some View {
        HStack(spacing: 8) {
            // Currently-playing indicator dot
            Circle()
                .fill(Color.white.opacity(isCurrentEntry ? 0.9 : 0))
                .frame(width: 5, height: 5)
                .padding(.leading, 12)

            // Title
            Text(entry.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(isCurrentEntry ? 1.0 : 0.8))
                .lineLimit(1)
                .truncationMode(.tail)

            // Lyrics indicator icon
            if entry.lyricsFile != nil {
                Image(systemName: "text.quote")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer(minLength: 8)

            // Last played date
            Text(relativeLabel(for: entry.lastPlayed))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .fixedSize()

            // Delete button
            Button {
                library.removeEntry(id: entry.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(isHovered ? 0.6 : 0.2))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .help("Remove from library")
        }
        .frame(height: 40)
        .background(rowBackground)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isCurrentEntry {
            Color.white.opacity(0.08)
        } else if isHovered {
            Color.white.opacity(0.04)
        } else {
            Color.clear
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(hex: "0a0a0a")
            .ignoresSafeArea()
        LibraryDrawerView()
    }
    .frame(width: 700, height: 500)
    .environmentObject(LibraryManager())
    .environmentObject(AudioPlayerManager())
}
