//
//  FullScreenTrackListView.swift
//  NyaViz
//

import SwiftUI

/// The track picker that drops down beneath the track-info card in full-screen
/// lyrics mode.
///
/// Full-screen mode deliberately hides the windowed library sidebar, so this is
/// the only way to change tracks without leaving full screen.  It lists the same
/// entries in the same order the playlist advances through
/// (``AudioPlayerManager/playNextSong()`` sorts by `lastPlayed` descending).
struct FullScreenTrackListView: View {

    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @Environment(\.uiScale) private var scale

    /// Called after a track is chosen so the caller can collapse the panel.
    let onSelect: () -> Void

    private var sortedEntries: [LibraryEntry] {
        library.entries.sorted { $0.lastPlayed > $1.lastPlayed }
    }

    private var rowHeight: CGFloat { 32 * scale }
    private var listPadding: CGFloat { 12 * scale }

    /// A `ScrollView` takes all the height it is offered, so a short library
    /// would otherwise render as a mostly-empty panel.  Rows are a fixed height,
    /// so the content height is exact rather than estimated.
    private var listHeight: CGFloat {
        let content = CGFloat(sortedEntries.count) * rowHeight + listPadding
        return min(content, 320 * scale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sortedEntries.isEmpty {
                Text("No songs in library")
                    .font(.system(size: 12 * scale))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14 * scale)
                    .padding(.vertical, 14 * scale)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedEntries) { entry in
                            FullScreenTrackRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    audioPlayer.loadLibraryEntry(entry)
                                    onSelect()
                                }
                        }
                    }
                    .padding(.vertical, listPadding / 2)
                }
                .frame(height: listHeight)
            }
        }
        .frame(width: 300 * scale)
        .background(
            RoundedRectangle(cornerRadius: 12 * scale)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 12 * scale)
                        .fill(Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12 * scale)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12 * scale))
        .shadow(color: .black.opacity(0.5), radius: 18 * scale, y: 8 * scale)
    }
}

// MARK: - Row

private struct FullScreenTrackRow: View {

    let entry: LibraryEntry

    @EnvironmentObject var library: LibraryManager
    @Environment(\.uiScale) private var scale
    @State private var isHovered = false

    private var isCurrentEntry: Bool {
        library.currentEntryId == entry.id
    }

    var body: some View {
        HStack(spacing: 8 * scale) {
            Circle()
                .fill(Color.white.opacity(isCurrentEntry ? 0.9 : 0))
                .frame(width: 5 * scale, height: 5 * scale)

            Text(entry.title)
                .font(.system(size: 12 * scale, weight: isCurrentEntry ? .semibold : .medium))
                .foregroundColor(.white.opacity(isCurrentEntry ? 1.0 : 0.75))
                .lineLimit(1)
                .truncationMode(.tail)

            if entry.lyricsFile != nil {
                Image(systemName: "text.quote")
                    .font(.system(size: 9 * scale))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer(minLength: 4 * scale)
        }
        .padding(.horizontal, 14 * scale)
        .frame(height: 32 * scale)  // keep in sync with FullScreenTrackListView.rowHeight
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
            Color.white.opacity(0.10)
        } else if isHovered {
            Color.white.opacity(0.06)
        } else {
            Color.clear
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(hex: "0a0a0a")
        FullScreenTrackListView(onSelect: {})
            .environment(\.uiScale, 1.3)
    }
    .frame(width: 700, height: 500)
    .environmentObject(LibraryManager())
    .environmentObject(AudioPlayerManager())
}
