//
//  AudioPlayerManager.swift
//  NyaViz
//

import Foundation
import AVFoundation
import Accelerate
import Combine

@MainActor
class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var lyrics: [Lyric] = []
    @Published var currentLyricIndex: Int = -1
    @Published var isWithinLyricTimeRange: Bool = false  // True only when strictly within a lyric's start/end time
    @Published var audioFileName: String = ""
    @Published var showFilePicker = false
    @Published var showSRTPicker = false
    @Published var isLooping = true
    @Published var volume: Float = 0.8
    
    // Frequency bands for visualizer (normalized 0-1)
    @Published var frequencyBands: [Float] = Array(repeating: 0, count: 128)
    
    // Audio engine components
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    
    // Track the seek offset for accurate time calculation
    private var seekOffset: TimeInterval = 0
    
    // Generation counter to invalidate old completion handlers after seek/reschedule
    private var scheduleGeneration: Int = 0
    
    // FFT setup
    private var fftSetup: FFTSetup?
    private let fftSize: Int = 2048
    private var log2n: vDSP_Length = 0
    private var realPart: [Float] = []
    private var imaginaryPart: [Float] = []
    private var window: [Float] = []
    private var smoothedBands: [Float] = Array(repeating: 0, count: 128)
    private var lastBandsUpdateTime: CFAbsoluteTime = 0
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupFFT()
        setupVolumeObserver()
    }
    
    private func setupFFT() {
        log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        realPart = [Float](repeating: 0, count: fftSize / 2)
        imaginaryPart = [Float](repeating: 0, count: fftSize / 2)
        
        // Create Hann window for better frequency resolution
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }
    
    private func setupVolumeObserver() {
        $volume
            .sink { [weak self] newVolume in
                self?.audioEngine?.mainMixerNode.outputVolume = newVolume
            }
            .store(in: &cancellables)
    }
    
    func loadAudio(from url: URL) {
        // Stop any existing playback
        stop()
        
        do {
            audioFileURL = url
            audioFile = try AVAudioFile(forReading: url)
            
            guard let file = audioFile else { return }
            
            duration = Double(file.length) / file.processingFormat.sampleRate
            audioFileName = url.deletingPathExtension().lastPathComponent
            currentTime = 0
            
            setupAudioEngine()
            
        } catch {
            print("Error loading audio: \(error.localizedDescription)")
        }
    }
    
    private func setupAudioEngine() {
        guard let file = audioFile else { return }
        
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        guard let engine = audioEngine, let player = playerNode else { return }
        
        let format = file.processingFormat
        
        // Attach and connect nodes
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        
        // Set initial volume
        engine.mainMixerNode.outputVolume = volume
        
        // Install tap for FFT analysis
        let bufferSize: AVAudioFrameCount = AVAudioFrameCount(fftSize)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try engine.start()
        } catch {
            print("Error starting audio engine: \(error)")
        }
    }
    
    /// Load lyrics from SRT or NyaViz format files
    func loadSRT(from url: URL) {
        lyrics = SubtitleLoader.load(from: url)
        currentLyricIndex = -1
        updateCurrentLyric()
        let formatName = url.pathExtension.lowercased() == "nyaviz" ? "NyaViz" : "SRT"
        print("Loaded \(lyrics.count) lyrics from \(formatName)")
    }
    
    func play() {
        guard let player = playerNode, audioFile != nil, let engine = audioEngine else { return }
        
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("Error starting engine: \(error)")
                return
            }
        }
        
        // Schedule the file from current position (scheduleAudio sets seekOffset)
        scheduleAudio(from: currentTime)
        player.play()
        
        isPlaying = true
        startTimer()
    }
    
    private func scheduleAudio(from time: TimeInterval) {
        // Increment generation to invalidate any pending completion handlers
        scheduleGeneration += 1
        let currentGeneration = scheduleGeneration
        
        guard let player = playerNode, let file = audioFile else { return }
        
        player.stop()
        
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(time * sampleRate)
        let totalFrames = file.length
        let frameCount = AVAudioFrameCount(totalFrames - startFrame)
        
        guard frameCount > 0, startFrame < totalFrames else { return }
        
        // Update seekOffset to match the scheduled time
        seekOffset = time
        
        if isLooping {
            // Schedule current segment, then set up completion handler for looping
            player.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    
                    // Only loop if this completion handler is for the CURRENT schedule
                    // If we've rescheduled (seek), the generation won't match and we should ignore
                    guard currentGeneration == self.scheduleGeneration else { return }
                    guard self.isLooping, self.isPlaying else { return }
                    
                    self.currentTime = 0
                    self.seekOffset = 0
                    self.scheduleAudio(from: 0)
                    self.playerNode?.play()
                }
            }
        } else {
            player.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
                guard self != nil else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard currentGeneration == self.scheduleGeneration else { return }
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }
    
    func pause() {
        playerNode?.pause()
        isPlaying = false
        stopTimer()
        
        // Fade out frequency bands
        for i in 0..<frequencyBands.count {
            smoothedBands[i] = 0
        }
        frequencyBands = smoothedBands
    }
    
    func stop() {
        playerNode?.stop()
        audioEngine?.mainMixerNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        
        isPlaying = false
        currentTime = 0
        seekOffset = 0  // Reset offset
        stopTimer()
        
        // Reset frequency bands
        smoothedBands = Array(repeating: 0, count: 128)
        frequencyBands = smoothedBands
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying
        
        if wasPlaying {
            playerNode?.stop()
        }
        
        currentTime = max(0, min(time, duration))
        seekOffset = currentTime
        updateCurrentLyric()
        
        if wasPlaying {
            scheduleAudio(from: currentTime)
            playerNode?.play()
        }
    }
    
    func seekForward(_ seconds: TimeInterval = 5) {
        seek(to: currentTime + seconds)
    }
    
    func seekBackward(_ seconds: TimeInterval = 5) {
        seek(to: currentTime - seconds)
    }
    
    func toggleLoop() {
        isLooping.toggle()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                
                // Update current time based on player position + seek offset
                if let player = self.playerNode, let nodeTime = player.lastRenderTime,
                   let playerTime = player.playerTime(forNodeTime: nodeTime) {
                    let sampleRate = self.audioFile?.processingFormat.sampleRate ?? 44100
                    let playerSeconds = Double(playerTime.sampleTime) / sampleRate
                    
                    // Add the seek offset to get absolute time in file
                    let calculatedTime = self.seekOffset + playerSeconds
                    
                    // Only update if the calculated time is valid and has changed meaningfully
                    // This reduces unnecessary @Published updates
                    if calculatedTime >= 0 && abs(calculatedTime - self.currentTime) > 0.001 {
                        self.currentTime = calculatedTime
                    }
                    
                    // Handle end of track
                    if self.currentTime >= self.duration {
                        if self.isLooping {
                            self.currentTime = 0
                            self.seekOffset = 0
                        }
                    }
                }
                
                self.updateCurrentLyric()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        
        guard frameLength >= fftSize else { return }
        
        // Apply window function
        var windowedSamples = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(channelData, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))
        
        // Perform FFT with proper memory management
        let halfSize = fftSize / 2
        var localRealPart = [Float](repeating: 0, count: halfSize)
        var localImagPart = [Float](repeating: 0, count: halfSize)
        
        localRealPart.withUnsafeMutableBufferPointer { realPtr in
            localImagPart.withUnsafeMutableBufferPointer { imagPtr in
                var complexBuffer = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                
                windowedSamples.withUnsafeBufferPointer { samplesPtr in
                    samplesPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &complexBuffer, 1, vDSP_Length(halfSize))
                    }
                }
                
                guard let fftSetup = fftSetup else { return }
                vDSP_fft_zrip(fftSetup, &complexBuffer, 1, log2n, FFTDirection(FFT_FORWARD))
                
                // Calculate magnitudes
                var magnitudes = [Float](repeating: 0, count: halfSize)
                vDSP_zvmags(&complexBuffer, 1, &magnitudes, 1, vDSP_Length(halfSize))
                
                // Take square root to get actual magnitude (zvmags gives squared magnitudes)
                var sqrtMagnitudes = [Float](repeating: 0, count: halfSize)
                var length = Int32(halfSize)
                vvsqrtf(&sqrtMagnitudes, magnitudes, &length)
                
                // Normalize by FFT size
                var scale = Float(1.0 / Float(self.fftSize))
                var scaledMagnitudes = [Float](repeating: 0, count: halfSize)
                vDSP_vsmul(sqrtMagnitudes, 1, &scale, &scaledMagnitudes, 1, vDSP_Length(halfSize))
                
                // Map FFT bins to frequency bands with logarithmic scaling
                let bandCount = 128
                var bands = [Float](repeating: 0, count: bandCount)
                
                // Find the max magnitude for dynamic normalization
                var maxMag: Float = 0
                vDSP_maxv(scaledMagnitudes, 1, &maxMag, vDSP_Length(halfSize))
                let normalizer = max(maxMag, 0.001)  // Avoid division by zero
                
                for i in 0..<bandCount {
                    // Logarithmic mapping for more natural visualization
                    let lowFreq = pow(Float(i) / Float(bandCount), 2.0) * Float(halfSize - 1)
                    let highFreq = pow(Float(i + 1) / Float(bandCount), 2.0) * Float(halfSize - 1)
                    
                    let lowBin = max(1, Int(lowFreq))  // Skip DC bin
                    let highBin = max(lowBin + 1, Int(highFreq))
                    
                    var maxInBand: Float = 0
                    for bin in lowBin..<min(highBin, halfSize) {
                        maxInBand = max(maxInBand, scaledMagnitudes[bin])
                    }
                    
                    // Normalize relative to max and apply curve for better dynamics
                    let normalized = maxInBand / normalizer
                    bands[i] = pow(normalized, 0.6)  // Compress dynamic range slightly
                }
                
                // Apply frequency-dependent boost
                for i in 0..<bandCount {
                    let position = Float(i) / Float(bandCount)
                    
                    // Boost bass (first 20%) more dramatically
                    var boost: Float = 1.0
                    if position < 0.2 {
                        boost = 1.4
                    } else if position < 0.4 {
                        boost = 1.1
                    } else if position > 0.85 {
                        boost = 1.2
                    }
                    
                    bands[i] = min(1.0, bands[i] * boost)
                }
                
                // Smooth with fast attack, slower release
                let attackSpeed: Float = 0.7
                let releaseSpeed: Float = 0.25
                
                for i in 0..<bandCount {
                    if bands[i] > self.smoothedBands[i] {
                        self.smoothedBands[i] = self.smoothedBands[i] + (bands[i] - self.smoothedBands[i]) * attackSpeed
                    } else {
                        self.smoothedBands[i] = self.smoothedBands[i] + (bands[i] - self.smoothedBands[i]) * releaseSpeed
                    }
                }
                
                // Throttle UI updates to ~60fps to avoid "Publishing changes from within view updates" warnings
                let now = CFAbsoluteTimeGetCurrent()
                if now - self.lastBandsUpdateTime >= 0.016 {
                    self.lastBandsUpdateTime = now
                    let resultBands = self.smoothedBands
                    Task { @MainActor [weak self] in
                        self?.frequencyBands = resultBands
                    }
                }
            }
        }
    }
    
    private func updateCurrentLyric() {
        let time = currentTime
        
        // Check if we're strictly within a lyric's time range
        if let index = lyrics.firstIndex(where: { time >= $0.startTime && time < $0.endTime }) {
            if currentLyricIndex != index {
                currentLyricIndex = index
            }
            if !isWithinLyricTimeRange {
                isWithinLyricTimeRange = true
            }
        } else if let index = lyrics.lastIndex(where: { time >= $0.startTime }) {
            // Fallback for normal mode: show last started lyric
            if currentLyricIndex != index {
                currentLyricIndex = index
            }
            // But we're not within the time range anymore
            if isWithinLyricTimeRange {
                isWithinLyricTimeRange = false
            }
        } else {
            if currentLyricIndex != -1 {
                currentLyricIndex = -1
            }
            if isWithinLyricTimeRange {
                isWithinLyricTimeRange = false
            }
        }
    }
    
    // MARK: - One-Line Mode Helpers (with merged background vocals)
    
    /// Minimum duration for a lyric to be displayed (filters out flickering)
    private static let minLyricDuration: TimeInterval = 0.25
    
    /// A merged lyric pair: main lyric on top, optional background vocal below
    struct MergedLyric: Equatable {
        let mainText: String
        let backgroundText: String? // Parenthetical backup vocals
        
        // Styled versions for color/formatting support
        let styledMainText: StyledLine
        let styledBackgroundText: StyledLine?
        
        var displayId: String {
            mainText + (backgroundText ?? "")
        }
        
        /// Whether this lyric has styled text
        var hasStyles: Bool {
            styledMainText.hasStyles || (styledBackgroundText?.hasStyles ?? false)
        }
    }
    
    /// Returns the current merged lyric for one-line mode
    /// Main lyrics appear on top, secondary text (translation) appears below
    /// Filters out lyrics shorter than minLyricDuration to prevent flickering
    var oneLineModeLyric: MergedLyric? {
        let time = currentTime
        
        // Find the current lyric at this time (with minimum duration)
        // Lyrics are now pre-merged with secondaryText at parse time
        for lyric in lyrics {
            guard time >= lyric.startTime && time < lyric.endTime else { continue }
            
            // Skip lyrics that are too short (causes flickering)
            let duration = lyric.endTime - lyric.startTime
            guard duration >= Self.minLyricDuration else { continue }
            
            // Return the lyric with its styled text
            return MergedLyric(
                mainText: lyric.text,
                backgroundText: lyric.secondaryText,
                styledMainText: lyric.styledText,
                styledBackgroundText: lyric.styledSecondaryText
            )
        }
        
        // Check if we should extend a previous lyric (to bridge short gaps)
        var lastLyric: Lyric? = nil
        for lyric in lyrics {
            guard lyric.startTime <= time else { break }
            let duration = lyric.endTime - lyric.startTime
            guard duration >= Self.minLyricDuration else { continue }
            lastLyric = lyric
        }
        
        if let last = lastLyric, time < last.endTime + 0.5 {
            // Check if there's a gap before the next valid lyric
            let nextStart = lyrics.first(where: { lyric in
                let duration = lyric.endTime - lyric.startTime
                return lyric.startTime > last.endTime && duration >= Self.minLyricDuration
            })?.startTime ?? .infinity
            
            if time < nextStart {
                return MergedLyric(
                    mainText: last.text,
                    backgroundText: last.secondaryText,
                    styledMainText: last.styledText,
                    styledBackgroundText: last.styledSecondaryText
                )
            }
        }
        
        return nil
    }
    
    /// Whether there's a valid lyric to show in one-line mode
    var hasOneLineModeLyric: Bool {
        oneLineModeLyric != nil
    }
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var hasAudio: Bool {
        audioFile != nil
    }
    
    var hasLyrics: Bool {
        !lyrics.isEmpty
    }
    
    /// Public accessor for the current audio file URL (needed for video export)
    var currentAudioFileURL: URL? {
        audioFileURL
    }
    
    nonisolated deinit {
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }
}
