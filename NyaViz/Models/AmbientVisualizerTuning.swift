//
//  AmbientVisualizerTuning.swift
//  NyaViz
//

import Foundation

enum AmbientVisualizerTuning {
    static let backgroundFrameExpansion = 1.11
    static let backgroundScaleAmount = 0.035
    static let particleSizeBoost = 0.8
    static let particleOpacityBoost = 0.14

    static func backgroundDrift(size: CGSize, time: TimeInterval) -> CGSize {
        let diagonalOffset = sin(time * 0.42)
        return CGSize(
            width: diagonalOffset * size.width * 0.015,
            height: diagonalOffset * size.height * 0.015
        )
    }

    static func backgroundScale(bassEnergy: Float, intensity: Double) -> Double {
        1.0 + Double(bassEnergy) * backgroundScaleAmount * intensity
    }

    static func particleSize(baseSize: Double, bassEnergy: Float, intensity: Double) -> Double {
        baseSize + Double(bassEnergy) * intensity * particleSizeBoost
    }

    static func particleOpacity(baseOpacity: Double, bassEnergy: Float, intensity: Double) -> Double {
        min(1.0, baseOpacity + Double(bassEnergy) * intensity * particleOpacityBoost)
    }
}
