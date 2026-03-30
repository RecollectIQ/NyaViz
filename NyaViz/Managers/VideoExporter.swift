//
//  VideoExporter.swift
//  NyaViz
//

import Foundation
import AVFoundation
import SwiftUI
import AppKit
import Combine

// MARK: - Export Options

struct ExportOptions {
    enum Resolution: String, CaseIterable {
        case r2160p = "4K (3840×2160)"
        case r1080p = "1080p (1920×1080)"
        case r720p = "720p (1280×720)"
        case r480p = "480p (854×480)"
        
        var width: Int {
            switch self {
            case .r2160p: return 3840
            case .r1080p: return 1920
            case .r720p: return 1280
            case .r480p: return 854
            }
        }
        
        var height: Int {
            switch self {
            case .r2160p: return 2160
            case .r1080p: return 1080
            case .r720p: return 720
            case .r480p: return 480
            }
        }
    }
    
    var resolution: Resolution = .r1080p
    var includeVisualizer: Bool = true
    var includeParticles: Bool = true
    var frameRate: Double = 30
}

@MainActor
class VideoExporter: ObservableObject {
    @Published var isExporting = false
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""
    @Published var showExportOptions = false
    @Published var exportOptions = ExportOptions()
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    // These will be set from exportOptions
    private var frameRate: Double = 30
    private var videoWidth: Int = 1920
    private var videoHeight: Int = 1080
    
    // Frame cache for duplicate detection
    private var lastRenderedLyricIndex: Int = -999
    private var lastRenderedTime: TimeInterval = -1
    private var cachedPixelBuffer: CVPixelBuffer?
    
    // Batch processing settings
    private let batchSize = 10 // Render frames in batches
    private let keyframeInterval: TimeInterval = 0.1 // Minimum time between full re-renders
    
    enum ExportError: LocalizedError {
        case noAudioFile
        case cannotCreateWriter
        case cannotReadAudio
        case exportCancelled
        case renderingFailed
        
        var errorDescription: String? {
            switch self {
            case .noAudioFile: return "No audio file loaded"
            case .cannotCreateWriter: return "Cannot create video writer"
            case .cannotReadAudio: return "Cannot read audio file"
            case .exportCancelled: return "Export was cancelled"
            case .renderingFailed: return "Failed to render video frame"
            }
        }
    }
    
    /// Shows export options sheet, then save panel, then exports
    func showExportOptionsAndExport(
        audioPlayer: AudioPlayerManager,
        settings: SettingsManager,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.pendingCompletion = completion
        self.pendingAudioPlayer = audioPlayer
        self.pendingSettings = settings
        self.showExportOptions = true
    }
    
    // Stored references for after options are confirmed
    private var pendingCompletion: ((Result<URL, Error>) -> Void)?
    private var pendingAudioPlayer: AudioPlayerManager?
    private var pendingSettings: SettingsManager?
    
    /// Called when user confirms export options
    func confirmExport() {
        guard let completion = pendingCompletion,
              let audioPlayer = pendingAudioPlayer,
              let settings = pendingSettings else { return }
        
        showExportOptions = false
        
        // Apply export options
        videoWidth = exportOptions.resolution.width
        videoHeight = exportOptions.resolution.height
        frameRate = exportOptions.frameRate
        
        // Show save panel
        let savePanel = NSSavePanel()
        savePanel.title = "Export Video"
        savePanel.nameFieldStringValue = "\(audioPlayer.audioFileName).mp4"
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { [weak self] response in
            guard let self = self else { return }
            
            if response == .OK, let url = savePanel.url {
                Task { @MainActor in
                    do {
                        try await self.performExport(
                            to: url,
                            audioPlayer: audioPlayer,
                            settings: settings,
                            options: self.exportOptions
                        )
                        completion(.success(url))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }
        
        pendingCompletion = nil
        pendingAudioPlayer = nil
        pendingSettings = nil
    }
    
    func cancelExport() {
        showExportOptions = false
        pendingCompletion = nil
        pendingAudioPlayer = nil
        pendingSettings = nil
    }
    
    /// Direct export without options (legacy)
    func exportVideo(
        audioPlayer: AudioPlayerManager,
        settings: SettingsManager,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Video"
        savePanel.nameFieldStringValue = "\(audioPlayer.audioFileName).mp4"
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { [weak self] response in
            guard let self = self else { return }
            
            if response == .OK, let url = savePanel.url {
                Task { @MainActor in
                    do {
                        try await self.performExport(
                            to: url,
                            audioPlayer: audioPlayer,
                            settings: settings,
                            options: self.exportOptions
                        )
                        completion(.success(url))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    /// Main export function - optimized with batch processing and frame skipping
    private func performExport(
        to outputURL: URL,
        audioPlayer: AudioPlayerManager,
        settings: SettingsManager,
        options: ExportOptions = ExportOptions()
    ) async throws {
        // Apply options
        videoWidth = options.resolution.width
        videoHeight = options.resolution.height
        frameRate = options.frameRate
        print("[VideoExporter] Starting export to: \(outputURL.path)")
        
        guard let audioFileURL = audioPlayer.currentAudioFileURL else {
            print("[VideoExporter] ERROR: No audio file URL")
            throw ExportError.noAudioFile
        }
        
        print("[VideoExporter] Audio file: \(audioFileURL.path)")
        
        isExporting = true
        progress = 0
        statusMessage = "Preparing export..."
        
        // Reset frame cache
        lastRenderedLyricIndex = -999
        lastRenderedTime = -1
        cachedPixelBuffer = nil
        frameRenderCount = 0
        
        defer {
            print("[VideoExporter] Export finished, cleaning up")
            isExporting = false
            cleanup()
        }
        
        try? FileManager.default.removeItem(at: outputURL)
        
        print("[VideoExporter] Creating asset writer...")
        
        // Setup asset writer
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        guard let writer = assetWriter else {
            print("[VideoExporter] ERROR: Could not create asset writer")
            throw ExportError.cannotCreateWriter
        }
        
        print("[VideoExporter] Asset writer created successfully")
        
        // Video settings - H.264 with high performance preset
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000, // 6 Mbps - slightly lower for speed
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: 30, // Keyframe every second for faster seeking
                AVVideoAllowFrameReorderingKey: false // Disable B-frames for speed
            ]
        ]
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = false
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: videoWidth,
            kCVPixelBufferHeightKey as String: videoHeight,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        // Only add video input - we'll mux audio separately at the end
        writer.add(videoInput!)
        
        print("[VideoExporter] Starting writer...")
        
        guard writer.startWriting() else {
            print("[VideoExporter] ERROR: Writer failed to start: \(writer.error?.localizedDescription ?? "unknown")")
            throw writer.error ?? ExportError.cannotCreateWriter
        }
        
        writer.startSession(atSourceTime: .zero)
        
        print("[VideoExporter] Writer started, loading audio asset...")
        
        // Get audio asset
        let audioAsset = AVAsset(url: audioFileURL)
        let duration = try await audioAsset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let totalFrames = Int(durationSeconds * frameRate)
        
        print("[VideoExporter] Audio duration: \(durationSeconds)s, total frames: \(totalFrames)")
        
        statusMessage = "Rendering video..."
        
        // Pre-calculate keyframes (when lyrics change)
        let keyframeTimes = calculateKeyframeTimes(
            lyrics: audioPlayer.lyrics,
            duration: durationSeconds,
            frameRate: frameRate
        )
        
        print("[VideoExporter] Keyframes calculated: \(keyframeTimes.count) keyframes")
        
        // Create simulated player
        let simulatedPlayer = SimulatedAudioPlayer(
            lyrics: audioPlayer.lyrics,
            duration: durationSeconds,
            audioFileName: audioPlayer.audioFileName
        )
        
        print("[VideoExporter] Starting GCD-based frame rendering...")
        
        // Update progress to show we've started
        progress = 0.01
        statusMessage = "Rendering frames..."
        
        // Capture values needed for background processing
        let capturedLyrics = audioPlayer.lyrics
        let capturedDuration = durationSeconds
        let capturedFileName = audioPlayer.audioFileName
        let capturedSettings = CapturedSettings(from: settings, options: options)
        let capturedBackgroundImage = settings.backgroundImage
        let capturedVideoInput = videoInput!
        let capturedAdaptor = pixelBufferAdaptor!
        
        // Use continuation to bridge GCD with async/await
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            
            // Use requestMediaDataWhenReady - Apple's recommended pattern
            let renderQueue = DispatchQueue(label: "com.nyaviz.render", qos: .userInitiated)
            
            var frameIndex = 0
            let startTime = CFAbsoluteTimeGetCurrent()
            
            capturedVideoInput.requestMediaDataWhenReady(on: renderQueue) { [self] in
                
                // Process frames while ready
                while capturedVideoInput.isReadyForMoreMediaData && frameIndex < totalFrames {
                    let currentFrame = frameIndex
                    let currentTime = Double(currentFrame) / self.frameRate
                    let presentationTime = CMTime(seconds: currentTime, preferredTimescale: 600)
                    
                    // Render on main thread synchronously
                    var pixelBuffer: CVPixelBuffer?
                    DispatchQueue.main.sync {
                        let simPlayer = SimulatedAudioPlayer(
                            lyrics: capturedLyrics,
                            duration: capturedDuration,
                            audioFileName: capturedFileName
                        )
                        simPlayer.updateTime(currentTime)
                        
                        let image = self.renderFrameWithSettings(
                            at: currentTime,
                            simulatedPlayer: simPlayer,
                            capturedSettings: capturedSettings,
                            backgroundImage: capturedBackgroundImage
                        )
                        
                        pixelBuffer = self.createPixelBuffer(from: image)
                    }
                    
                    guard let buffer = pixelBuffer else {
                        print("[VideoExporter] ERROR: Failed to create pixel buffer at frame \(currentFrame)")
                        capturedVideoInput.markAsFinished()
                        continuation.resume(throwing: ExportError.renderingFailed)
                        return
                    }
                    
                    // Append frame
                    let success = capturedAdaptor.append(buffer, withPresentationTime: presentationTime)
                    
                    if !success && currentFrame < 10 {
                        print("[VideoExporter] WARNING: Frame \(currentFrame) append failed")
                    }
                    
                    frameIndex += 1
                    
                    // Update progress on main thread
                    if currentFrame % 30 == 0 {
                        let currentProgress = Double(currentFrame) / Double(totalFrames) * 0.7
                        DispatchQueue.main.async {
                            self.progress = currentProgress
                        }
                    }
                    
                    // Log progress
                    if currentFrame < 10 || currentFrame % 100 == 0 {
                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        let fps = currentFrame > 0 ? Double(currentFrame) / elapsed : 0
                        print("[VideoExporter] Frame \(currentFrame)/\(totalFrames) (\(String(format: "%.1f", fps)) fps)")
                    }
                }
                
                // Check if done
                if frameIndex >= totalFrames {
                    let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                    print("[VideoExporter] All \(totalFrames) frames in \(String(format: "%.1f", totalTime))s (\(String(format: "%.1f", Double(frameIndex) / totalTime)) fps)")
                    capturedVideoInput.markAsFinished()
                    continuation.resume()
                }
            }
        }
        
        statusMessage = "Finalizing video..."
        print("[VideoExporter] Finalizing video track...")
        progress = 0.75
        
        await writer.finishWriting()
        
        if writer.status == .failed {
            print("[VideoExporter] ERROR: Video writer failed: \(writer.error?.localizedDescription ?? "unknown")")
            throw writer.error ?? ExportError.cannotCreateWriter
        }
        
        print("[VideoExporter] Video written successfully, now muxing audio...")
        statusMessage = "Adding audio..."
        progress = 0.80
        
        // Mux video and audio together using AVMutableComposition
        try await muxAudioWithVideo(videoURL: outputURL, audioAsset: audioAsset)
        
        progress = 1.0
        statusMessage = "Export complete!"
        print("[VideoExporter] Export complete!")
    }
    
    /// Mux audio track with the video file
    private func muxAudioWithVideo(videoURL: URL, audioAsset: AVAsset) async throws {
        // Create a temporary URL in the system temp directory (always writable)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nyaviz_temp_\(UUID().uuidString).mp4")
        
        // Create composition
        let composition = AVMutableComposition()
        
        // Load video asset we just created
        let videoAsset = AVAsset(url: videoURL)
        
        // Add video track
        guard let videoAssetTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            print("[VideoExporter] ERROR: Could not load video track")
            throw ExportError.cannotCreateWriter
        }
        
        let videoDuration = try await videoAsset.load(.duration)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoAssetTrack,
            at: .zero
        )
        
        print("[VideoExporter] Video track added to composition")
        
        // Add audio track
        if let audioAssetTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let audioDuration = try await audioAsset.load(.duration)
            // Use the shorter of video or audio duration
            let insertDuration = CMTimeMinimum(videoDuration, audioDuration)
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertDuration),
                of: audioAssetTrack,
                at: .zero
            )
            print("[VideoExporter] Audio track added to composition")
        }
        
        // Export the composition
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            print("[VideoExporter] ERROR: Could not create export session")
            throw ExportError.cannotCreateWriter
        }
        
        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mp4
        
        print("[VideoExporter] Starting final export...")
        progress = 0.85
        
        await exportSession.export()
        
        if exportSession.status == .failed {
            print("[VideoExporter] ERROR: Export session failed: \(exportSession.error?.localizedDescription ?? "unknown")")
            throw exportSession.error ?? ExportError.cannotCreateWriter
        }
        
        print("[VideoExporter] Muxing complete, replacing original file...")
        progress = 0.95
        
        // Replace original video-only file with muxed version
        try FileManager.default.removeItem(at: videoURL)
        try FileManager.default.moveItem(at: tempURL, to: videoURL)
        
        print("[VideoExporter] Final file ready at: \(videoURL.path)")
    }
    
    /// Calculate times when lyrics change (keyframes)
    private func calculateKeyframeTimes(
        lyrics: [Lyric],
        duration: TimeInterval,
        frameRate: Double
    ) -> Set<Int> {
        var keyframes = Set<Int>()
        
        // Add frame 0
        keyframes.insert(0)
        
        // Add frames when lyrics start/end
        for lyric in lyrics {
            let startFrame = Int(lyric.startTime * frameRate)
            let endFrame = Int(lyric.endTime * frameRate)
            keyframes.insert(startFrame)
            keyframes.insert(max(0, startFrame - 1))
            keyframes.insert(endFrame)
            keyframes.insert(min(Int(duration * frameRate), endFrame + 1))
        }
        
        return keyframes
    }
    
    /// Determine if a new frame needs to be rendered
    private func shouldRenderNewFrame(
        currentTime: TimeInterval,
        lyricIndex: Int,
        keyframeTimes: Set<Int>,
        settings: SettingsManager
    ) -> Bool {
        let frameNumber = Int(currentTime * frameRate)
        
        // Always render keyframes (lyric changes)
        if keyframeTimes.contains(frameNumber) {
            return true
        }
        
        // Render if lyric changed
        if lyricIndex != lastRenderedLyricIndex {
            return true
        }
        
        // For one-line mode, render less frequently when static
        if settings.lyricLinesVisible == 1 {
            // Only render at minimum intervals when lyrics are static
            if currentTime - lastRenderedTime < keyframeInterval {
                return false
            }
        }
        
        return true
    }
    
    // Frame render counter for logging
    private var frameRenderCount = 0
    
    /// Render frame with captured settings (thread-safe)
    @MainActor
    private func renderFrameWithSettings(
        at time: TimeInterval,
        simulatedPlayer: SimulatedAudioPlayer,
        capturedSettings: CapturedSettings,
        backgroundImage: NSImage?
    ) -> NSImage {
        frameRenderCount += 1
        let size = CGSize(width: videoWidth, height: videoHeight)
        
        // Create exportable view with captured settings
        let exportView = ExportableFullScreenViewStatic(
            simulatedPlayer: simulatedPlayer,
            capturedSettings: capturedSettings,
            backgroundImage: backgroundImage,
            size: size
        )
        
        let renderer = ImageRenderer(content: exportView.frame(width: size.width, height: size.height))
        renderer.scale = 1.0
        
        if let cgImage = renderer.cgImage {
            return NSImage(cgImage: cgImage, size: size)
        }
        
        // Fallback
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }
    
    /// Fast frame rendering using Core Graphics directly
    private func renderFrameFast(
        at time: TimeInterval,
        simulatedPlayer: SimulatedAudioPlayer,
        settings: SettingsManager
    ) -> NSImage {
        frameRenderCount += 1
        let size = CGSize(width: videoWidth, height: videoHeight)
        
        if frameRenderCount == 1 {
            print("[VideoExporter] renderFrameFast: Creating ExportableFullScreenView...")
        }
        
        // Use ImageRenderer for SwiftUI view
        let exportView = ExportableFullScreenView(
            simulatedPlayer: simulatedPlayer,
            settings: settings,
            size: size
        )
        
        if frameRenderCount == 1 {
            print("[VideoExporter] renderFrameFast: Creating ImageRenderer...")
        }
        
        let renderer = ImageRenderer(content: exportView.frame(width: size.width, height: size.height))
        renderer.scale = 1.0
        
        if frameRenderCount == 1 {
            print("[VideoExporter] renderFrameFast: Rendering to CGImage...")
        }
        
        if let cgImage = renderer.cgImage {
            if frameRenderCount == 1 {
                print("[VideoExporter] renderFrameFast: CGImage created successfully")
            }
            return NSImage(cgImage: cgImage, size: size)
        }
        
        print("[VideoExporter] renderFrameFast: WARNING - CGImage was nil, using fallback")
        
        // Fallback: create black frame
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }
    
    /// Create a CVPixelBuffer from NSImage - optimized
    private func createPixelBuffer(from image: NSImage) -> CVPixelBuffer? {
        guard let pixelBufferPool = pixelBufferAdaptor?.pixelBufferPool else {
            return createPixelBufferWithoutPool(from: image)
        }
        
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        
        guard let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: videoWidth,
            height: videoHeight,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        
        let rect = CGRect(x: 0, y: 0, width: videoWidth, height: videoHeight)
        context.clear(rect)
        
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: rect)
        }
        
        return buffer
    }
    
    private func createPixelBufferWithoutPool(from image: NSImage) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            videoWidth,
            videoHeight,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: videoWidth,
            height: videoHeight,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        
        let rect = CGRect(x: 0, y: 0, width: videoWidth, height: videoHeight)
        context.clear(rect)
        
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: rect)
        }
        
        return buffer
    }
    
    
    private func cleanup() {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        cachedPixelBuffer = nil
        lastRenderedLyricIndex = -999
        lastRenderedTime = -1
    }
}

// MARK: - Captured Settings (thread-safe snapshot)

/// Thread-safe snapshot of settings for background rendering
struct CapturedSettings: Sendable {
    let backgroundOpacity: Double
    let backgroundBlur: Double
    let showTrackTitle: Bool
    let showParticles: Bool
    let particleDensity: Double
    let lyricFontSize: CGFloat
    let lyricLinesVisible: Int
    let showVisualizer: Bool
    let visualizerIntensity: Double
    let colorBrightness: Double
    let dialogCharacterName: String
    let dialogMaxWidth: Double
    let dialogMaxHeight: Double
    let dialogPosition: Double

    @MainActor
    init(from settings: SettingsManager, options: ExportOptions) {
        self.backgroundOpacity = settings.backgroundOpacity
        self.backgroundBlur = settings.backgroundBlur
        self.showTrackTitle = settings.showTrackTitle
        // Use export options to override visualizer/particles
        self.showParticles = settings.showParticles && options.includeParticles
        self.particleDensity = settings.particleDensity
        self.lyricFontSize = settings.lyricFontSize
        self.lyricLinesVisible = settings.lyricLinesVisible
        self.showVisualizer = settings.showVisualizer && options.includeVisualizer
        self.visualizerIntensity = settings.visualizerIntensity
        self.colorBrightness = settings.colorBrightness
        self.dialogCharacterName = settings.dialogCharacterName
        self.dialogMaxWidth = settings.dialogMaxWidth
        self.dialogMaxHeight = settings.dialogMaxHeight
        self.dialogPosition = settings.dialogPosition
    }
}

// MARK: - Simulated Audio Player for Export

/// A simulated audio player that provides time-synced state for rendering
@MainActor
class SimulatedAudioPlayer: ObservableObject {
    let lyrics: [Lyric]
    let duration: TimeInterval
    let audioFileName: String
    
    @Published var currentTime: TimeInterval = 0
    @Published var currentLyricIndex: Int = -1
    @Published var isWithinLyricTimeRange: Bool = false
    @Published var frequencyBands: [Float] = Array(repeating: 0, count: 128)
    @Published var bassEnergy: Float = 0

    // Pre-computed random seeds for consistent visualizer animation
    private let visualizerSeeds: [Float]
    
    init(lyrics: [Lyric], duration: TimeInterval, audioFileName: String = "") {
        self.lyrics = lyrics
        self.duration = duration
        self.audioFileName = audioFileName
        
        // Pre-compute random seeds for visualizer
        var seeds = [Float]()
        for i in 0..<128 {
            seeds.append(Float.random(in: 0...1))
        }
        self.visualizerSeeds = seeds
    }
    
    func updateTime(_ time: TimeInterval) {
        currentTime = time
        updateCurrentLyric()
        generateVisualizerData(time: time)
    }
    
    private func updateCurrentLyric() {
        let time = currentTime
        
        if let index = lyrics.firstIndex(where: { time >= $0.startTime && time < $0.endTime }) {
            currentLyricIndex = index
            isWithinLyricTimeRange = true
        } else if let index = lyrics.lastIndex(where: { time >= $0.startTime }) {
            currentLyricIndex = index
            isWithinLyricTimeRange = false
        } else {
            currentLyricIndex = -1
            isWithinLyricTimeRange = false
        }
    }
    
    private func generateVisualizerData(time: TimeInterval) {
        // Fast visualizer generation using pre-computed seeds
        let timeFloat = Float(time)
        for i in 0..<frequencyBands.count {
            let seed = visualizerSeeds[i]
            let phase = sin(Double(timeFloat * 3 + seed * 10))
            let amplitude = 0.3 + 0.3 * sin(Double(timeFloat * 2 + seed * 5))
            frequencyBands[i] = Float(max(0.05, min(0.9, amplitude * (0.5 + 0.5 * phase))))
        }

        // Compute bass energy from first 20 bands
        let bassSum = frequencyBands.prefix(20).reduce(Float(0), +)
        bassEnergy = bassSum / 20.0
    }
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var hasLyrics: Bool {
        !lyrics.isEmpty
    }
    
    var oneLineModeLyric: AudioPlayerManager.MergedLyric? {
        let time = currentTime
        
        for lyric in lyrics {
            guard time >= lyric.startTime && time < lyric.endTime else { continue }
            let duration = lyric.endTime - lyric.startTime
            guard duration >= 0.25 else { continue }
            return AudioPlayerManager.MergedLyric(
                mainText: lyric.text,
                backgroundText: lyric.secondaryText,
                styledMainText: lyric.styledText,
                styledBackgroundText: lyric.styledSecondaryText
            )
        }
        
        var lastLyric: Lyric? = nil
        for lyric in lyrics {
            guard lyric.startTime <= time else { break }
            let duration = lyric.endTime - lyric.startTime
            guard duration >= 0.25 else { continue }
            lastLyric = lyric
        }
        
        if let last = lastLyric, time < last.endTime + 0.5 {
            let nextStart = lyrics.first(where: { lyric in
                let duration = lyric.endTime - lyric.startTime
                return lyric.startTime > last.endTime && duration >= 0.25
            })?.startTime ?? .infinity
            
            if time < nextStart {
                return AudioPlayerManager.MergedLyric(
                    mainText: last.text,
                    backgroundText: last.secondaryText,
                    styledMainText: last.styledText,
                    styledBackgroundText: last.styledSecondaryText
                )
            }
        }
        
        return nil
    }
}

// MARK: - Exportable Full Screen View (Static - uses CapturedSettings)

struct ExportableFullScreenViewStatic: View {
    let simulatedPlayer: SimulatedAudioPlayer
    let capturedSettings: CapturedSettings
    let backgroundImage: NSImage?
    let size: CGSize

    // Scale factor relative to 1080p reference resolution
    private var scale: CGFloat {
        size.height / 1080.0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            ZStack {
                SettingsManager.background

                if let image = backgroundImage {
                    let driftPhase = AmbientVisualizerTuning.backgroundDriftPhase(
                        time: simulatedPlayer.currentTime
                    )
                    let drift = AmbientVisualizerTuning.backgroundDrift(
                        size: size,
                        phase: driftPhase
                    )
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: size.width * AmbientVisualizerTuning.backgroundFrameExpansion,
                                height: size.height * AmbientVisualizerTuning.backgroundFrameExpansion
                            )
                            .offset(drift)
                            .blur(radius: capturedSettings.backgroundBlur * scale)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .opacity(capturedSettings.backgroundOpacity)
                }

                Color.black.opacity(0.3)

                if capturedSettings.showParticles {
                    ExportableDustMoteViewStatic(
                        density: capturedSettings.particleDensity,
                        bassEnergy: simulatedPlayer.bassEnergy,
                        intensity: capturedSettings.showVisualizer ? capturedSettings.visualizerIntensity : 0,
                        time: simulatedPlayer.currentTime,
                        size: size
                    )
                }
            }

            // Centered lyrics
            if simulatedPlayer.hasLyrics {
                if capturedSettings.lyricLinesVisible == 4 {
                    ExportableDialogLyricStatic(
                        simulatedPlayer: simulatedPlayer,
                        capturedSettings: capturedSettings,
                        size: size,
                        scale: scale
                    )
                } else if capturedSettings.lyricLinesVisible == 1 {
                    ExportableOneLineLyricStatic(
                        simulatedPlayer: simulatedPlayer,
                        fontSize: capturedSettings.lyricFontSize * scale,
                        colorBrightness: capturedSettings.colorBrightness
                    )
                } else {
                    ExportableSmoothLyricsStatic(
                        simulatedPlayer: simulatedPlayer,
                        fontSize: capturedSettings.lyricFontSize * scale,
                        visibleRange: capturedSettings.lyricLinesVisible,
                        containerHeight: size.height,
                        colorBrightness: capturedSettings.colorBrightness
                    )
                }
            }

            // Track info at top left - all sizes scaled to resolution
            if capturedSettings.showTrackTitle && !simulatedPlayer.audioFileName.isEmpty {
                let ringSize: CGFloat = 32 * scale
                let titleFontSize: CGFloat = 14 * scale
                let timeFontSize: CGFloat = 11 * scale
                let iconSize: CGFloat = 9 * scale
                let strokeWidth: CGFloat = 2 * scale
                let spacing: CGFloat = 12 * scale
                let padding: CGFloat = 24 * scale

                VStack {
                    HStack(alignment: .center, spacing: spacing) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: strokeWidth)
                                .frame(width: ringSize, height: ringSize)

                            Circle()
                                .trim(from: 0, to: simulatedPlayer.progress)
                                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                                .frame(width: ringSize, height: ringSize)
                                .rotationEffect(.degrees(-90))

                            Image(systemName: "play.fill")
                                .font(.system(size: iconSize))
                                .foregroundColor(.white.opacity(0.8))
                        }

                        VStack(alignment: .leading, spacing: 2 * scale) {
                            Text(simulatedPlayer.audioFileName)
                                .font(.system(size: titleFontSize, weight: .medium, design: .default))
                                .foregroundColor(.white.opacity(0.8))

                            Text(formatTime(simulatedPlayer.currentTime) + " / " + formatTime(simulatedPlayer.duration))
                                .font(.system(size: timeFontSize, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, padding)
                    .padding(.top, 20 * scale)

                    Spacer()
                }
            }

        }
        .frame(width: size.width, height: size.height)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Static versions of subviews for thread-safe rendering

struct ExportableDustMoteViewStatic: View {
    let density: Double
    let bassEnergy: Float
    let intensity: Double
    let time: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            drawParticles(context: context, size: size)
        }
    }

    private func hash(_ n: Int) -> Double {
        var x = UInt64(abs(n) &+ 1)
        x = ((x >> 16) ^ x) &* 0x45d9f3b
        x = ((x >> 16) ^ x) &* 0x45d9f3b
        x = (x >> 16) ^ x
        return Double(x % 10000) / 10000.0
    }

    private func drawParticles(context: GraphicsContext, size: CGSize) {
        let particleCount = AmbientVisualizerTuning.particleCount(density: density)

        for i in 0..<particleCount {
            let xRandom = hash(i * 7919)
            let yRandom = hash(i * 6271)
            let speedRandom = hash(i * 5147)
            let sizeRandom = hash(i * 4219)
            let opacityRandom = hash(i * 3571)
            let driftXRandom = hash(i * 2957)
            let driftYRandom = hash(i * 2381)

            let baseSize = 1.0 + sizeRandom * 2.0
            let baseOpacity = 0.15 + opacityRandom * 0.2
            let particleSize = AmbientVisualizerTuning.particleSize(
                baseSize: baseSize,
                bassEnergy: bassEnergy,
                intensity: intensity
            )
            let opacity = AmbientVisualizerTuning.particleOpacity(
                baseOpacity: baseOpacity,
                bassEnergy: bassEnergy,
                intensity: intensity
            )

            let speed = 5 + speedRandom * 10
            let driftAngle = driftXRandom * .pi * 2
            let dx = cos(driftAngle) * speed
            let dy = sin(driftAngle) * speed
            let beatOffset = AmbientVisualizerTuning.particleBeatOffset(
                bassEnergy: bassEnergy,
                intensity: intensity,
                direction: driftAngle + driftYRandom * 1.2,
                variance: sizeRandom
            )

            let baseX = xRandom * size.width
            let baseY = yRandom * size.height
            let wanderX = sin(time * 0.2 + Double(i) * 1.7) * (20 + driftYRandom * 30)
            let wanderY = cos(time * 0.15 + Double(i) * 2.3) * (15 + driftXRandom * 25)

            let x = (baseX + dx * time.truncatingRemainder(dividingBy: 200) + wanderX)
                .truncatingRemainder(dividingBy: size.width + 20) - 10
            let y = (baseY + dy * time.truncatingRemainder(dividingBy: 200) + wanderY)
                .truncatingRemainder(dividingBy: size.height + 20) - 10
            let pulsedX = x + beatOffset.width
            let pulsedY = y + beatOffset.height

            let rect = CGRect(
                x: pulsedX - particleSize / 2,
                y: pulsedY - particleSize / 2,
                width: particleSize,
                height: particleSize
            )

            context.fill(
                Circle().path(in: rect),
                with: .color(.white.opacity(opacity))
            )
        }
    }
}

struct ExportableOneLineLyricStatic: View {
    let simulatedPlayer: SimulatedAudioPlayer
    let fontSize: CGFloat
    let colorBrightness: Double

    var body: some View {
        VStack {
            Spacer()

            if let lyric = simulatedPlayer.oneLineModeLyric {
                VStack(spacing: fontSize * 0.2) {
                    if lyric.hasStyles {
                        lyric.styledMainText.attributedText(
                            font: .custom("MollenTrial-Bold", size: fontSize * 1.3),
                            brightness: colorBrightness,
                            uppercased: true
                        )
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                    } else {
                        Text(lyric.mainText.uppercased())
                            .font(.custom("MollenTrial-Bold", size: fontSize * 1.3))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                    }

                    if let styledBg = lyric.styledBackgroundText {
                        if styledBg.hasStyles {
                            styledBg.attributedText(
                                font: .custom("MollenTrial-Bold", size: fontSize * 0.85),
                                opacity: 0.5,
                                brightness: colorBrightness,
                                uppercased: true
                            )
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        } else {
                            Text(styledBg.plainText.uppercased())
                                .font(.custom("MollenTrial-Bold", size: fontSize * 0.85))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                }
                .padding(.horizontal, fontSize * 1.25)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ExportableSmoothLyricsStatic: View {
    let simulatedPlayer: SimulatedAudioPlayer
    let fontSize: CGFloat
    let visibleRange: Int
    let containerHeight: CGFloat
    let colorBrightness: Double

    private var lineSpacing: CGFloat { fontSize * 0.42 }
    private var adjustedFontSize: CGFloat { fontSize * 1.2 }
    private var lineHeight: CGFloat { adjustedFontSize * 2.0 }
    private var totalLineHeight: CGFloat { lineHeight + lineSpacing }

    var body: some View {
        ZStack {
            ForEach(-visibleRange...visibleRange, id: \.self) { offset in
                let index = simulatedPlayer.currentLyricIndex + offset
                if index >= 0 && index < simulatedPlayer.lyrics.count {
                    let lyric = simulatedPlayer.lyrics[index]
                    let relativeOffset = CGFloat(offset)

                    lyricLine(lyric: lyric, relativePosition: relativeOffset)
                        .frame(minHeight: lineHeight)
                        .offset(y: relativeOffset * totalLineHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .padding(.horizontal, fontSize * 1.25)
    }

    @ViewBuilder
    private func lyricLine(lyric: Lyric, relativePosition: CGFloat) -> some View {
        let distance = abs(relativePosition)
        let isActive = distance < 0.5
        let opacity = distance < 0.1 ? 1.0 : max(0.06, 0.35 - (distance / max(CGFloat(visibleRange), 1)) * 0.2)
        let scale = distance < 0.1 ? 1.0 : max(0.72, 0.9 - (distance / max(CGFloat(visibleRange), 1)) * 0.12)
        let mainSize: CGFloat = isActive ? adjustedFontSize * 1.08 : adjustedFontSize * 0.85
        let mainWeight: Font.Weight = isActive ? .heavy : .bold
        let secondarySize: CGFloat = isActive ? adjustedFontSize * 0.8 : adjustedFontSize * 0.65
        let secondaryWeight: Font.Weight = isActive ? .semibold : .medium

        VStack(spacing: fontSize * 0.1) {
            if lyric.styledText.hasStyles {
                lyric.styledText.attributedText(
                    font: .system(size: mainSize, weight: mainWeight),
                    opacity: opacity,
                    brightness: colorBrightness
                )
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            } else {
                Text(lyric.text)
                    .font(.system(size: mainSize, weight: mainWeight))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundColor(.white.opacity(opacity))
            }

            if let styledSecondary = lyric.styledSecondaryText {
                if styledSecondary.hasStyles {
                    styledSecondary.attributedText(
                        font: .system(size: secondarySize, weight: secondaryWeight),
                        opacity: opacity * 0.6,
                        brightness: colorBrightness
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                } else {
                    Text(styledSecondary.plainText)
                        .font(.system(size: secondarySize, weight: secondaryWeight))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundColor(.white.opacity(opacity * 0.6))
                }
            }
        }
        .scaleEffect(scale)
        .frame(maxWidth: .infinity)
    }
}

struct ExportableDialogLyricStatic: View {
    let simulatedPlayer: SimulatedAudioPlayer
    let capturedSettings: CapturedSettings
    let size: CGSize
    let scale: CGFloat

    private var displayName: String {
        capturedSettings.dialogCharacterName.isEmpty ? "CHARACTER" : capturedSettings.dialogCharacterName
    }

    var body: some View {
        let fontSize = capturedSettings.lyricFontSize * scale * 0.85
        let dialogMaxWidth = size.width * capturedSettings.dialogMaxWidth
        let dialogMaxHeight = size.height * capturedSettings.dialogMaxHeight
        let horizontalMargin = (size.width - dialogMaxWidth) / 2
        let nameTagFontSize = max(11 * scale, min(14 * scale, size.width * 0.012))
        let topSpacerHeight = size.height * capturedSettings.dialogPosition - (dialogMaxHeight / 2)

        VStack {
            Spacer().frame(height: max(0, topSpacerHeight))

            HStack {
                Spacer(minLength: max(horizontalMargin, 24 * scale))

                VStack(alignment: .leading, spacing: 0) {
                    // Character name tag
                    HStack {
                        Text(displayName.uppercased())
                            .font(.custom("MollenTrial-Bold", size: nameTagFontSize))
                            .tracking(2 * scale)
                            .foregroundColor(.white.opacity(0.95))
                            .padding(.horizontal, 14 * scale)
                            .padding(.vertical, 6 * scale)
                            .background(Rectangle().fill(Color.white.opacity(0.12)))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.3), lineWidth: 2 * scale))
                            .offset(x: -2 * scale, y: -1 * scale)
                        Spacer()
                    }
                    .offset(y: 1 * scale)

                    // Dialog box
                    VStack(spacing: 0) {
                        if let lyric = simulatedPlayer.oneLineModeLyric {
                            if lyric.hasStyles {
                                lyric.styledMainText.attributedText(
                                    font: .custom("MollenTrial-Bold", size: fontSize),
                                    brightness: capturedSettings.colorBrightness,
                                    uppercased: true
                                )
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .minimumScaleFactor(0.5)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                            } else {
                                Text(lyric.mainText.uppercased())
                                    .font(.custom("MollenTrial-Bold", size: fontSize))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(4)
                                    .minimumScaleFactor(0.5)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            Text("...")
                                .font(.custom("MollenTrial-Bold", size: fontSize))
                                .foregroundColor(.white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 32 * scale)
                    .padding(.vertical, 20 * scale)
                    .frame(maxWidth: dialogMaxWidth, maxHeight: dialogMaxHeight)
                    .background(
                        Rectangle().fill(Color.black.opacity(0.65))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.35), lineWidth: 3 * scale))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1 * scale).padding(4 * scale))
                    )
                }
                .frame(maxWidth: dialogMaxWidth)

                Spacer(minLength: max(horizontalMargin, 24 * scale))
            }

            Spacer()
        }
    }
}


// MARK: - Exportable Full Screen View (Original - uses SettingsManager)

struct ExportableFullScreenView: View {
    let simulatedPlayer: SimulatedAudioPlayer
    let settings: SettingsManager
    let size: CGSize
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            ExportableBackgroundView(settings: settings, simulatedPlayer: simulatedPlayer, size: size, time: simulatedPlayer.currentTime)
            
            // Centered lyrics
            if simulatedPlayer.hasLyrics {
                if settings.lyricLinesVisible == 1 {
                    ExportableOneLineLyric(simulatedPlayer: simulatedPlayer, settings: settings)
                } else {
                    ExportableSmoothLyrics(
                        simulatedPlayer: simulatedPlayer,
                        settings: settings,
                        containerHeight: size.height
                    )
                }
            } else {
                Image(systemName: "text.quote")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundColor(Color.white.opacity(0.1))
            }
            
            // Track info at top left
            if settings.showTrackTitle && !simulatedPlayer.audioFileName.isEmpty {
                VStack {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 2)
                                .frame(width: 32, height: 32)
                            
                            Circle()
                                .trim(from: 0, to: simulatedPlayer.progress)
                                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 32, height: 32)
                                .rotationEffect(.degrees(-90))
                            
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(simulatedPlayer.audioFileName)
                                .font(.system(size: 14, weight: .medium, design: .default))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text(formatTime(simulatedPlayer.currentTime) + " / " + formatTime(simulatedPlayer.duration))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    Spacer()
                }
            }
            
        }
        .frame(width: size.width, height: size.height)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Exportable Background (Optimized)

struct ExportableBackgroundView: View {
    let settings: SettingsManager
    let simulatedPlayer: SimulatedAudioPlayer
    let size: CGSize
    let time: TimeInterval

    var body: some View {
        ZStack {
            SettingsManager.background

            if let image = settings.backgroundImage {
                let driftPhase = AmbientVisualizerTuning.backgroundDriftPhase(time: time)
                let drift = AmbientVisualizerTuning.backgroundDrift(size: size, phase: driftPhase)
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: size.width * AmbientVisualizerTuning.backgroundFrameExpansion,
                            height: size.height * AmbientVisualizerTuning.backgroundFrameExpansion
                        )
                        .offset(drift)
                        .blur(radius: settings.backgroundBlur)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .opacity(settings.backgroundOpacity)
            }

            Color.black.opacity(0.3)

            if settings.showParticles {
                ExportableDustMoteView(
                    density: settings.particleDensity,
                    bassEnergy: simulatedPlayer.bassEnergy,
                    intensity: settings.showVisualizer ? settings.visualizerIntensity : 0,
                    time: time,
                    size: size
                )
            }
        }
    }
}

struct ExportableDustMoteView: View {
    let density: Double
    let bassEnergy: Float
    let intensity: Double
    let time: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            drawParticles(context: context, size: size)
        }
    }

    private func hash(_ n: Int) -> Double {
        var x = UInt64(abs(n) &+ 1)
        x = ((x >> 16) ^ x) &* 0x45d9f3b
        x = ((x >> 16) ^ x) &* 0x45d9f3b
        x = (x >> 16) ^ x
        return Double(x % 10000) / 10000.0
    }

    private func drawParticles(context: GraphicsContext, size: CGSize) {
        let particleCount = AmbientVisualizerTuning.particleCount(density: density)

        for i in 0..<particleCount {
            let xRandom = hash(i * 7919)
            let yRandom = hash(i * 6271)
            let speedRandom = hash(i * 5147)
            let sizeRandom = hash(i * 4219)
            let opacityRandom = hash(i * 3571)
            let driftXRandom = hash(i * 2957)
            let driftYRandom = hash(i * 2381)

            let baseSize = 1.0 + sizeRandom * 2.0
            let baseOpacity = 0.15 + opacityRandom * 0.2
            let particleSize = AmbientVisualizerTuning.particleSize(
                baseSize: baseSize,
                bassEnergy: bassEnergy,
                intensity: intensity
            )
            let opacity = AmbientVisualizerTuning.particleOpacity(
                baseOpacity: baseOpacity,
                bassEnergy: bassEnergy,
                intensity: intensity
            )

            let speed = 5 + speedRandom * 10
            let driftAngle = driftXRandom * .pi * 2
            let dx = cos(driftAngle) * speed
            let dy = sin(driftAngle) * speed
            let beatOffset = AmbientVisualizerTuning.particleBeatOffset(
                bassEnergy: bassEnergy,
                intensity: intensity,
                direction: driftAngle + driftYRandom * 1.2,
                variance: sizeRandom
            )

            let baseX = xRandom * size.width
            let baseY = yRandom * size.height
            let wanderX = sin(time * 0.2 + Double(i) * 1.7) * (20 + driftYRandom * 30)
            let wanderY = cos(time * 0.15 + Double(i) * 2.3) * (15 + driftXRandom * 25)

            let x = (baseX + dx * time.truncatingRemainder(dividingBy: 200) + wanderX)
                .truncatingRemainder(dividingBy: size.width + 20) - 10
            let y = (baseY + dy * time.truncatingRemainder(dividingBy: 200) + wanderY)
                .truncatingRemainder(dividingBy: size.height + 20) - 10
            let pulsedX = x + beatOffset.width
            let pulsedY = y + beatOffset.height

            let rect = CGRect(
                x: pulsedX - particleSize / 2,
                y: pulsedY - particleSize / 2,
                width: particleSize,
                height: particleSize
            )

            context.fill(
                Circle().path(in: rect),
                with: .color(.white.opacity(opacity))
            )
        }
    }
}

// MARK: - Exportable Lyrics

struct ExportableOneLineLyric: View {
    let simulatedPlayer: SimulatedAudioPlayer
    let settings: SettingsManager
    
    var body: some View {
        VStack {
            Spacer()
            
            if let lyric = simulatedPlayer.oneLineModeLyric {
                VStack(spacing: 10) {
                    Text(lyric.mainText.uppercased())
                        .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 1.3))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                    
                    if let background = lyric.backgroundText {
                        Text(background.uppercased())
                            .font(.custom("MollenTrial-Bold", size: settings.lyricFontSize * 0.85))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                .padding(.horizontal, 60)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ExportableSmoothLyrics: View {
    let simulatedPlayer: SimulatedAudioPlayer
    let settings: SettingsManager
    let containerHeight: CGFloat
    
    private let lineSpacing: CGFloat = 24
    
    private var fontSize: CGFloat {
        settings.lyricFontSize * 1.2
    }
    
    private var lineHeight: CGFloat {
        fontSize * 2.0
    }
    
    private var totalLineHeight: CGFloat {
        lineHeight + lineSpacing
    }
    
    private var visibleRange: Int {
        settings.lyricLinesVisible
    }
    
    var body: some View {
        ZStack {
            ForEach(-visibleRange...visibleRange, id: \.self) { offset in
                let index = simulatedPlayer.currentLyricIndex + offset
                if index >= 0 && index < simulatedPlayer.lyrics.count {
                    let lyric = simulatedPlayer.lyrics[index]
                    let relativeOffset = CGFloat(offset)
                    
                    ExportableLyricLine(
                        text: lyric.text,
                        secondaryText: lyric.secondaryText,
                        relativePosition: relativeOffset,
                        fontSize: fontSize,
                        maxDistance: CGFloat(visibleRange)
                    )
                    .frame(minHeight: lineHeight)
                    .offset(y: relativeOffset * totalLineHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .padding(.horizontal, 60)
    }
}

struct ExportableLyricLine: View {
    let text: String
    let secondaryText: String?
    let relativePosition: CGFloat
    let fontSize: CGFloat
    let maxDistance: CGFloat
    
    private var opacity: Double {
        let distance = abs(relativePosition)
        if distance < 0.1 { return 1.0 }
        let normalized = distance / max(maxDistance, 1)
        return max(0.06, 0.35 - normalized * 0.2)
    }
    
    private var scale: CGFloat {
        let distance = abs(relativePosition)
        if distance < 0.1 { return 1.0 }
        let normalized = distance / max(maxDistance, 1)
        return max(0.72, 0.9 - normalized * 0.12)
    }
    
    private var isActive: Bool {
        abs(relativePosition) < 0.5
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Text(text)
                .font(.system(size: isActive ? fontSize * 1.08 : fontSize * 0.85, weight: isActive ? .heavy : .bold, design: .default))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .foregroundColor(.white.opacity(opacity))
            
            if let secondary = secondaryText {
                Text(secondary)
                    .font(.system(size: isActive ? fontSize * 0.8 : fontSize * 0.65, weight: isActive ? .semibold : .medium, design: .default))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundColor(.white.opacity(opacity * 0.6))
            }
        }
        .scaleEffect(scale)
        .frame(maxWidth: .infinity)
    }
}
