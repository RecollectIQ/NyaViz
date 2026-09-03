//
//  LibraryRenameTests.swift
//  NyaVizTests
//

import Foundation
import Testing
@testable import NyaViz

/// Covers renaming a library entry, which backs double-click-to-rename on the
/// full-screen track title.
///
/// These run against the real library directory, so every test imports an entry
/// under a unique name and removes it again before returning.
@MainActor
struct LibraryRenameTests {

    /// Imports a throwaway entry and hands back its id plus a cleanup closure.
    private func makeEntry(_ label: String) throws -> (library: LibraryManager, id: String) {
        let library = LibraryManager()
        let name = "nyaviz-test-\(label)-\(UUID().uuidString.prefix(8)).aiff"
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data("not really audio".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let imported = try #require(library.importAudio(from: source, setCurrent: false))
        return (library, imported.entry.id)
    }

    /// Reads the title straight back off disk, so the assertion covers
    /// persistence rather than just the in-memory array.
    private func persistedTitle(_ library: LibraryManager, _ id: String) throws -> String {
        let url = library.libraryDirectory
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("index.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryEntry.self, from: Data(contentsOf: url)).title
    }

    @Test func renamePersistsToDisk() throws {
        let (library, id) = try makeEntry("rename")
        defer { library.removeEntry(id: id) }

        #expect(library.renameEntry(id: id, to: "Bound to Break"))
        #expect(library.entries.first { $0.id == id }?.title == "Bound to Break")
        #expect(try persistedTitle(library, id) == "Bound to Break")
    }

    @Test func renameTrimsSurroundingWhitespace() throws {
        let (library, id) = try makeEntry("trim")
        defer { library.removeEntry(id: id) }

        #expect(library.renameEntry(id: id, to: "   Confess \n"))
        #expect(library.entries.first { $0.id == id }?.title == "Confess")
    }

    /// An entry must never become nameless, so blank titles are refused rather
    /// than written.
    @Test func renameRejectsBlankTitles() throws {
        let (library, id) = try makeEntry("blank")
        defer { library.removeEntry(id: id) }

        let original = try #require(library.entries.first { $0.id == id }?.title)

        #expect(library.renameEntry(id: id, to: "") == false)
        #expect(library.renameEntry(id: id, to: "    ") == false)
        #expect(library.entries.first { $0.id == id }?.title == original)
        #expect(try persistedTitle(library, id) == original)
    }

    /// De-duplication keys off the original audio filename, so renaming must not
    /// disturb it — otherwise re-opening the same file would create a duplicate.
    @Test func renameLeavesFilenamesAlone() throws {
        let (library, id) = try makeEntry("filenames")
        defer { library.removeEntry(id: id) }

        let before = try #require(library.entries.first { $0.id == id })
        #expect(library.renameEntry(id: id, to: "A Much Nicer Name"))
        let after = try #require(library.entries.first { $0.id == id })

        #expect(after.originalAudioName == before.originalAudioName)
        #expect(after.audioFile == before.audioFile)
        #expect(library.findEntry(byAudioName: before.originalAudioName)?.id == id)
    }

    @Test func renameIgnoresUnknownEntries() throws {
        let library = LibraryManager()
        #expect(library.renameEntry(id: "no-such-entry", to: "Whatever") == false)
    }

    @Test func currentEntryFollowsCurrentEntryId() throws {
        let (library, id) = try makeEntry("current")
        defer { library.removeEntry(id: id) }

        #expect(library.currentEntry == nil)
        library.currentEntryId = id
        #expect(library.currentEntry?.id == id)
    }
}
