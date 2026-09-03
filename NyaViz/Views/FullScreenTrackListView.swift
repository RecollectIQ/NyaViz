//
//  FullScreenTrackListView.swift
//  NyaViz
//

import SwiftUI

/// The track picker that appears beneath the track-info card in full-screen
/// lyrics mode.
///
/// Deliberately not a panel: no surface, border or shadow of its own.  It reads
/// as a continuation of the track title — plain lines of text sharing the same
/// background and the same left edge — so expanding it does not drop a piece of
/// window chrome over the artwork.
///
/// Full-screen mode hides the windowed library sidebar, so this is the only way
/// to change tracks without leaving full screen.  It lists entries in the order
/// the playlist advances through them (``AudioPlayerManager/playNextSong()``
/// sorts by `lastPlayed` descending).
struct FullScreenTrackListView: View {

    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @Environment(\.uiScale) private var scale

    /// Called after a track is chosen so the caller can collapse the list.
    let onSelect: () -> Void

    private var sortedEntries: [LibraryEntry] {
        library.entries.sorted { $0.lastPlayed > $1.lastPlayed }
    }

    private var rowHeight: CGFloat { 26 * scale }

    /// A `ScrollView` takes all the height it is offered, so a short library
    /// would otherwise leave a large empty gap.  Rows are a fixed height, so the
    /// content height is exact rather than estimated.
    private var listHeight: CGFloat {
        min(CGFloat(sortedEntries.count) * rowHeight, 320 * scale)
    }

    var body: some View {
        Group {
            if sortedEntries.isEmpty {
                Text("No songs in library")
                    .font(.system(size: 12 * scale))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(height: rowHeight, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sortedEntries) { entry in
                            FullScreenTrackRow(entry: entry, height: rowHeight)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    audioPlayer.loadLibraryEntry(entry)
                                    onSelect()
                                }
                        }
                    }
                }
                .frame(height: listHeight)
            }
        }
        // Long titles truncate rather than running across the lyrics.
        .frame(maxWidth: 340 * scale, alignment: .leading)
    }
}

// MARK: - Row

private struct FullScreenTrackRow: View {

    let entry: LibraryEntry
    let height: CGFloat

    @EnvironmentObject var library: LibraryManager
    @Environment(\.uiScale) private var scale
    @State private var isHovered = false

    private var isCurrentEntry: Bool {
        library.currentEntryId == entry.id
    }

    /// The playing track reads at full strength, the rest recede; hovering lifts
    /// a row part-way.  Brightness carries the state instead of a filled row.
    private var titleOpacity: Double {
        if isCurrentEntry { return 0.95 }
        return isHovered ? 0.85 : 0.45
    }

    var body: some View {
        HStack(spacing: 6 * scale) {
            Text(entry.title)
                .font(.system(size: 13 * scale, weight: isCurrentEntry ? .semibold : .regular))
                .foregroundColor(.white.opacity(titleOpacity))
                .lineLimit(1)
                .truncationMode(.tail)

            if entry.lyricsFile != nil {
                Image(systemName: "text.quote")
                    .font(.system(size: 9 * scale))
                    .foregroundColor(.white.opacity(titleOpacity * 0.5))
            }

            Spacer(minLength: 0)
        }
        .frame(height: height)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
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
