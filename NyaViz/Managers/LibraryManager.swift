//
//  LibraryManager.swift
//  NyaViz
//

import AppKit
import Foundation

/// Manages the NyaViz persistent song library stored under
/// `~/Library/Application Support/NyaViz/Library/`.
///
/// Each imported song occupies its own sub-folder named after the entry's
/// 8-character id.  A JSON index file (`index.json`) inside each folder
/// holds the serialised ``LibraryEntry``.
@MainActor
class LibraryManager: ObservableObject {

    // MARK: - Published State

    /// All entries currently in the library, ordered by date added (newest first).
    @Published var entries: [LibraryEntry] = []

    /// The id of the entry that is currently loaded / playing, if any.
    @Published var currentEntryId: String?

    // MARK: - Paths

    /// Root directory for all library entries:
    /// `~/Library/Application Support/NyaViz/Library/`
    var libraryDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("NyaViz", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
    }

    // MARK: - Private Helpers

    private var indexFileName: String { "index.json" }

    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }

    private var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Init

    init() {
        loadIndex()
    }

    // MARK: - Directory for a Single Entry

    /// Returns the folder URL for the given entry.
    ///
    /// The folder is located at `libraryDirectory/<entry.id>/`.
    func entryDirectory(for entry: LibraryEntry) -> URL {
        libraryDirectory.appendingPathComponent(entry.id, isDirectory: true)
    }

    // MARK: - Index Persistence

    /// Loads all entries from disk by scanning each sub-folder's `index.json`.
    ///
    /// Entries that cannot be decoded are silently skipped.  After loading,
    /// ``entries`` is sorted newest-first by ``LibraryEntry/dateAdded``.
    func loadIndex() {
        let fm = FileManager.default
        guard let subDirs = try? fm.contentsOfDirectory(
            at: libraryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            entries = []
            return
        }

        var loaded: [LibraryEntry] = []
        for dir in subDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let indexURL = dir.appendingPathComponent(indexFileName)
            guard let data = try? Data(contentsOf: indexURL),
                  let entry = try? jsonDecoder.decode(LibraryEntry.self, from: data) else {
                continue
            }
            loaded.append(entry)
        }

        entries = loaded.sorted { $0.dateAdded > $1.dateAdded }
    }

    /// Persists a single ``LibraryEntry`` to its `index.json`.
    ///
    /// Creates the entry folder if it does not yet exist.
    func saveIndex(for entry: LibraryEntry) {
        let fm = FileManager.default
        let folder = entryDirectory(for: entry)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? jsonEncoder.encode(entry) else { return }
        try? data.write(to: folder.appendingPathComponent(indexFileName), options: .atomic)
    }

    // MARK: - Lookup

    /// Returns the first entry whose ``LibraryEntry/originalAudioName`` matches
    /// the given filename (case-insensitive).
    func findEntry(byAudioName name: String) -> LibraryEntry? {
        entries.first {
            $0.originalAudioName.lowercased() == name.lowercased()
        }
    }
}
