//
//  NyaVizApp.swift
//  NyaViz - Apple Music-Style Lyric Player
//

import SwiftUI
import CoreText
import AppKit

@main
struct NyaVizApp: App {
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var libraryManager = LibraryManager()
    @StateObject private var inboxWatcher = InboxWatcher()

    init() {
        // Register custom fonts
        registerFonts()
    }
    
    private func registerFonts() {
        // Try to load from bundle first
        if let fontURL = Bundle.main.url(forResource: "Mollen Trial-Bold", withExtension: "ttf", subdirectory: "Fonts") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
        
        // Fallback: try from mollen folder in app directory
        if let resourcePath = Bundle.main.resourcePath {
            let fontPaths = [
                "\(resourcePath)/Fonts/Mollen Trial-Bold.ttf",
                "\(resourcePath)/../../../mollen/Mollen Trial-Bold.ttf"
            ]
            
            for path in fontPaths {
                let fontURL = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
                    break
                }
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioPlayer)
                .environmentObject(settingsManager)
                .environmentObject(libraryManager)
                .environmentObject(inboxWatcher)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    // Wire the settings and library references so AudioPlayerManager can apply
                    // directives and auto-import opened files. Runs on the MainActor immediately
                    // after the first render.
                    audioPlayer.settingsRef = settingsManager
                    audioPlayer.libraryRef = libraryManager

                    // Begin importing anything agents write into the inbox folder.
                    inboxWatcher.start(library: libraryManager, audioPlayer: audioPlayer)
                }
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

                Divider()

                // One-time setup, so it belongs somewhere findable rather than
                // behind a hover-revealed button in the settings panel.
                Button(inboxWatcher.isConfigured ? "Change Agent Inbox Folder..." : "Set Up Agent Inbox...") {
                    inboxWatcher.chooseFolder()
                }

                if inboxWatcher.isConfigured {
                    Button("Reveal Agent Inbox in Finder") {
                        if let url = inboxWatcher.inboxDirectory {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }
        }
    }
}
