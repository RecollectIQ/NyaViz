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
    
    var duration: TimeInterval {
        endTime - startTime
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
        
        return lyrics.sorted { $0.startTime < $1.startTime }
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
