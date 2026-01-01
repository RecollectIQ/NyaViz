# NyaViz 🎵✨

A beautiful Apple Music-style lyric player for macOS with elegant, auto-scrolling lyrics display.

![NyaViz Preview](preview.png)

## Features

### 🎨 Beautiful Design
- Apple Music-inspired modern interface
- Glassmorphism and blur effects
- Smooth animations and transitions
- Dark, elegant aesthetic

### 📜 Lyric Display
- **Auto-scrolling lyrics** synced to audio playback
- **Full-screen mode** for immersive viewing
- **Windowed mode** with split view (controls + lyrics)
- Gradient text effects on active lyrics
- Beautiful glow effects
- Click any lyric line to seek to that timestamp

### 🎛️ Customization
- **8 gradient presets**: Night Sky, Sunset, Ocean, Forest, Aurora, Lavender, Midnight, Cosmic
- **Solid color backgrounds**
- **Custom image backgrounds**
- Adjustable background **opacity and blur**
- Configurable lyric **font size and colors**
- Toggle glow effects
- Lyric alignment options (left, center, right)

### 🎵 Audio Controls
- Play/Pause with spacebar
- Seek forward/backward (10 seconds)
- **Loop mode** for continuous playback
- Volume control
- Progress bar with seeking

## How to Use

1. **Open an audio file**: Click the settings gear → "Open Audio File" or press `⌘O`
2. **Load lyrics**: Click "Open SRT File" or press `⌘L` to load an SRT subtitle file
3. **Play**: Press spacebar or click the play button
4. **Customize**: Open settings to change background, font size, and effects
5. **Full-screen**: Click the expand button to enter immersive full-screen lyrics mode

## Supported Formats

### Audio
- MP3
- WAV
- AIFF
- M4A

### Lyrics
- SRT (SubRip Subtitle) files

## SRT Format Example

```
1
00:00:05,000 --> 00:00:10,000
First line of lyrics

2
00:00:10,500 --> 00:00:15,000
Second line of lyrics

3
00:00:15,500 --> 00:00:20,000
And so on...
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Space` | Play/Pause |
| `←` | Seek back 10 seconds |
| `→` | Seek forward 10 seconds |
| `⌘O` | Open audio file |
| `⌘L` | Open SRT file |

## Requirements

- macOS 14.0 or later
- Xcode 15+ to build

## Building

1. Open `NyaViz.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run (⌘R)

## License

MIT License - Feel free to use and modify!

---

Made with 💜 using SwiftUI

