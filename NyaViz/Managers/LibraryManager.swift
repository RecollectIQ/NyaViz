//
//  LibraryManager.swift
//  NyaViz
//

import AppKit
import Combine
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

    // MARK: - URL Accessors

    /// Returns the on-disk URL of the audio file for the given entry, or `nil`
    /// if the file does not exist.
    func audioURL(for entry: LibraryEntry) -> URL? {
        let url = entryDirectory(for: entry).appendingPathComponent(entry.audioFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Returns the on-disk URL of the lyrics file for the given entry, or `nil`
    /// if no lyrics file is associated or the file does not exist.
    func lyricsURL(for entry: LibraryEntry) -> URL? {
        guard let lyricsFile = entry.lyricsFile else { return nil }
        let url = entryDirectory(for: entry).appendingPathComponent(lyricsFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Import

    /// Imports an audio file into the library.
    ///
    /// If an existing entry already references the same audio filename it is
    /// returned as-is (de-duplication by ``LibraryEntry/originalAudioName``).
    /// Otherwise a new entry folder is created, the audio file is copied into
    /// it, and the entry is persisted and prepended to ``entries``.
    ///
    /// - Parameter sourceURL: The URL of the audio file to import.
    /// - Returns: A tuple of the (possibly existing) ``LibraryEntry`` and its
    ///   folder URL, or `nil` if the copy failed.
    @discardableResult
    func importAudio(from sourceURL: URL) -> (entry: LibraryEntry, folder: URL)? {
        let audioName = sourceURL.lastPathComponent

        // Re-use an existing entry for the same audio file.
        if let existing = findEntry(byAudioName: audioName) {
            let folder = entryDirectory(for: existing)
            currentEntryId = existing.id
            return (existing, folder)
        }

        // Generate an 8-character id from a new UUID.
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        let now = Date()
        let folder = libraryDirectory.appendingPathComponent(id, isDirectory: true)

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(audioName)
            try fm.copyItem(at: sourceURL, to: destination)
        } catch {
            return nil
        }

        let title = sourceURL.deletingPathExtension().lastPathComponent
        var entry = LibraryEntry(
            id: id,
            title: title,
            audioFile: audioName,
            lyricsFile: nil,
            dateAdded: now,
            lastPlayed: now,
            originalAudioName: audioName
        )
        saveIndex(for: entry)

        // Keep entries sorted newest-first.
        entries.insert(entry, at: 0)
        currentEntryId = entry.id
        return (entry, folder)
    }

    /// Replaces the lyrics file for the current entry.
    ///
    /// The old lyrics file and any directive image files (all non-audio files
    /// in the entry folder) are removed before the new lyrics file and its
    /// referenced images are copied in.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL of the new lyrics file.
    ///   - directiveImagePaths: Relative image filenames referenced by directives
    ///     inside the lyrics file (e.g. background image names).
    ///   - imageSourceDir: The directory from which directive images are resolved.
    ///     Pass `nil` when no images need to be copied.
    func importLyrics(
        from sourceURL: URL,
        directiveImagePaths: [String],
        imageSourceDir: URL?
    ) {
        guard let entryId = currentEntryId,
              let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }

        var entry = entries[idx]
        let folder = entryDirectory(for: entry)
        let lyricsName = sourceURL.lastPathComponent
        let fm = FileManager.default

        // Remove stale directive images, keeping the audio file intact.
        cleanDirectiveImages(in: folder, keeping: entry.audioFile)

        // Copy the new lyrics file (overwrite if already present).
        let lyricsDestination = folder.appendingPathComponent(lyricsName)
        try? fm.removeItem(at: lyricsDestination)
        try? fm.copyItem(at: sourceURL, to: lyricsDestination)

        // Copy referenced directive images from the source directory.
        if let imageDir = imageSourceDir {
            for imagePath in directiveImagePaths {
                let imageSrc = imageDir.appendingPathComponent(imagePath)
                let imageDst = folder.appendingPathComponent(imagePath)
                // Create any intermediate sub-directories inside the entry folder.
                let imageSubDir = imageDst.deletingLastPathComponent()
                try? fm.createDirectory(at: imageSubDir, withIntermediateDirectories: true)
                try? fm.copyItem(at: imageSrc, to: imageDst)
            }
        }

        // Update and persist the entry.
        entry.lyricsFile = lyricsName
        saveIndex(for: entry)
        entries[idx] = entry
    }

    // MARK: - Cleanup

    /// Removes all non-audio files from the entry folder, preserving the audio
    /// file named `audioFilename` and the `index.json` metadata file.
    ///
    /// This is called before importing a fresh set of directive images so that
    /// stale images from a previous lyrics file do not accumulate.
    ///
    /// - Parameters:
    ///   - folder: The entry folder to clean.
    ///   - audioFilename: The audio filename to preserve.
    func cleanDirectiveImages(in folder: URL, keeping audioFilename: String) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        let preserved: Set<String> = [audioFilename, indexFileName]
        for item in contents where !preserved.contains(item.lastPathComponent) {
            try? fm.removeItem(at: item)
        }
    }

    // MARK: - Remove Entry

    /// Permanently deletes the entry folder from disk and removes the entry
    /// from ``entries``.
    ///
    /// If the deleted entry is the current one, ``currentEntryId`` is cleared.
    ///
    /// - Parameter id: The ``LibraryEntry/id`` of the entry to remove.
    func removeEntry(id: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[idx]
        let folder = entryDirectory(for: entry)
        try? FileManager.default.removeItem(at: folder)
        entries.remove(at: idx)
        if currentEntryId == id {
            currentEntryId = nil
        }
    }
}
