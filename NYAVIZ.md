# NyaViz File Format Specification

## Overview

`.nyaviz` is an extended subtitle format for the NyaViz lyrics visualizer application. It is fully backwards-compatible with the standard SRT (SubRip) format while adding support for:

- **Multiple entries with identical timestamps** (for main lyrics + translations/echoes)
- **Inline text coloring** (hex colors and named colors)
- **Text styling** (bold and italic)

## File Extension

`.nyaviz`

## Basic Structure

NyaViz files follow the same block structure as SRT files:

```
SEQUENCE_NUMBER
TIMESTAMP_START --> TIMESTAMP_END
LYRIC_TEXT

SEQUENCE_NUMBER
TIMESTAMP_START --> TIMESTAMP_END
LYRIC_TEXT
...
```

### Timestamp Format

Timestamps use the standard SRT format:
- `HH:MM:SS,mmm` (hours:minutes:seconds,milliseconds)
- `HH:MM:SS.mmm` (alternative with period)
- `MM:SS,mmm` or `MM:SS.mmm` (shortened format)

## Feature: Multiple Entries with Same Timestamp

When two consecutive subtitle blocks share the exact same start and end times, NyaViz treats them as a paired display:

- **Main lyric** appears prominently (top/larger)
- **Secondary lyric** appears below (smaller/dimmer)

Lines starting with `(` are automatically treated as secondary/parenthetical lines.

### Example

```
6
00:00:21,254 --> 00:00:29,095
How much you must have suffered through my anger

00:00:21,254 --> 00:00:29,095
(How much you must have overlooked your wonder)
```

In this example:
- "How much you must have suffered through my anger" displays as the main lyric
- "(How much you must have overlooked your wonder)" displays as the secondary line below

## Feature: Inline Color Markers

NyaViz supports coloring specific words or phrases within lyrics.

### Hex Color Syntax

```
[#RRGGBB]colored text[/]
[#RGB]short hex color[/]
```

### Named Color Syntax

```
[color:red]colored text[/]
[color:violet]colored text[/]
```

### Supported Named Colors

| Color Name | Hex Equivalent |
|------------|----------------|
| `red` | System red |
| `blue` | System blue |
| `green` | System green |
| `yellow` | System yellow |
| `orange` | System orange |
| `purple` | System purple |
| `pink` | System pink |
| `cyan` | System cyan |
| `white` | #FFFFFF |
| `gray` / `grey` | System gray |
| `violet` | #8F00FF |
| `gold` | #FFD700 |
| `crimson` | #DC143C |
| `lime` | #00FF00 |
| `teal` | #008080 |
| `indigo` | System indigo |
| `mint` | System mint |

### Color Examples

```
1
00:00:05,000 --> 00:00:10,000
Through patches of [#8B00FF]violet[/] we walk

2
00:00:10,000 --> 00:00:15,000
The [color:crimson]crimson[/] sunset fades to [color:gold]gold[/]
```

## Feature: Text Styling

### Bold

```
[b]bold text[/b]
[bold]bold text[/bold]
```

### Italic

```
[i]italic text[/i]
[italic]italic text[/italic]
```

### Combined Styles

Multiple styles can be combined in a single tag:

```
[#FF0000 b]red and bold[/]
[#00FF00 b i]green, bold and italic[/]
[color:violet bold]violet and bold[/]
```

### Styling Examples

```
1
00:00:00,000 --> 00:00:05,000
[b]Listen[/b] to the [i]whispers[/i] of the wind

2
00:00:05,000 --> 00:00:10,000
[#FF6B6B b]REMEMBER[/] what we [#6B98FF i]lost[/i]
```

## Complete Example

```
1
00:00:00,000 --> 00:00:05,000
Welcome to the [color:violet]violet[/] garden

2
00:00:05,000 --> 00:00:12,000
How much you must have [#FF4444]suffered[/] through my anger

00:00:05,000 --> 00:00:12,000
(How much you must have overlooked your [color:gold]wonder[/])

3
00:00:12,000 --> 00:00:18,000
[b]Through patches of violet[/b] we [i]wander[/i]

4
00:00:18,000 --> 00:00:25,000
[#8B00FF bold]VIOLET[/] dreams and [#FFD700 italic]golden[/] seams
```

## Feature: Inline Directives

Directives let a `.nyaviz` file change display settings at specific playback times. A directive is a standalone block (separated from other blocks by blank lines) containing exactly one line that starts with `!`.

### Syntax

```
!HH:MM:SS,mmm type:value
```

- The timestamp format is identical to subtitle timestamps (`HH:MM:SS,mmm` or `HH:MM:SS.mmm`).
- `type` identifies the directive; `value` is the directive-specific argument.
- Whitespace around the timestamp and value is ignored.
- Lines that do not match this pattern (unknown type, malformed timestamp, missing value) are silently skipped.

### Supported Directive Types

#### `mode`

Switches the number of lyric lines displayed.

| Value | Effect |
|-------|--------|
| `minimal` | Show 1 lyric line (`lyricLinesVisible = 1`) |
| `dialog` | Show 4 lyric lines (`lyricLinesVisible = 4`) |

```
!00:01:30,000 mode:minimal
!00:02:00,000 mode:dialog
```

Only `minimal` and `dialog` are valid mode values. Any other value is ignored.

#### `background`

Loads a new background image at the specified time. The value is a filename or relative path resolved against the directory that contains the `.nyaviz` file.

```
!00:02:30,000 background:chorus_backdrop.jpg
!00:03:00,000 background:assets/verse2.png
```

If the referenced file does not exist, the directive is silently ignored.

### Directive Placement

Directives appear between subtitle blocks, separated by blank lines just like regular blocks:

```
1
00:00:00,000 --> 00:00:05,000
Opening lyric

!00:00:05,000 mode:minimal

2
00:00:05,000 --> 00:00:12,000
Verse one lyric

!00:01:30,000 background:chorus.jpg
!00:01:30,000 mode:dialog

3
00:01:30,000 --> 00:01:38,000
Chorus lyric
```

Multiple directives can appear in the same block (consecutive lines all starting with `!`):

```
!00:01:30,000 background:chorus.jpg
!00:01:30,000 mode:dialog
```

### Transitions

When a `background` directive fires, the old and new images crossfade over 0.8 seconds. When a `mode` directive fires, the lyric display crossfades over 0.8 seconds. Both transitions use `easeInOut` timing and run simultaneously when triggered at the same timestamp.

### Settings Override & Restore

Directives override the user's current settings (lyric mode, background image) during playback. The user's original settings are automatically restored when:

- A new lyrics file is loaded
- Playback is stopped

This means a `.nyaviz` file has full control over the visual experience during its playback without permanently changing the user's preferences.

### Seek Behaviour

When the user seeks to a new position, directives are re-evaluated from the beginning up to the seeked position, so the display state always reflects what it should be at that point in the track.

### Image Loading

Background images referenced by directives are resolved relative to the `.nyaviz` file's directory. On macOS, the app prompts for folder access (sandbox) when background directives are detected, then pre-loads all referenced images into memory for instant switching during playback.

When a `.nyaviz` file is added to the library, all referenced background images are copied into the library entry folder alongside the audio and lyrics files, making the entry fully self-contained.

### Backwards Compatibility

Files without any directive lines parse and display exactly as before. The directive feature is purely additive.

## Parsing Rules

1. **Backwards Compatibility**: Plain text without markers renders normally
2. **Unclosed Tags**: If a closing `[/]` is missing, styles apply to the rest of the line
3. **Nested Tags**: Tags do not nest; each opening tag starts fresh styling
4. **Case Insensitivity**: Tag names are case-insensitive (`[B]` = `[b]`)
5. **Whitespace**: Whitespace inside tags is ignored (`[#FF0000  b]` = `[#FF0000 b]`)
6. **Invalid Colors**: Unrecognized color names or malformed hex codes are ignored
7. **Closing Variants**: `[/]` resets all styles; `[/color]`, `[/b]`, `[/i]` reset specific styles

## MIME Type

No official MIME type. Suggested: `text/x-nyaviz` or `application/x-nyaviz`

## File Loading

NyaViz automatically detects the format based on file extension:
- `.nyaviz` → NyaViz parser (with style support)
- `.srt` → Standard SRT parser (styles stripped)

## API Reference (Swift)

### Key Types

```swift
/// A segment of text with optional styling
struct StyledTextSegment {
    let text: String
    let color: Color?      // nil = inherit default (white)
    let isBold: Bool
    let isItalic: Bool
}

/// A complete line with styled segments
struct StyledLine {
    let segments: [StyledTextSegment]
    var plainText: String  // Plain text without styling
    var hasStyles: Bool    // Whether any segment has styles
}

/// A single lyric entry
struct Lyric {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let styledText: StyledLine           // Main lyric
    let styledSecondaryText: StyledLine? // Translation/echo (if paired)
}
```

### Directive Types

```swift
/// A directive that changes display settings at a specific playback time
struct NyaVizDirective {
    enum DirectiveType: Equatable {
        case mode(String)        // "minimal" (1 line) or "dialog" (4 lines)
        case background(String)  // filename/path relative to the .nyaviz file
    }

    let time: TimeInterval   // Seconds from track start
    let type: DirectiveType
}

/// Combined result of a full NyaViz parse
struct NyaVizParseResult {
    let lyrics: [Lyric]
    let directives: [NyaVizDirective]  // Sorted by time
}
```

### Loading Files

```swift
// Automatic format detection – lyrics only (backwards compatible)
let lyrics = SubtitleLoader.load(from: fileURL)

// Automatic format detection – lyrics + directives
let result = SubtitleLoader.loadWithDirectives(from: fileURL)

// Explicit NyaViz parsing – lyrics + directives
let result = NyaVizParser.loadWithDirectives(from: fileURL)

// Explicit NyaViz parsing – lyrics only
let lyrics = NyaVizParser.load(from: fileURL)

// Explicit SRT parsing
let lyrics = SRTParser.load(from: fileURL)
```

### Parsing Inline Styles

```swift
let styledLine = NyaVizParser.parseStyledLine("Hello [#FF0000]World[/]")
// styledLine.segments = [
//   StyledTextSegment(text: "Hello ", color: nil, isBold: false, isItalic: false),
//   StyledTextSegment(text: "World", color: Color.red, isBold: false, isItalic: false)
// ]
```

## Use Cases

1. **Karaoke-style highlighting**: Color key words that should stand out
2. **Dual-language lyrics**: Main lyric in native language, translation in parentheses below
3. **Emphasis**: Bold important words, italicize whispered/soft passages
4. **Character differentiation**: Different colors for different singers/characters
5. **Artistic styling**: Match colors to song themes or album artwork
6. **Music video feel**: Use `background` and `mode` directives to create scene changes synced to the music
7. **Playlist experience**: Songs with `.nyaviz` files retain their full visual experience in the library

## Song Library

NyaViz maintains a persistent song library at `~/Library/Application Support/NyaViz/Library/`. Songs are auto-added when opened and can be browsed via the library sidebar.

### Library Structure

```
Library/
├── <uuid>/
│   ├── index.json          # Entry metadata
│   ├── audio.mp3           # Copied audio file
│   ├── lyrics.nyaviz       # Copied lyrics (optional, replaceable)
│   ├── backdrop1.jpg       # Copied directive images
│   └── backdrop2.jpg
```

### Key Behaviours

- **Auto-add**: Opening an audio file automatically adds it to the library
- **Duplicate detection**: If the same audio filename exists, the existing entry is loaded
- **Lyrics replacement**: Opening new lyrics for the same audio replaces the old lyrics and associated directive images
- **Self-contained**: All files (audio, lyrics, directive images) are copied into the library folder
- **Playlist playback**: When loop-one is off, the next song in the library plays automatically

## Video Export

NyaViz can export the lyrics visualization as an MP4 video. The export renders:

- Background image with blur/opacity settings
- Styled text (colors, bold, italic) in all lyric modes
- Dialog mode with game-style conversation box
- Minimal mode with centered uppercase text
- Audio visualizer bars
- Snow particle effects
- Track info with progress ring

All UI elements scale proportionally with the chosen resolution (480p, 720p, 1080p, 4K), using 1080p as the reference.

---

*NyaViz Format Specification v1.2*

