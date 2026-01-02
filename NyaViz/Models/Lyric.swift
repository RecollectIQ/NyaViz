//
//  Lyric.swift
//  NyaViz
//

import Foundation

struct Lyric: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    /// Secondary line (e.g., translation in parentheses) that shares the same timestamp
    let secondaryText: String?
    
    init(startTime: TimeInterval, endTime: TimeInterval, text: String, secondaryText: String? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.secondaryText = secondaryText
    }
    
    var duration: TimeInterval {
        endTime - startTime
    }
    
    /// Whether this lyric has a paired translation/secondary line
    var hasPairedLine: Bool {
        secondaryText != nil
    }
}

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
                  let startTime = parseTimestamp(timestamps[0].trimmingCharacters(in: .whitespaces)),
                  let endTime = parseTimestamp(timestamps[1].trimmingCharacters(in: .whitespaces)) else { continue }
            
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
        
        // Sort by start time first
        let sortedLyrics = lyrics.sorted { $0.startTime < $1.startTime }
        
        // Merge lyrics with identical timestamps
        // When two consecutive lyrics have the same start and end time,
        // combine them: main lyric on top, secondary (parenthetical) below
        var mergedLyrics: [Lyric] = []
        var i = 0
        
        while i < sortedLyrics.count {
            let current = sortedLyrics[i]
            
            // Look ahead for a lyric with matching timestamps
            if i + 1 < sortedLyrics.count {
                let next = sortedLyrics[i + 1]
                
                // Check if timestamps match (within tiny tolerance for floating point)
                let sameStart = abs(current.startTime - next.startTime) < 0.01
                let sameEnd = abs(current.endTime - next.endTime) < 0.01
                
                if sameStart && sameEnd {
                    // Determine which is main and which is secondary
                    let currentIsParenthetical = current.text.trimmingCharacters(in: .whitespaces).hasPrefix("(")
                    let nextIsParenthetical = next.text.trimmingCharacters(in: .whitespaces).hasPrefix("(")
                    
                    let mainText: String
                    let secondaryText: String
                    
                    if currentIsParenthetical && !nextIsParenthetical {
                        // Current is secondary, next is main
                        mainText = next.text
                        secondaryText = current.text
                    } else if !currentIsParenthetical && nextIsParenthetical {
                        // Current is main, next is secondary
                        mainText = current.text
                        secondaryText = next.text
                    } else {
                        // Both same type - first is main, second is secondary
                        mainText = current.text
                        secondaryText = next.text
                    }
                    
                    mergedLyrics.append(Lyric(
                        startTime: current.startTime,
                        endTime: current.endTime,
                        text: mainText,
                        secondaryText: secondaryText
                    ))
                    
                    i += 2 // Skip both lyrics
                    continue
                }
            }
            
            // No merge - add as single lyric
            mergedLyrics.append(current)
            i += 1
        }
        
        return mergedLyrics
    }
    
    private static func parseTimestamp(_ string: String) -> TimeInterval? {
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
