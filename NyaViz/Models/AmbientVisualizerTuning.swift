//
//  AmbientVisualizerTuning.swift
//  NyaViz
//

import Foundation

enum AmbientVisualizerTuning {
    static let baseVignetteStrength = 0.6
    static let backgroundScaleAmount = 0.035
    static let vignetteBoostAmount = 0.16
    static let particleSizeBoost = 0.8
    static let particleOpacityBoost = 0.14

    static func backgroundScale(bassEnergy: Float, intensity: Double) -> Double {
        1.0 + Double(bassEnergy) * backgroundScaleAmount * intensity
    }

    static func vignetteStrength(bassEnergy: Float, intensity: Double) -> Double {
        baseVignetteStrength + Double(bassEnergy) * vignetteBoostAmount * intensity
    }

    static func particleSize(baseSize: Double, bassEnergy: Float, intensity: Double) -> Double {
        baseSize + Double(bassEnergy) * intensity * particleSizeBoost
    }

    static func particleOpacity(baseOpacity: Double, bassEnergy: Float, intensity: Double) -> Double {
        min(1.0, baseOpacity + Double(bassEnergy) * intensity * particleOpacityBoost)
    }
}
