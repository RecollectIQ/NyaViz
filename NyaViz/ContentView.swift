//
//  ContentView.swift
//  NyaViz
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var library: LibraryManager
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var showSettingsButton = false
    @State private var showLibraryButton = false

    var body: some View {
        ZStack {
            // Background Layer
            BackgroundView()

            // Main Content
            if settings.isFullScreen {
                FullScreenLyricsView()
                    .transition(.opacity)
            } else {
                MainPlayerView()
                    .transition(.opacity)
            }

            // Floating Controls (appear on hover in fullscreen)
            if settings.isFullScreen {
                VStack {
                    Spacer()
                    FloatingControlsView()
                        .opacity(showControls ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: showControls)
                }
                .padding(.bottom, 40)
            }

            // Library Button (top left) - not in fullscreen
            if !library.isDrawerExpanded && !settings.isFullScreen {
                VStack {
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                library.isDrawerExpanded = true
                            }
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.25))
                                .opacity(showLibraryButton ? 1 : 0)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 60, height: 60)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showLibraryButton = hovering
                            }
                        }

                        Spacer()
                    }
                    Spacer()
                }
            }

            // Settings Button (top right) - not in fullscreen
            if !settings.showSettings && !settings.isFullScreen {
                VStack {
                    HStack {
                        Spacer()

                        Button(action: { settings.showSettings.toggle() }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.25))
                                .opacity(showSettingsButton ? 1 : 0)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 60, height: 60)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSettingsButton = hovering
                            }
                        }
                    }
                    Spacer()
                }
            }

            // Library Sidebar (left) - not in fullscreen
            if library.isDrawerExpanded && !settings.isFullScreen {
                LibraryDrawerView()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Settings Panel (right) - not in fullscreen
            if settings.showSettings && !settings.isFullScreen {
                SettingsPanelView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering in
            if settings.isFullScreen {
                showControls = hovering
                resetControlsTimer()
            }
        }
        .onTapGesture {
            if settings.isFullScreen {
                showControls.toggle()
                if showControls {
                    resetControlsTimer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: settings.isFullScreen)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: settings.showSettings)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: library.isDrawerExpanded)
    }

    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(SettingsManager())
        .environmentObject(LibraryManager())
}
