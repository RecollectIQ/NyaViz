//
//  InboxWatcher.swift
//  NyaViz
//

import AppKit
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
/// The folder is chosen by the user rather than fixed by the app.  NyaViz is
/// sandboxed, so a folder inside its container would be unreachable to the very
/// tools this feature exists for — macOS blocks other processes from reading or
/// writing an app's container.  Instead the user picks an ordinary folder once
/// (`~/Music/NyaViz Inbox`, say); the choice is persisted as a security-scoped
/// bookmark so access survives relaunches.
///
/// ```
/// <chosen folder>/
/// ├── README.md          # written when the folder is chosen; documents the contract
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

    // MARK: - Chosen Folder

    /// The folder currently being watched, or `nil` if the user has not picked one.
    @Published private(set) var inboxDirectory: URL?

    /// Whether an inbox folder is configured and accessible.
    var isConfigured: Bool { inboxDirectory != nil }

    /// Path shown in Settings, or a prompt when unset.
    var displayPath: String {
        inboxDirectory?.path ?? "Choose a folder…"
    }

    private let bookmarkDefaultsKey = "inboxFolderBookmark"

    /// Tracks whether we currently hold security-scoped access, so it is
    /// released exactly once.
    private var isAccessingScope = false

    private func processedDirectory(in folder: URL) -> URL {
        folder.appendingPathComponent(".processed", isDirectory: true)
    }

    private func statusFileURL(in folder: URL) -> URL {
        folder.appendingPathComponent("status.json")
    }

    private func readmeURL(in folder: URL) -> URL {
        folder.appendingPathComponent("README.md")
    }

    /// Names that are inbox infrastructure rather than droppable content.
    private var reservedNames: Set<String> {
        ["README.md", "status.json", ".processed", ".DS_Store"]
    }

    // MARK: - Lifecycle

    /// Wires up dependencies and resumes watching the previously chosen folder,
    /// if there is one.  Does nothing visible until the user picks a folder.
    func start(library: LibraryManager, audioPlayer: AudioPlayerManager) {
        self.library = library
        self.audioPlayer = audioPlayer
        restoreSavedFolder()
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        releaseScope()
    }

    deinit {
        source?.cancel()
    }

    // MARK: - Folder Selection

    /// Asks the user to pick the inbox folder, then persists and starts watching it.
    ///
    /// The sandbox grants access to whatever the user selects in the panel; the
    /// security-scoped bookmark is what makes that access survive a relaunch.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Inbox"
        panel.message = "Choose a folder for agents and scripts to drop tracks and lyrics into."
        panel.directoryURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        adopt(folder, persistBookmark: true)
    }

    /// Stops watching and forgets the chosen folder. Files already imported into
    /// the library are unaffected.
    func clearFolder() {
        stop()
        inboxDirectory = nil
        reportedFailures.removeAll()
        UserDefaults.standard.removeObject(forKey: bookmarkDefaultsKey)
    }

    /// Re-opens the folder the user chose in a previous session.
    private func restoreSavedFolder() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else { return }

        var isStale = false
        guard let folder = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            // The folder was deleted or moved beyond recovery.
            UserDefaults.standard.removeObject(forKey: bookmarkDefaultsKey)
            return
        }

        // A stale bookmark still resolves, but needs re-minting to keep working.
        adopt(folder, persistBookmark: isStale)
    }

    /// Begins using `folder` as the inbox.
    private func adopt(_ folder: URL, persistBookmark: Bool) {
        stop()

        guard folder.startAccessingSecurityScopedResource() else { return }
        isAccessingScope = true
        inboxDirectory = folder

        if persistBookmark,
           let data = try? folder.bookmarkData(
               options: [.withSecurityScope],
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            UserDefaults.standard.set(data, forKey: bookmarkDefaultsKey)
        }

        prepareDirectory(folder)
        beginWatching(folder)

        // Pick up anything written while the app was closed.
        scheduleScan()
    }

    private func releaseScope() {
        if isAccessingScope, let folder = inboxDirectory {
            folder.stopAccessingSecurityScopedResource()
        }
        isAccessingScope = false
    }

    // MARK: - Setup

    private func prepareDirectory(_ folder: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: processedDirectory(in: folder), withIntermediateDirectories: true)

        // Write the contract next to the folder it describes, so an agent that
        // finds the directory can discover how to use it without other docs.
        let readme = readmeURL(in: folder)
        if !fm.fileExists(atPath: readme.path) {
            try? Self.readmeContents.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    private func beginWatching(_ folder: URL) {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil

        descriptor = open(folder.path, O_EVTONLY)
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
        guard let folder = inboxDirectory else { return }
        let fm = FileManager.default
        // Skipping hidden files keeps `.processed/`, `.DS_Store` and AppleDouble
        // `._` stubs from being mistaken for drops.
        guard let contents = try? fm.contentsOfDirectory(
            at: folder,
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
            recordStatus(results, in: folder)
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
        guard let folder = inboxDirectory else { return }
        let processed = processedDirectory(in: folder)
        let fm = FileManager.default
        var destination = processed.appendingPathComponent(drop.lastPathComponent)

        // Never clobber an earlier drop of the same name.
        if fm.fileExists(atPath: destination.path) {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let base = drop.deletingPathExtension().lastPathComponent
            let ext = drop.pathExtension
            let unique = ext.isEmpty ? "\(base) \(stamp)" : "\(base) \(stamp).\(ext)"
            destination = processed.appendingPathComponent(unique)
        }
        try? fm.moveItem(at: drop, to: destination)
    }

    // MARK: - Status Reporting

    /// Appends results to `status.json` so the writer can confirm what happened.
    private func recordStatus(_ results: [ImportResult], in folder: URL) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let statusURL = statusFileURL(in: folder)
        var history: [ImportResult] = []
        if let data = try? Data(contentsOf: statusURL),
           let existing = try? decoder.decode(StatusFile.self, from: data) {
            history = existing.results
        }
        history.append(contentsOf: results)
        if history.count > statusHistoryLimit {
            history.removeFirst(history.count - statusHistoryLimit)
        }

        let file = StatusFile(updated: Date(), results: history)
        if let data = try? encoder.encode(file) {
            try? data.write(to: statusURL, options: .atomic)
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

    NyaViz is sandboxed, so this folder is one you chose rather than a fixed
    path inside the app's container — the container is not reachable by other
    processes. Settings -> Files -> Copy Inbox Path gives you the current
    location; Change Inbox Folder moves it.

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
