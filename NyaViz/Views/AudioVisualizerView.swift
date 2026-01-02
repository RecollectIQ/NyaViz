//
//  AudioVisualizerView.swift
//  NyaViz
//

import SwiftUI

struct AudioVisualizerView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: SettingsManager
    
    private let maxBarHeight: CGFloat = 60
    private let minBarHeight: CGFloat = 2
    
    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: settings.visualizerBarGap) {
                // Create symmetric bars - left half mirrors right half
                ForEach(0..<settings.visualizerBarCount, id: \.self) { index in
                    let height = symmetricBarHeight(for: index)
                    
                    RoundedRectangle(cornerRadius: settings.visualizerBarWidth / 2)
                        .fill(Color.white.opacity(settings.visualizerBarOpacity))
                        .frame(width: settings.visualizerBarWidth, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: maxBarHeight)
    }
    
    private func symmetricBarHeight(for index: Int) -> CGFloat {
        let bandCount = audioPlayer.frequencyBands.count
        guard bandCount > 0, settings.visualizerBarCount > 0 else { return minBarHeight }
        
        let barCount = settings.visualizerBarCount
        let halfBars = barCount / 2
        
        // Mirror index: bars on left side use same frequency as corresponding right side
        // Center bars use low frequencies (bass), outer bars use high frequencies
        let mirroredIndex: Int
        if index < halfBars {
            // Left side: map from center outward (0 = center, halfBars-1 = left edge)
            mirroredIndex = halfBars - 1 - index
        } else {
            // Right side: map from center outward (halfBars = center, barCount-1 = right edge)
            mirroredIndex = index - halfBars
        }
        
        // Map the mirrored index to frequency band
        // Lower indices = bass (center), higher indices = highs (edges)
        let bandIndex = Int(Float(mirroredIndex) / Float(halfBars) * Float(bandCount))
        let clampedIndex = min(bandIndex, bandCount - 1)
        
        let magnitude = CGFloat(audioPlayer.frequencyBands[clampedIndex])
        let height = minBarHeight + magnitude * (maxBarHeight - minBarHeight)
        
        return max(minBarHeight, min(maxBarHeight, height))
    }
}

#Preview {
    ZStack {
        Color.black
        
        VStack {
            Spacer()
            AudioVisualizerView()
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
        }
    }
    .environmentObject(AudioPlayerManager())
    .environmentObject(SettingsManager())
    .frame(width: 800, height: 200)
}
