//
//  LibraryEntry.swift
//  NyaViz
//

import Foundation

/// A single entry in the NyaViz persistent song library.
///
/// Each entry represents one imported audio file along with its optional associated
/// lyrics file. Entries are stored as a JSON index inside the per-entry folder under
/// `~/Library/Application Support/NyaViz/Library/<id>/`.
struct LibraryEntry: Codable, Identifiable, Equatable {
    /// Unique identifier for this entry (8-character UUID prefix).
    let id: String
    /// Display title derived from the original audio filename.
    var title: String
    /// Filename of the copied audio file within the entry's folder.
    var audioFile: String
    /// Filename of the copied lyrics file within the entry's folder, if any.
    var lyricsFile: String?
    /// The date this entry was first added to the library.
    var dateAdded: Date
    /// The date this entry was most recently played.
    var lastPlayed: Date
    /// The original filename of the audio file before it was imported.
    var originalAudioName: String
}
