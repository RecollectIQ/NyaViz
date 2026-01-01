//
//  NyaVizApp.swift
//  NyaViz - Apple Music-Style Lyric Player
//

import SwiftUI

@main
struct NyaVizApp: App {
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var settingsManager = SettingsManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioPlayer)
                .environmentObject(settingsManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Audio File...") {
                    audioPlayer.showFilePicker = true
                }
                .keyboardShortcut("O", modifiers: .command)
                
                Button("Open SRT File...") {
                    audioPlayer.showSRTPicker = true
                }
                .keyboardShortcut("L", modifiers: .command)
            }
        }
    }
}
