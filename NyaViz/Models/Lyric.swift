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
        let blocks = content.components(separatedBy: "\n\n")
        
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count >= 2 else { continue }
            
            // Find the timestamp line (contains " --> ")
            guard let timestampLine = lines.first(where: { $0.contains(" --> ") }) else { continue }
            
            let timestamps = timestampLine.components(separatedBy: " --> ")
            guard timestamps.count == 2,
                  let startTime = parseTimestamp(timestamps[0].trimmingCharacters(in: .whitespaces)),
                  let endTime = parseTimestamp(timestamps[1].trimmingCharacters(in: .whitespaces)) else { continue }
            
            // Get text lines (everything after timestamp line)
            let timestampIndex = lines.firstIndex(of: timestampLine) ?? 0
            let textLines = lines.dropFirst(timestampIndex + 1)
            let text = textLines.joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !text.isEmpty {
                lyrics.append(Lyric(startTime: startTime, endTime: endTime, text: text))
            }
        }
        
        return lyrics.sorted { $0.startTime < $1.startTime }
    }
    
    private static func parseTimestamp(_ string: String) -> TimeInterval? {
        // Support both "00:00:00,000" and "00:00:00.000" formats
        let normalized = string.replacingOccurrences(of: ",", with: ".")
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

