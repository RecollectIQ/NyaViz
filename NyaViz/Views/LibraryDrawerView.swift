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
/// Collapsed state shows only a small pill handle. Expanding it reveals a
/// scrollable list sorted by ``LibraryEntry/lastPlayed`` descending.
struct LibraryDrawerView: View {

    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var audioPlayer: AudioPlayerManager

    @State private var isExpanded = false

    // Height of the expanded drawer panel (not counting the handle bar area)
    private let drawerHeight: CGFloat = 300

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

            // Pill handle (always visible)
            pillHandle
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                }

            // Expanded drawer body
            if isExpanded {
                drawerBody
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Pill Handle

    private var pillHandle: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: pillHeight / 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: pillWidth, height: pillHeight)
            Spacer()
        }
        .padding(.bottom, isExpanded ? 0 : 8)
        .contentShape(Rectangle())
        .frame(height: 24)
    }

    // MARK: - Drawer Body

    private var drawerBody: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(Color.black.opacity(0.85))
                .overlay(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.3)
                )

            // Top border
            VStack {
                Divider()
                    .background(Color.white.opacity(0.1))
                Spacer()
            }

            // Content
            if sortedEntries.isEmpty {
                emptyState
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
        .frame(height: drawerHeight)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.2))
            Text("No songs in library")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.3))
        }
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
