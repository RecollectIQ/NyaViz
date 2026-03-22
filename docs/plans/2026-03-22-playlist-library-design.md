# Playlist / Library Feature Design

## Overview

Add a persistent song library to NyaViz so users don't have to re-open files every session. Songs are auto-added when opened, stored self-contained in the app support directory, and browsable via a bottom drawer UI.

## Storage

Each song is a folder inside `~/Library/Application Support/NyaViz/Library/<uuid>/`:

```
Library/
├── library.json              # index of all entries
├── a1b2c3d4/
│   ├── meta.json             # title, audio/lyrics filenames, dates
│   ├── audio.wav             # copied audio file
│   ├── lyrics.nyaviz         # copied lyrics (optional, replaceable)
│   ├── wallhaven-exkqk8.jpg  # copied directive images
│   └── wallhaven-3qwmz3.jpg
├── e5f6g7h8/
│   ├── meta.json
│   ├── audio.mp3
│   └── lyrics.srt
```

### library.json

Flat array for fast loading:

```json
[
  {
    "id": "a1b2c3d4",
    "title": "REWRITE",
    "audioFile": "audio.wav",
    "lyricsFile": "lyrics.nyaviz",
    "dateAdded": "2026-03-22T00:00:00Z",
    "lastPlayed": "2026-03-22T00:00:00Z"
  }
]
```

### Identity

Audio filename is the key. If the user opens an audio file whose name already exists in the library, the existing entry is loaded instead of creating a duplicate.

### Lyrics Replacement

Lyrics are replaceable per entry. Opening new lyrics for the same audio:

1. Deletes old lyrics file + old directive images from the entry folder
2. Copies new lyrics file + new directive images into the entry folder
3. Updates meta.json

## Auto-Add Flow

### Opening audio

1. Audio loads and plays as normal (no UX change)
2. Check if an entry with this audio filename exists in library
   - Yes: Load that entry (including its saved lyrics). Done.
   - No: Copy audio to a new entry folder, create meta.json, add to library.json

### Opening lyrics

1. Lyrics load as normal
2. Delete old lyrics + directive images from current entry folder (if any)
3. Copy new lyrics file into current entry folder
4. If `.nyaviz` with background directives, copy all referenced images into entry folder
5. Update meta.json and library.json

## UI: Bottom Drawer

A pull-up drawer anchored to the bottom of the window.

### Collapsed State

- Small pill/handle bar at bottom center
- Subtle drag indicator, no text

### Expanded State

- Slides up with translucent dark blur background (matches settings panel aesthetic)
- Scrollable list of library entries, each row showing:
  - Song title
  - Lyrics indicator icon (present/absent)
  - Last played date (secondary text)
- Active song highlighted
- Click row to switch songs (loads audio + lyrics + images from library)
- Swipe left or delete key to remove entry (deletes folder from disk)
- Drag handle or click to toggle

### Fullscreen Mode

Drawer overlays on top of floating controls. Same toggle behavior.

## Key Decisions

- Files are **copied** into the app folder (self-contained, survives original file moves)
- Audio filename is the **identity key** (no duplicates)
- Lyrics are **replaceable** (one lyrics slot per audio)
- Directive images are **included** (full .nyaviz experience preserved)
- Songs are **auto-added** on open (no explicit "add to library" step)
- Storage format is **JSON files** (no Core Data, keeps it simple)
