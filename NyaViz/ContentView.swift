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
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    
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
            
            // Settings Button (top right) - hidden when panel is open
            if !settings.showSettings {
                VStack {
                    HStack {
                        Spacer()
                        
                        Button(action: { settings.showSettings.toggle() }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 20)
                        .padding(.top, 16)
                    }
                    Spacer()
                }
            }
            
            // Settings Panel
            if settings.showSettings {
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
}
