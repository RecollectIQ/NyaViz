//
//  Lyric.swift
//  NyaViz
//

import Foundation
import SwiftUI

// MARK: - Styled Text Segment

/// A segment of text with optional styling (color, bold, italic)
struct StyledTextSegment: Equatable {
    let text: String
    let color: Color?
    let isBold: Bool
    let isItalic: Bool
    
    init(text: String, color: Color? = nil, isBold: Bool = false, isItalic: Bool = false) {
        self.text = text
        self.color = color
        self.isBold = isBold
        self.isItalic = isItalic
    }
    
    /// Plain text segment with no styling
    static func plain(_ text: String) -> StyledTextSegment {
        StyledTextSegment(text: text)
    }
    
    /// Colored text segment
    static func colored(_ text: String, color: Color) -> StyledTextSegment {
        StyledTextSegment(text: text, color: color)
    }
}

// MARK: - Styled Line

/// A complete line of lyrics with styled segments
struct StyledLine: Equatable {
    let segments: [StyledTextSegment]
    
    /// The plain text representation (without styling)
    var plainText: String {
        segments.map { $0.text }.joined()
    }
    
    /// Create from plain text (no styling)
    static func plain(_ text: String) -> StyledLine {
        StyledLine(segments: [.plain(text)])
    }
    
    /// Whether this line has any styled segments
    var hasStyles: Bool {
        segments.contains { $0.color != nil || $0.isBold || $0.isItalic }
    }
}

// MARK: - Lyric

struct Lyric: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    
    /// Primary line with styled segments
    let styledText: StyledLine
    /// Secondary line (e.g., translation in parentheses) with styled segments
    let styledSecondaryText: StyledLine?
    
    /// Plain text for backwards compatibility
    var text: String {
        styledText.plainText
    }
    
    /// Plain secondary text for backwards compatibility
    var secondaryText: String? {
        styledSecondaryText?.plainText
    }
    
    init(startTime: TimeInterval, endTime: TimeInterval, text: String, secondaryText: String? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.styledText = .plain(text)
        self.styledSecondaryText = secondaryText.map { .plain($0) }
    }
    
    init(startTime: TimeInterval, endTime: TimeInterval, styledText: StyledLine, styledSecondaryText: StyledLine? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.styledText = styledText
        self.styledSecondaryText = styledSecondaryText
    }
    
    var duration: TimeInterval {
        endTime - startTime
    }
    
    /// Whether this lyric has a paired translation/secondary line
    var hasPairedLine: Bool {
        styledSecondaryText != nil
    }
    
    /// Whether this lyric has any styled segments
    var hasStyles: Bool {
        styledText.hasStyles || (styledSecondaryText?.hasStyles ?? false)
    }
}

// MARK: - SRT Parser (Standard SubRip format)

struct SRTParser {
    static func parse(_ content: String) -> [Lyric] {
        var lyrics: [Lyric] = []
        
        // Normalize line endings (handle Windows \r\n, old Mac \r, and Unix \n)
        let normalizedContent = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            // Remove BOM if present
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        
        // Split by double newlines (empty lines between blocks)
        // Also handle cases where there might be more than 2 newlines
        let blocks = normalizedContent.components(separatedBy: "\n\n")
        
        for block in blocks {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBlock.isEmpty else { continue }
            
            let lines = trimmedBlock.components(separatedBy: "\n").map { 
                $0.trimmingCharacters(in: .whitespaces) 
            }.filter { !$0.isEmpty }
            
            guard lines.count >= 2 else { continue }
            
            // Find the timestamp line (contains " --> ")
            guard let timestampLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timestampLine = lines[timestampLineIndex]
            
            // Parse timestamps - handle both " --> " and "-->" formats
            let arrowPattern = timestampLine.contains(" --> ") ? " --> " : "-->"
            let timestamps = timestampLine.components(separatedBy: arrowPattern)
            
            guard timestamps.count == 2,
                  let startTime = TimestampParser.parse(timestamps[0]),
                  let endTime = TimestampParser.parse(timestamps[1]) else { continue }
            
            // Get text lines (everything after timestamp line)
            let textLines = lines.dropFirst(timestampLineIndex + 1)
            let text = textLines.joined(separator: " ")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\{[^}]+\\}", with: "", options: .regularExpression) // Remove ASS tags like {\an8}
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !text.isEmpty {
                lyrics.append(Lyric(startTime: startTime, endTime: endTime, text: text))
            }
        }
        
        // Sort and merge lyrics with identical timestamps
        return LyricMerger.merge(lyrics)
    }
}

// MARK: - NyaViz Directives

/// A directive that changes display settings at a specific playback time.
///
/// Directives appear in `.nyaviz` files as single-line blocks between subtitle blocks:
/// ```
/// !00:01:30,000 mode:minimal
/// !00:02:00,000 mode:dialog
/// !00:02:30,000 background:image2.jpg
/// ```
struct NyaVizDirective {
    /// The type of action this directive performs.
    enum DirectiveType: Equatable {
        /// Switch the lyric display mode. Valid values: `"minimal"` (1 line) or `"dialog"` (4 lines).
        case mode(String)
        /// Load a new background image. The value is a filename or path relative to the `.nyaviz` file.
        case background(String)
    }

    /// The playback time at which this directive fires, in seconds.
    let time: TimeInterval
    /// The action to perform when this directive fires.
    let type: DirectiveType
}

// MARK: - NyaViz Parse Result

/// The combined output of a full NyaViz file parse, containing both lyrics and directives.
struct NyaVizParseResult {
    /// All subtitle entries parsed from the file.
    let lyrics: [Lyric]
    /// All inline directives parsed from the file, sorted by time.
    let directives: [NyaVizDirective]
}

// MARK: - NyaViz Parser (Extended format with styling)

struct NyaVizParser {

    /// Parse NyaViz format content
    /// Supports color markers: [#RRGGBB]text[/] or [color:name]text[/]
    /// Supports bold: [b]text[/b] or [bold]text[/bold]
    /// Supports italic: [i]text[/i] or [italic]text[/italic]
    /// Supports directives: `!HH:MM:SS,mmm mode:minimal`, `!HH:MM:SS,mmm background:file.jpg`
    static func parse(_ content: String) -> [Lyric] {
        parseWithDirectives(content).lyrics
    }

    /// Parse NyaViz format content and return both lyrics and directives.
    ///
    /// Directive lines begin with `!` followed by a timestamp and a directive body:
    /// ```
    /// !00:01:30,000 mode:minimal
    /// !00:02:00,000 mode:dialog
    /// !00:02:30,000 background:path/to/image.jpg
    /// ```
    /// Valid mode values are `minimal` (sets 1 visible line) and `dialog` (sets 4 visible lines).
    /// Background values are filenames or paths resolved relative to the `.nyaviz` file's directory.
    ///
    /// Files without any directive lines are fully backwards-compatible.
    static func parseWithDirectives(_ content: String) -> NyaVizParseResult {
        var lyrics: [Lyric] = []
        var directives: [NyaVizDirective] = []

        // Normalize line endings
        let normalizedContent = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))

        // Split by double newlines
        let blocks = normalizedContent.components(separatedBy: "\n\n")

        for block in blocks {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBlock.isEmpty else { continue }

            // Split block into lines
            let blockLines = trimmedBlock.components(separatedBy: "\n").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }

            // A directive block: all lines start with '!'
            // This handles single directives and consecutive directives in one block
            if blockLines.allSatisfy({ $0.hasPrefix("!") }) {
                for directiveLine in blockLines {
                    if let directive = parseDirectiveLine(directiveLine) {
                        directives.append(directive)
                    }
                }
                continue
            }

            // Otherwise treat as a normal subtitle block
            guard blockLines.count >= 2 else { continue }

            // Find the timestamp line
            guard let timestampLineIndex = blockLines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timestampLine = blockLines[timestampLineIndex]

            let arrowPattern = timestampLine.contains(" --> ") ? " --> " : "-->"
            let timestamps = timestampLine.components(separatedBy: arrowPattern)

            guard timestamps.count == 2,
                  let startTime = TimestampParser.parse(timestamps[0]),
                  let endTime = TimestampParser.parse(timestamps[1]) else { continue }

            // Get text lines and parse styling
            let textLines = blockLines.dropFirst(timestampLineIndex + 1)
            let rawText = textLines.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !rawText.isEmpty {
                let styledLine = parseStyledLine(rawText)
                lyrics.append(Lyric(startTime: startTime, endTime: endTime, styledText: styledLine))
            }
        }

        let mergedLyrics = LyricMerger.mergeStyled(lyrics)
        let sortedDirectives = directives.sorted { $0.time < $1.time }
        return NyaVizParseResult(lyrics: mergedLyrics, directives: sortedDirectives)
    }

    // MARK: - Directive Parsing

    /// Parse a single directive line of the form `!HH:MM:SS,mmm type:value`.
    ///
    /// Returns `nil` for lines that cannot be parsed (malformed timestamp, unknown type, etc.).
    /// Whitespace around the timestamp and body is tolerated.
    private static func parseDirectiveLine(_ line: String) -> NyaVizDirective? {
        // Strip leading '!'
        let body = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        // Split on first whitespace to separate the timestamp from the directive body
        let separatorIndex = body.firstIndex(where: { $0.isWhitespace })
        guard let sepIdx = separatorIndex else { return nil }

        let timestampPart = String(body[body.startIndex..<sepIdx]).trimmingCharacters(in: .whitespaces)
        let directivePart = String(body[body.index(after: sepIdx)...]).trimmingCharacters(in: .whitespaces)

        guard let time = TimestampParser.parse(timestampPart), !directivePart.isEmpty else { return nil }

        // directivePart has the form "key:value"
        guard let colonIndex = directivePart.firstIndex(of: ":") else { return nil }
        let key = String(directivePart[directivePart.startIndex..<colonIndex])
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        let value = String(directivePart[directivePart.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespaces)

        guard !value.isEmpty else { return nil }

        switch key {
        case "mode":
            let normalized = value.lowercased()
            guard normalized == "minimal" || normalized == "dialog" else { return nil }
            return NyaVizDirective(time: time, type: .mode(normalized))
        case "background":
            return NyaVizDirective(time: time, type: .background(value))
        default:
            return nil
        }
    }
    
    /// Parse a line of text with style markers into StyledLine
    static func parseStyledLine(_ text: String) -> StyledLine {
        var segments: [StyledTextSegment] = []
        var remaining = text
        
        // Pattern matches: [#RRGGBB], [#RGB], [color:name], [b], [bold], [i], [italic], and closing [/], [/color], [/b], [/bold], [/i], [/italic]
        // Also supports combining: [#FF0000 b i]text[/]
        let tagPattern = #"\[([^\]]+)\]"#
        
        var currentColor: Color? = nil
        var currentBold = false
        var currentItalic = false
        
        while !remaining.isEmpty {
            // Find next tag
            if let range = remaining.range(of: tagPattern, options: .regularExpression) {
                // Add text before tag as segment
                let beforeTag = String(remaining[..<range.lowerBound])
                if !beforeTag.isEmpty {
                    segments.append(StyledTextSegment(
                        text: beforeTag,
                        color: currentColor,
                        isBold: currentBold,
                        isItalic: currentItalic
                    ))
                }
                
                // Parse the tag
                let tagContent = String(remaining[range]).dropFirst().dropLast() // Remove [ and ]
                let tagString = String(tagContent).lowercased().trimmingCharacters(in: .whitespaces)
                
                if tagString == "/" || tagString == "/color" || tagString == "/b" || tagString == "/bold" || tagString == "/i" || tagString == "/italic" {
                    // Closing tag - reset styles
                    if tagString == "/" {
                        currentColor = nil
                        currentBold = false
                        currentItalic = false
                    } else if tagString == "/color" {
                        currentColor = nil
                    } else if tagString == "/b" || tagString == "/bold" {
                        currentBold = false
                    } else if tagString == "/i" || tagString == "/italic" {
                        currentItalic = false
                    }
                } else {
                    // Opening tag - parse style attributes
                    let parts = tagString.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    for part in parts {
                        if part.hasPrefix("#") {
                            currentColor = parseHexColor(part)
                        } else if part.hasPrefix("color:") {
                            let colorName = String(part.dropFirst(6))
                            currentColor = parseNamedColor(colorName)
                        } else if part == "b" || part == "bold" {
                            currentBold = true
                        } else if part == "i" || part == "italic" {
                            currentItalic = true
                        }
                    }
                }
                
                remaining = String(remaining[range.upperBound...])
            } else {
                // No more tags - add remaining text
                if !remaining.isEmpty {
                    segments.append(StyledTextSegment(
                        text: remaining,
                        color: currentColor,
                        isBold: currentBold,
                        isItalic: currentItalic
                    ))
                }
                break
            }
        }
        
        // If no segments, return plain text
        if segments.isEmpty {
            return .plain(text)
        }
        
        return StyledLine(segments: segments)
    }
    
    /// Parse hex color string (#RGB or #RRGGBB)
    private static func parseHexColor(_ hex: String) -> Color? {
        var hexString = hex.trimmingCharacters(in: .whitespaces)
        if hexString.hasPrefix("#") {
            hexString = String(hexString.dropFirst())
        }
        
        // Expand 3-digit hex to 6-digit
        if hexString.count == 3 {
            hexString = hexString.map { "\($0)\($0)" }.joined()
        }
        
        guard hexString.count == 6,
              let hexValue = UInt64(hexString, radix: 16) else {
            return nil
        }
        
        let r = Double((hexValue >> 16) & 0xFF) / 255.0
        let g = Double((hexValue >> 8) & 0xFF) / 255.0
        let b = Double(hexValue & 0xFF) / 255.0
        
        return Color(red: r, green: g, blue: b)
    }
    
    /// Parse named color
    private static func parseNamedColor(_ name: String) -> Color? {
        switch name.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "cyan": return .cyan
        case "white": return .white
        case "gray", "grey": return .gray
        case "violet": return Color(red: 0.56, green: 0.0, blue: 1.0)
        case "gold": return Color(red: 1.0, green: 0.84, blue: 0.0)
        case "crimson": return Color(red: 0.86, green: 0.08, blue: 0.24)
        case "lime": return Color(red: 0.0, green: 1.0, blue: 0.0)
        case "teal": return Color(red: 0.0, green: 0.5, blue: 0.5)
        case "indigo": return .indigo
        case "mint": return .mint
        default: return nil
        }
    }
}

// MARK: - Shared Timestamp Parser

struct TimestampParser {
    static func parse(_ string: String) -> TimeInterval? {
        // Support both "00:00:00,000" and "00:00:00.000" formats
        var normalized = string
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        
        // Remove any position data after timestamp (e.g., "00:00:00.000 X1:0 X2:0")
        if let spaceIndex = normalized.firstIndex(of: " ") {
            normalized = String(normalized[..<spaceIndex])
        }
        
        let components = normalized.components(separatedBy: ":")
        
        guard components.count >= 2 else { return nil }
        
        if components.count == 3 {
            // Hours:Minutes:Seconds.Milliseconds
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        } else if components.count == 2 {
            // Minutes:Seconds.Milliseconds
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else { return nil }
            return minutes * 60 + seconds
        }
        
        return nil
    }
}

// MARK: - Lyric Merger

struct LyricMerger {
    /// Merge lyrics with identical timestamps (plain text version)
    static func merge(_ lyrics: [Lyric]) -> [Lyric] {
        // Sort by start time first
        let sortedLyrics = lyrics.sorted { $0.startTime < $1.startTime }
        
        var mergedLyrics: [Lyric] = []
        var i = 0
        
        while i < sortedLyrics.count {
            let current = sortedLyrics[i]
            
            if i + 1 < sortedLyrics.count {
                let next = sortedLyrics[i + 1]
                
                let sameStart = abs(current.startTime - next.startTime) < 0.01
                let sameEnd = abs(current.endTime - next.endTime) < 0.01
                
                if sameStart && sameEnd {
                    let currentIsParenthetical = current.text.trimmingCharacters(in: .whitespaces).hasPrefix("(")
                    let nextIsParenthetical = next.text.trimmingCharacters(in: .whitespaces).hasPrefix("(")
                    
                    let mainText: String
                    let secondaryText: String
                    
                    if currentIsParenthetical && !nextIsParenthetical {
                        mainText = next.text
                        secondaryText = current.text
                    } else if !currentIsParenthetical && nextIsParenthetical {
                        mainText = current.text
                        secondaryText = next.text
                    } else {
                        mainText = current.text
                        secondaryText = next.text
                    }
                    
                    mergedLyrics.append(Lyric(
                        startTime: current.startTime,
                        endTime: current.endTime,
                        text: mainText,
                        secondaryText: secondaryText
                    ))
                    
                    i += 2
                    continue
                }
            }
            
            mergedLyrics.append(current)
            i += 1
        }
        
        return mergedLyrics
    }
    
    /// Merge lyrics with identical timestamps (styled text version)
    static func mergeStyled(_ lyrics: [Lyric]) -> [Lyric] {
        let sortedLyrics = lyrics.sorted { $0.startTime < $1.startTime }
        
        var mergedLyrics: [Lyric] = []
        var i = 0
        
        while i < sortedLyrics.count {
            let current = sortedLyrics[i]
            
            if i + 1 < sortedLyrics.count {
                let next = sortedLyrics[i + 1]
                
                let sameStart = abs(current.startTime - next.startTime) < 0.01
                let sameEnd = abs(current.endTime - next.endTime) < 0.01
                
                if sameStart && sameEnd {
                    let currentIsParenthetical = current.text.trimmingCharacters(in: .whitespaces).hasPrefix("(")
                    let nextIsParenthetical = next.text.trimmingCharacters(in: .whitespaces).hasPrefix("(")
                    
                    let mainStyled: StyledLine
                    let secondaryStyled: StyledLine
                    
                    if currentIsParenthetical && !nextIsParenthetical {
                        mainStyled = next.styledText
                        secondaryStyled = current.styledText
                    } else if !currentIsParenthetical && nextIsParenthetical {
                        mainStyled = current.styledText
                        secondaryStyled = next.styledText
                    } else {
                        mainStyled = current.styledText
                        secondaryStyled = next.styledText
                    }
                    
                    mergedLyrics.append(Lyric(
                        startTime: current.startTime,
                        endTime: current.endTime,
                        styledText: mainStyled,
                        styledSecondaryText: secondaryStyled
                    ))
                    
                    i += 2
                    continue
                }
            }
            
            mergedLyrics.append(current)
            i += 1
        }
        
        return mergedLyrics
    }
}

// MARK: - File Loading Helper

extension SRTParser {
    static func load(from url: URL) -> [Lyric] {
        // Try different encodings
        let encodings: [String.Encoding] = [.utf8, .utf16, .isoLatin1, .windowsCP1252, .ascii]
        
        for encoding in encodings {
            if let content = try? String(contentsOf: url, encoding: encoding) {
                let lyrics = parse(content)
                if !lyrics.isEmpty {
                    return lyrics
                }
            }
        }
        
        // Fallback: try to detect encoding
        if let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8) ?? 
                         String(data: data, encoding: .isoLatin1) {
            return parse(content)
        }
        
        return []
    }
}

extension NyaVizParser {
    static func load(from url: URL) -> [Lyric] {
        loadWithDirectives(from: url).lyrics
    }

    /// Load a `.nyaviz` file and return both lyrics and directives.
    static func loadWithDirectives(from url: URL) -> NyaVizParseResult {
        let encodings: [String.Encoding] = [.utf8, .utf16, .isoLatin1, .windowsCP1252, .ascii]

        for encoding in encodings {
            if let content = try? String(contentsOf: url, encoding: encoding) {
                let result = parseWithDirectives(content)
                // Only accept the result if it produced at least one lyric or directive;
                // this mirrors the existing behaviour of the plain load(from:) method.
                if !result.lyrics.isEmpty || !result.directives.isEmpty {
                    return result
                }
            }
        }

        if let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8) ??
                         String(data: data, encoding: .isoLatin1) {
            return parseWithDirectives(content)
        }

        return NyaVizParseResult(lyrics: [], directives: [])
    }
}

// MARK: - Unified Subtitle Loader

struct SubtitleLoader {
    /// Load subtitles from a file, automatically detecting format by extension.
    static func load(from url: URL) -> [Lyric] {
        loadWithDirectives(from: url).lyrics
    }

    /// Load subtitles and directives from a file, automatically detecting format by extension.
    ///
    /// Only `.nyaviz` files can contain directives; `.srt` files always return an empty
    /// directives array.
    static func loadWithDirectives(from url: URL) -> NyaVizParseResult {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "nyaviz":
            return NyaVizParser.loadWithDirectives(from: url)
        case "srt":
            return NyaVizParseResult(lyrics: SRTParser.load(from: url), directives: [])
        default:
            return NyaVizParseResult(lyrics: SRTParser.load(from: url), directives: [])
        }
    }
}
