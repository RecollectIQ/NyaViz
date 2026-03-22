# Playlist / Library Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a persistent song library that auto-saves opened songs and lets users switch between them via a bottom drawer UI.

**Architecture:** A `LibraryManager` handles file copying, JSON persistence, and entry CRUD. `AudioPlayerManager` calls into it on file open. A `LibraryDrawerView` provides the bottom drawer UI. All files are copied into `~/Library/Application Support/NyaViz/Library/<uuid>/` so the library is self-contained.

**Tech Stack:** SwiftUI, Foundation (FileManager, JSONEncoder/Decoder), existing AudioPlayerManager/SettingsManager

**Design doc:** `docs/plans/2026-03-22-playlist-library-design.md`

---

### Task 1: LibraryEntry Model

**Files:**
- Create: `NyaViz/Models/LibraryEntry.swift`

**Step 1: Create the model**

```swift
import Foundation

struct LibraryEntry: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var audioFile: String        // filename within entry folder
    var lyricsFile: String?      // filename within entry folder (optional, replaceable)
    var dateAdded: Date
    var lastPlayed: Date

    /// The original audio filename used for duplicate detection
    var originalAudioName: String
}
```

**Step 2: Commit**

```
git add NyaViz/Models/LibraryEntry.swift
git commit -m "feat: add LibraryEntry model for playlist persistence"
```

---

### Task 2: LibraryManager — Core Storage

**Files:**
- Create: `NyaViz/Managers/LibraryManager.swift`

**Step 1: Create LibraryManager with directory setup and JSON persistence**

```swift
import Foundation
import AppKit

@MainActor
class LibraryManager: ObservableObject {
    @Published var entries: [LibraryEntry] = []
    @Published var currentEntryId: String?

    private let fileManager = FileManager.default

    /// Root library directory: ~/Library/Application Support/NyaViz/Library/
    var libraryDirectory: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("NyaViz/Library", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexURL: URL? {
        libraryDirectory?.appendingPathComponent("library.json")
    }

    init() {
        loadIndex()
    }

    // MARK: - Index Persistence

    func loadIndex() {
        guard let url = indexURL, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([LibraryEntry].self, from: data)) ?? []
    }

    func saveIndex() {
        guard let url = indexURL else { return }
        let encoder = JSONEncoder()
        encoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url)
    }

    /// Directory for a specific entry
    func entryDirectory(for id: String) -> URL? {
        libraryDirectory?.appendingPathComponent(id, isDirectory: true)
    }

    // MARK: - Find Existing Entry

    /// Find entry by original audio filename
    func findEntry(byAudioName name: String) -> LibraryEntry? {
        entries.first { $0.originalAudioName == name }
    }
}
```

**Step 2: Commit**

```
git add NyaViz/Managers/LibraryManager.swift
git commit -m "feat: add LibraryManager with directory setup and JSON index"
```

---

### Task 3: LibraryManager — Add/Remove/Update Operations

**Files:**
- Modify: `NyaViz/Managers/LibraryManager.swift`

**Step 1: Add audio import method**

Add to LibraryManager:

```swift
    // MARK: - Audio Import

    /// Add or find an audio file in the library. Returns the entry and its folder URL.
    func importAudio(from sourceURL: URL) -> (entry: LibraryEntry, folder: URL)? {
        let audioName = sourceURL.lastPathComponent
        let title = sourceURL.deletingPathExtension().lastPathComponent

        // Check for existing entry
        if let existing = findEntry(byAudioName: audioName),
           let folder = entryDirectory(for: existing.id) {
            // Update last played
            if let idx = entries.firstIndex(where: { $0.id == existing.id }) {
                entries[idx].lastPlayed = Date()
                saveIndex()
            }
            currentEntryId = existing.id
            return (existing, folder)
        }

        // Create new entry
        let id = UUID().uuidString.prefix(8).lowercased()
        let entryId = String(id)
        guard let folder = entryDirectory(for: entryId) else { return nil }

        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let destAudio = folder.appendingPathComponent(audioName)
            try fileManager.copyItem(at: sourceURL, to: destAudio)
        } catch {
            print("[Library] Failed to copy audio: \(error)")
            return nil
        }

        let entry = LibraryEntry(
            id: entryId,
            title: title,
            audioFile: audioName,
            lyricsFile: nil,
            dateAdded: Date(),
            lastPlayed: Date(),
            originalAudioName: audioName
        )
        entries.append(entry)
        currentEntryId = entryId
        saveIndex()
        print("[Library] Added new entry: \(title) (\(entryId))")
        return (entry, folder)
    }
```

**Step 2: Add lyrics import method**

```swift
    // MARK: - Lyrics Import

    /// Import lyrics (and directive images) into the current entry, replacing any existing lyrics.
    func importLyrics(from sourceURL: URL, directiveImagePaths: [String], imageSourceDir: URL?) {
        guard let entryId = currentEntryId,
              let idx = entries.firstIndex(where: { $0.id == entryId }),
              let folder = entryDirectory(for: entryId) else { return }

        // Remove old lyrics and old directive images
        if let oldLyrics = entries[idx].lyricsFile {
            try? fileManager.removeItem(at: folder.appendingPathComponent(oldLyrics))
        }
        // Remove any images that aren't the audio file or meta
        cleanDirectiveImages(in: folder, keeping: entries[idx].audioFile)

        // Copy new lyrics
        let lyricsName = sourceURL.lastPathComponent
        let destLyrics = folder.appendingPathComponent(lyricsName)
        try? fileManager.removeItem(at: destLyrics) // remove if exists
        do {
            try fileManager.copyItem(at: sourceURL, to: destLyrics)
        } catch {
            print("[Library] Failed to copy lyrics: \(error)")
            return
        }

        // Copy directive images
        if let srcDir = imageSourceDir {
            for imagePath in directiveImagePaths {
                let srcImage = srcDir.appendingPathComponent(imagePath)
                let destImage = folder.appendingPathComponent(imagePath)
                if !fileManager.fileExists(atPath: destImage.path) {
                    try? fileManager.copyItem(at: srcImage, to: destImage)
                }
            }
        }

        entries[idx].lyricsFile = lyricsName
        saveIndex()
        print("[Library] Updated lyrics for entry \(entryId): \(lyricsName)")
    }

    /// Remove non-audio files from entry folder (old directive images)
    private func cleanDirectiveImages(in folder: URL, keeping audioFile: String) {
        guard let contents = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            let name = file.lastPathComponent
            if name != audioFile && name != "meta.json" {
                try? fileManager.removeItem(at: file)
            }
        }
    }
```

**Step 3: Add remove and load methods**

```swift
    // MARK: - Remove Entry

    func removeEntry(id: String) {
        entries.removeAll { $0.id == id }
        if let folder = entryDirectory(for: id) {
            try? fileManager.removeItem(at: folder)
        }
        if currentEntryId == id {
            currentEntryId = nil
        }
        saveIndex()
    }

    // MARK: - Load Entry

    /// Get the audio URL for an entry
    func audioURL(for entry: LibraryEntry) -> URL? {
        entryDirectory(for: entry.id)?.appendingPathComponent(entry.audioFile)
    }

    /// Get the lyrics URL for an entry
    func lyricsURL(for entry: LibraryEntry) -> URL? {
        guard let lyricsFile = entry.lyricsFile else { return nil }
        return entryDirectory(for: entry.id)?.appendingPathComponent(lyricsFile)
    }
```

**Step 4: Commit**

```
git add NyaViz/Managers/LibraryManager.swift
git commit -m "feat: add audio/lyrics import, remove, and load to LibraryManager"
```

---

### Task 4: Wire LibraryManager Into App Lifecycle

**Files:**
- Modify: `NyaViz/NyaVizApp.swift` — add LibraryManager as @StateObject and environmentObject
- Modify: `NyaViz/Managers/AudioPlayerManager.swift` — add weak ref to LibraryManager

**Step 1: Add LibraryManager to NyaVizApp**

In `NyaVizApp.swift`, add alongside the existing `@StateObject` declarations:
```swift
@StateObject private var libraryManager = LibraryManager()
```

Pass it as environmentObject on ContentView (alongside existing ones):
```swift
.environmentObject(libraryManager)
```

In the `.task` block that sets `settingsRef`, also set:
```swift
audioPlayer.libraryRef = libraryManager
```

**Step 2: Add libraryRef to AudioPlayerManager**

In `AudioPlayerManager.swift`, add property near `settingsRef`:
```swift
/// Reference to library for auto-adding songs
weak var libraryRef: LibraryManager?
```

**Step 3: Commit**

```
git add NyaViz/NyaVizApp.swift NyaViz/Managers/AudioPlayerManager.swift
git commit -m "feat: wire LibraryManager into app lifecycle"
```

---

### Task 5: Auto-Add on Audio Open

**Files:**
- Modify: `NyaViz/Managers/AudioPlayerManager.swift` — update `loadAudio(from:)` to auto-import
- Modify: `NyaViz/Views/SettingsPanelView.swift` — after opening audio, also load saved lyrics

**Step 1: Update loadAudio to auto-import and load saved lyrics**

In `AudioPlayerManager.loadAudio(from:)`, after the existing audio loading succeeds (after `setupAudioEngine()`), add:

```swift
// Auto-add to library
if let library = libraryRef {
    if let (entry, _) = library.importAudio(from: url) {
        // If entry already has lyrics, load them automatically
        if let lyricsURL = library.lyricsURL(for: entry) {
            loadSRT(from: lyricsURL)
        }
    }
}
```

**Step 2: Commit**

```
git add NyaViz/Managers/AudioPlayerManager.swift
git commit -m "feat: auto-add audio to library on open, load saved lyrics"
```

---

### Task 6: Auto-Save Lyrics on Open

**Files:**
- Modify: `NyaViz/Managers/AudioPlayerManager.swift` — update `loadSRT(from:)` to save lyrics to library

**Step 1: Update loadSRT to import lyrics into library**

At the end of `loadSRT(from:)`, after the existing print statement, add:

```swift
// Save lyrics to library
if let library = libraryRef {
    let imagePaths = directives.compactMap { d -> String? in
        if case .background(let path) = d.type { return path }
        return nil
    }
    library.importLyrics(
        from: url,
        directiveImagePaths: imagePaths,
        imageSourceDir: nyavizBaseDirectory
    )
}
```

**Step 2: Commit**

```
git add NyaViz/Managers/AudioPlayerManager.swift
git commit -m "feat: auto-save lyrics and directive images to library on open"
```

---

### Task 7: LibraryDrawerView — Bottom Drawer UI

**Files:**
- Create: `NyaViz/Views/LibraryDrawerView.swift`

**Step 1: Create the drawer view**

Build a bottom drawer with:
- Collapsed: pill handle at bottom center
- Expanded: translucent dark blur list of songs
- Click to switch, swipe to delete
- Highlight current song
- Matches existing app aesthetic (dark, blur, white text)

Key implementation details:
- `@EnvironmentObject var library: LibraryManager`
- `@EnvironmentObject var audioPlayer: AudioPlayerManager`
- `@State private var isExpanded = false`
- Expanded height: ~40% of container
- Animation: `.spring(response: 0.4, dampingFraction: 0.85)`
- Each row: title (left), lyrics icon if present (center-right), relative date (right)
- Active entry has white background at 0.1 opacity
- Delete via `.onDelete` or swipe gesture

**Step 2: Add switchToEntry method on AudioPlayerManager**

Add to `AudioPlayerManager.swift`:

```swift
/// Load a library entry (audio + lyrics)
func loadLibraryEntry(_ entry: LibraryEntry) {
    guard let library = libraryRef else { return }

    // Load audio
    if let audioURL = library.audioURL(for: entry) {
        loadAudio(from: audioURL)
    }

    // Load lyrics if present
    if let lyricsURL = library.lyricsURL(for: entry) {
        loadSRT(from: lyricsURL)
    }

    library.currentEntryId = entry.id
}
```

**Step 3: Commit**

```
git add NyaViz/Views/LibraryDrawerView.swift NyaViz/Managers/AudioPlayerManager.swift
git commit -m "feat: add LibraryDrawerView bottom drawer and song switching"
```

---

### Task 8: Integrate Drawer Into ContentView

**Files:**
- Modify: `NyaViz/ContentView.swift` — add LibraryDrawerView

**Step 1: Add the drawer**

In `ContentView.swift`, add the drawer inside the main ZStack, after the settings panel and before the closing brace. It should appear in both fullscreen and normal modes:

```swift
// Library drawer at bottom
LibraryDrawerView()
```

Position it at the bottom of the ZStack with appropriate alignment.

In fullscreen mode, it should sit above the floating controls area.

**Step 2: Commit**

```
git add NyaViz/ContentView.swift
git commit -m "feat: integrate library drawer into ContentView"
```

---

### Task 9: Prevent Duplicate Library Import for Library-Loaded Songs

**Files:**
- Modify: `NyaViz/Managers/AudioPlayerManager.swift`

**Step 1: Skip library import when loading from library**

Add a flag to AudioPlayerManager:
```swift
/// When true, skip auto-importing to library (we're already loading FROM the library)
private var isLoadingFromLibrary = false
```

Set it in `loadLibraryEntry`:
```swift
func loadLibraryEntry(_ entry: LibraryEntry) {
    isLoadingFromLibrary = true
    defer { isLoadingFromLibrary = false }
    // ... existing code
}
```

Guard the auto-import code in `loadAudio` and `loadSRT` with:
```swift
guard !isLoadingFromLibrary else { return }
```
(around the library import sections only, not the actual loading)

**Step 2: Commit**

```
git add NyaViz/Managers/AudioPlayerManager.swift
git commit -m "fix: prevent duplicate import when loading from library"
```

---

### Task 10: Build, Test, and Final Commit

**Step 1: Build**
```
xcodebuild -scheme NyaViz -configuration Debug build
```

**Step 2: Manual test checklist**
- Open an audio file → appears in library drawer
- Open lyrics for it → lyrics indicator shows in drawer
- Close and reopen app → library persists, songs listed
- Click a song in drawer → loads audio + lyrics
- Open same audio again → loads existing entry (not duplicate)
- Open different lyrics for same audio → replaces lyrics in drawer
- Swipe to delete → removes entry
- Fullscreen mode → drawer works over floating controls

**Step 3: Final commit if needed**

```
git add -A
git commit -m "feat: complete playlist/library feature"
```
