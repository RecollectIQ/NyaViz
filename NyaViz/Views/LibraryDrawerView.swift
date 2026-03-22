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

// MARK: - Library Sidebar View

/// A left sidebar that lists all entries in the song library.
/// Slides in from the left, matching the settings panel on the right.
struct LibraryDrawerView: View {

    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var audioPlayer: AudioPlayerManager

    private var sortedEntries: [LibraryEntry] {
        library.entries.sorted { $0.lastPlayed > $1.lastPlayed }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Library")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))

                    Spacer()

                    Button(action: { library.isDrawerExpanded = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()
                    .background(Color.white.opacity(0.1))

                // Song list
                if sortedEntries.isEmpty {
                    VStack {
                        Spacer()
                        Text("No songs yet")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Open an audio file to begin")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.2))
                        Spacer()
                    }
                } else {
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
                }
            }
            .frame(width: 260)
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.25))

            Spacer()
        }
    }
}

// MARK: - Library Row View

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

            Spacer(minLength: 4)

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
                    .foregroundColor(.white.opacity(isHovered ? 0.6 : 0.15))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .help("Remove from library")
        }
        .frame(height: 36)
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
