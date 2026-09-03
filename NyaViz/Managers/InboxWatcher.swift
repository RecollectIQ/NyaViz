//
//  InboxWatcher.swift
//  NyaViz
//

import Foundation
import Combine

/// Watches the agent drop-folder and imports anything written into it.
///
/// The inbox exists so that an external tool — a script, or an AI agent with
/// filesystem access — can add tracks and lyrics to NyaViz without driving the
/// UI.  The contract is deliberately forgiving: drop a folder containing an
/// audio file and/or a `.nyaviz`/`.srt` file and it gets imported.  No manifest,
/// no JSON, no fixed filenames.
///
/// ```
/// ~/Library/Application Support/NyaViz/Inbox/
/// ├── README.md          # written on first launch; documents the contract
/// ├── status.json        # append-only log of import results
/// ├── .processed/        # successfully imported drops are moved here
/// └── My Song/           # a drop
///     ├── my-song.mp3
///     ├── my-song.nyaviz
///     └── backdrop.jpg
/// ```
///
/// Imports are only attempted once a drop has been *settled* for
/// ``settleInterval`` seconds, so a file still being written is never picked up
/// half-finished.
@MainActor
final class InboxWatcher: ObservableObject {

    // MARK: - Tuning

    /// How long a drop must sit unmodified before it is considered complete.
    private let settleInterval: TimeInterval = 2.0

    /// How long to coalesce filesystem events before scanning.
    private let debounceInterval: TimeInterval = 1.0

    /// Number of results retained in `status.json`.
    private let statusHistoryLimit = 50

    /// File extensions treated as audio and as lyrics.
    private let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aiff", "aif", "caf", "flac", "aac", "alac", "mp4"
    ]
    private let lyricsExtensions: Set<String> = ["nyaviz", "srt"]

    // MARK: - Dependencies

    private weak var library: LibraryManager?
    private weak var audioPlayer: AudioPlayerManager?

    // MARK: - Watcher State

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var debounceTask: Task<Void, Never>?

    /// Drops that were skipped or failed, keyed by path, with the modification
    /// date at the time they were reported.
    ///
    /// Unimportable drops stay in the inbox so they can be corrected, which means
    /// every later scan sees them again.  Without this, a single bad file would
    /// append a duplicate result to `status.json` on every filesystem event.  A
    /// drop is retried — and reported again — once it changes on disk.
    private var reportedFailures: [String: Date] = [:]

    // MARK: - Paths

    /// `~/Library/Application Support/NyaViz/Inbox/`
    ///
    /// Derived from the same base as ``LibraryManager/libraryDirectory`` so the
    /// two stay together if the app is ever sandboxed into a container.
    var inboxDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("NyaViz", isDirectory: true)
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    private var processedDirectory: URL {
        inboxDirectory.appendingPathComponent(".processed", isDirectory: true)
    }

    private var statusFileURL: URL {
        inboxDirectory.appendingPathComponent("status.json")
    }

    private var readmeURL: URL {
        inboxDirectory.appendingPathComponent("README.md")
    }

    /// Names that are inbox infrastructure rather than droppable content.
    private var reservedNames: Set<String> {
        ["README.md", "status.json", ".processed", ".DS_Store"]
    }

    // MARK: - Lifecycle

    /// Creates the inbox if needed, imports anything already sitting in it, and
    /// begins watching for new drops.
    func start(library: LibraryManager, audioPlayer: AudioPlayerManager) {
        self.library = library
        self.audioPlayer = audioPlayer

        prepareDirectory()
        beginWatching()

        // Pick up anything written while the app was closed.
        scheduleScan()
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }

    // MARK: - Setup

    private func prepareDirectory() {
        let fm = FileManager.default
        try? fm.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: processedDirectory, withIntermediateDirectories: true)

        // Write the contract next to the folder it describes, so an agent that
        // finds the directory can discover how to use it without other docs.
        if !fm.fileExists(atPath: readmeURL.path) {
            try? Self.readmeContents.write(to: readmeURL, atomically: true, encoding: .utf8)
        }
    }

    private func beginWatching() {
        stop()

        descriptor = open(inboxDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleScan() }
        }
        let fd = descriptor
        source.setCancelHandler {
            if fd >= 0 { close(fd) }
        }
        source.resume()
        self.source = source
    }

    // MARK: - Scanning

    /// Coalesces bursts of filesystem events into a single scan.
    private func scheduleScan(after delay: TimeInterval? = nil) {
        debounceTask?.cancel()
        let wait = delay ?? debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    private func scan() {
        let fm = FileManager.default
        // Skipping hidden files keeps `.processed/`, `.DS_Store` and AppleDouble
        // `._` stubs from being mistaken for drops.
        guard let contents = try? fm.contentsOfDirectory(
            at: inboxDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let drops = contents.filter { !reservedNames.contains($0.lastPathComponent) }
        guard !drops.isEmpty else { return }

        var results: [ImportResult] = []
        var sawUnsettled = false

        for drop in drops {
            guard isSettled(drop) else {
                sawUnsettled = true
                continue
            }

            let modified = mostRecentModification(of: drop)
            if let lastReported = reportedFailures[drop.path],
               let modified, modified <= lastReported {
                continue  // Already reported, and unchanged since.
            }

            let result = process(drop)
            if result.status == .imported {
                reportedFailures.removeValue(forKey: drop.path)
            } else {
                reportedFailures[drop.path] = modified ?? Date()
            }
            results.append(result)
        }

        if !results.isEmpty {
            recordStatus(results)
        }

        // A directory event does not fire for writes *inside* a sub-folder, so
        // poll again while a drop is still being written. Polling stops as soon
        // as everything has settled.
        if sawUnsettled {
            scheduleScan(after: settleInterval)
        }
    }

    /// True once nothing inside the drop has been modified for ``settleInterval``.
    private func isSettled(_ url: URL) -> Bool {
        guard let newest = mostRecentModification(of: url) else { return false }
        return Date().timeIntervalSince(newest) >= settleInterval
    }

    private func mostRecentModification(of url: URL) -> Date? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]

        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        var newest = values.contentModificationDate

        if values.isDirectory == true,
           let walker = fm.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let child as URL in walker {
                guard let childValues = try? child.resourceValues(forKeys: Set(keys)),
                      let modified = childValues.contentModificationDate else { continue }
                if newest == nil || modified > newest! {
                    newest = modified
                }
            }
        }
        return newest
    }

    // MARK: - Importing

    /// Imports one drop (a folder, or a single loose file) and reports what happened.
    private func process(_ drop: URL) -> ImportResult {
        let name = drop.lastPathComponent
        guard let library else {
            return ImportResult(source: name, status: .failed, message: "Library unavailable")
        }

        let files = filesIn(drop)
        let audio = files.first { audioExtensions.contains($0.pathExtension.lowercased()) }
        let lyrics = files.first { lyricsExtensions.contains($0.pathExtension.lowercased()) }

        if audio == nil && lyrics == nil {
            return ImportResult(
                source: name,
                status: .skipped,
                message: "No audio or lyrics file found. Expected one of \(formatList(audioExtensions)) or \(formatList(lyricsExtensions))."
            )
        }

        // Case 1 — a new track (audio, optionally with lyrics).
        if let audio {
            guard let (entry, _) = library.importAudio(from: audio, setCurrent: false) else {
                return ImportResult(source: name, status: .failed, message: "Could not copy \(audio.lastPathComponent)")
            }
            var attachedLyrics = false
            if let lyrics {
                attachedLyrics = attach(lyrics, to: entry.id, from: drop, library: library)
            }
            archive(drop)
            return ImportResult(
                source: name,
                status: .imported,
                trackId: entry.id,
                title: entry.title,
                lyricsAttached: attachedLyrics
            )
        }

        // Case 2 — lyrics only: attach them to an existing track matched by filename.
        guard let lyrics else {
            return ImportResult(source: name, status: .failed, message: "Unreachable")
        }
        let stem = lyrics.deletingPathExtension().lastPathComponent
        guard let match = matchEntry(forStem: stem, in: library) else {
            return ImportResult(
                source: name,
                status: .failed,
                message: "No library track matches \"\(stem)\". Drop the audio file alongside the lyrics to add a new track."
            )
        }

        let attached = attach(lyrics, to: match.id, from: drop, library: library)
        guard attached else {
            return ImportResult(source: name, status: .failed, trackId: match.id, message: "Could not write lyrics")
        }
        archive(drop)
        return ImportResult(
            source: name,
            status: .imported,
            trackId: match.id,
            title: match.title,
            lyricsAttached: true
        )
    }

    /// Copies a lyrics file (plus any background images its directives reference)
    /// into the target entry, and refreshes playback if that track is on screen.
    private func attach(_ lyrics: URL, to entryId: String, from drop: URL, library: LibraryManager) -> Bool {
        let imagePaths = SubtitleLoader.loadWithDirectives(from: lyrics).directives
            .compactMap { directive -> String? in
                if case .background(let path) = directive.type { return path }
                return nil
            }

        let written = library.importLyrics(
            from: lyrics,
            into: entryId,
            directiveImagePaths: imagePaths,
            imageSourceDir: lyrics.deletingLastPathComponent()
        )
        guard written else { return false }

        // If the user is listening to this track right now, show the new lyrics
        // immediately rather than on the next load.
        if library.currentEntryId == entryId,
           let entry = library.entries.first(where: { $0.id == entryId }),
           let lyricsURL = library.lyricsURL(for: entry) {
            audioPlayer?.reloadLyricsFromLibrary(at: lyricsURL)
        }
        return true
    }

    /// Finds the library entry whose title or original filename matches `stem`.
    private func matchEntry(forStem stem: String, in library: LibraryManager) -> LibraryEntry? {
        let needle = stem.lowercased()
        return library.entries.first { entry in
            entry.title.lowercased() == needle
                || (entry.originalAudioName as NSString).deletingPathExtension.lowercased() == needle
        }
    }

    /// Every file in the drop — the drop itself if it is a single loose file.
    private func filesIn(_ drop: URL) -> [URL] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: drop.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [drop] }

        let contents = (try? fm.contentsOfDirectory(
            at: drop,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Moves a successfully imported drop into `.processed/`.
    ///
    /// The library keeps its own copy, so the original is redundant — but songs
    /// are small and silently deleting someone's files is worse than a folder
    /// they can empty themselves.
    private func archive(_ drop: URL) {
        let fm = FileManager.default
        var destination = processedDirectory.appendingPathComponent(drop.lastPathComponent)

        // Never clobber an earlier drop of the same name.
        if fm.fileExists(atPath: destination.path) {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let base = drop.deletingPathExtension().lastPathComponent
            let ext = drop.pathExtension
            let unique = ext.isEmpty ? "\(base) \(stamp)" : "\(base) \(stamp).\(ext)"
            destination = processedDirectory.appendingPathComponent(unique)
        }
        try? fm.moveItem(at: drop, to: destination)
    }

    // MARK: - Status Reporting

    /// Appends results to `status.json` so the writer can confirm what happened.
    private func recordStatus(_ results: [ImportResult]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var history: [ImportResult] = []
        if let data = try? Data(contentsOf: statusFileURL),
           let existing = try? decoder.decode(StatusFile.self, from: data) {
            history = existing.results
        }
        history.append(contentsOf: results)
        if history.count > statusHistoryLimit {
            history.removeFirst(history.count - statusHistoryLimit)
        }

        let file = StatusFile(updated: Date(), results: history)
        if let data = try? encoder.encode(file) {
            try? data.write(to: statusFileURL, options: .atomic)
        }

        for result in results {
            print("[Inbox] \(result.status.rawValue): \(result.source)\(result.message.map { " — \($0)" } ?? "")")
        }
    }

    private func formatList(_ extensions: Set<String>) -> String {
        extensions.sorted().map { ".\($0)" }.joined(separator: ", ")
    }
}

// MARK: - Status Types

extension InboxWatcher {

    /// The outcome of importing a single drop.
    struct ImportResult: Codable {
        enum Status: String, Codable {
            /// Added to the library; the drop was moved to `.processed/`.
            case imported
            /// Nothing importable in the drop; it was left in place.
            case skipped
            /// Import was attempted and did not succeed; the drop was left in place.
            case failed
        }

        var time: Date = Date()
        /// The name of the dropped folder or file.
        let source: String
        let status: Status
        /// The library entry id, when one was created or matched.
        var trackId: String?
        var title: String?
        var lyricsAttached: Bool = false
        /// Why the drop was skipped or failed.
        var message: String?

        init(
            source: String,
            status: Status,
            trackId: String? = nil,
            title: String? = nil,
            lyricsAttached: Bool = false,
            message: String? = nil
        ) {
            self.source = source
            self.status = status
            self.trackId = trackId
            self.title = title
            self.lyricsAttached = lyricsAttached
            self.message = message
        }
    }

    struct StatusFile: Codable {
        let updated: Date
        let results: [ImportResult]
    }
}

// MARK: - README

extension InboxWatcher {

    static let readmeContents = """
    # NyaViz Inbox

    Anything written into this folder is imported into the NyaViz library
    automatically. This is the supported way for scripts and agents to add
    tracks and lyrics without driving the app's UI.

    ## Adding a track

    Create a folder here containing the audio file, and optionally a lyrics
    file and any background images its directives reference:

        Inbox/
        └── My Song/
            ├── my-song.mp3
            ├── my-song.nyaviz
            └── backdrop.jpg

    Filenames do not matter — files are identified by extension.

    - Audio: .mp3 .m4a .wav .aiff .aif .caf .flac .aac .alac .mp4
    - Lyrics: .nyaviz .srt

    A single loose file dropped directly in this folder works too.

    ## Adding lyrics to a track already in the library

    Drop just the lyrics file. It is matched to an existing track by filename,
    so `Killings.nyaviz` attaches to the track titled `Killings`. If that track
    is playing at the time, the new lyrics appear immediately.

    If no track matches, the file is left here and the reason is recorded in
    `status.json`.

    ## Confirming the import

    Every attempt is appended to `status.json`:

        {
          "updated": "2026-09-03T12:00:00Z",
          "results": [
            {
              "time": "2026-09-03T12:00:00Z",
              "source": "My Song",
              "status": "imported",
              "trackId": "a1b2c3d4",
              "title": "my-song",
              "lyricsAttached": true
            }
          ]
        }

    `status` is one of `imported`, `skipped` or `failed`; the latter two carry a
    `message` explaining why.

    ## Notes

    - A drop is only imported once nothing inside it has changed for 2 seconds,
      so a partially written file is never picked up. Write your files, then
      leave them alone.
    - Imported drops are moved to `.processed/`. The library holds its own copy,
      so `.processed/` can be emptied at any time.
    - Drops that were skipped or failed stay here so they can be corrected.
    - The `.nyaviz` lyrics format is documented in NYAVIZ.md in the project repo.
    """
}
