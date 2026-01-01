//
//  AudioPlayerManager.swift
//  NyaViz
//

import Foundation
import AVFoundation
import Combine

@MainActor
class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var lyrics: [Lyric] = []
    @Published var currentLyricIndex: Int = -1
    @Published var audioFileName: String = ""
    @Published var showFilePicker = false
    @Published var showSRTPicker = false
    @Published var isLooping = true
    @Published var volume: Float = 0.8
    
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupVolumeObserver()
    }
    
    private func setupVolumeObserver() {
        $volume
            .sink { [weak self] newVolume in
                self?.player?.volume = newVolume
            }
            .store(in: &cancellables)
    }
    
    func loadAudio(from url: URL) {
        do {
            // Stop any existing playback
            stop()
            
            // Load the audio file
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.volume = volume
            player?.numberOfLoops = isLooping ? -1 : 0
            
            duration = player?.duration ?? 0
            audioFileName = url.deletingPathExtension().lastPathComponent
            currentTime = 0
            
        } catch {
            print("Error loading audio: \(error.localizedDescription)")
        }
    }
    
    func loadSRT(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            lyrics = SRTParser.parse(content)
            updateCurrentLyric()
        } catch {
            print("Error loading SRT: \(error.localizedDescription)")
        }
    }
    
    func play() {
        player?.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        player?.stop()
        isPlaying = false
        currentTime = 0
        player?.currentTime = 0
        stopTimer()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        player?.currentTime = max(0, min(time, duration))
        currentTime = player?.currentTime ?? 0
        updateCurrentLyric()
    }
    
    func seekForward(_ seconds: TimeInterval = 5) {
        seek(to: currentTime + seconds)
    }
    
    func seekBackward(_ seconds: TimeInterval = 5) {
        seek(to: currentTime - seconds)
    }
    
    func toggleLoop() {
        isLooping.toggle()
        player?.numberOfLoops = isLooping ? -1 : 0
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.player else { return }
                self.currentTime = player.currentTime
                self.updateCurrentLyric()
                
                // Check if playback finished (for non-looping mode)
                if !player.isPlaying && self.isPlaying && !self.isLooping {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateCurrentLyric() {
        let time = currentTime
        
        // Find the lyric that contains current time
        if let index = lyrics.firstIndex(where: { time >= $0.startTime && time < $0.endTime }) {
            if currentLyricIndex != index {
                currentLyricIndex = index
            }
        } else if let index = lyrics.lastIndex(where: { time >= $0.startTime }) {
            // If between lyrics, show the previous one
            if currentLyricIndex != index {
                currentLyricIndex = index
            }
        } else {
            currentLyricIndex = -1
        }
    }
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var hasAudio: Bool {
        player != nil
    }
    
    var hasLyrics: Bool {
        !lyrics.isEmpty
    }
    
    nonisolated deinit {
        // Timer cleanup happens automatically when the object is deallocated
    }
}

