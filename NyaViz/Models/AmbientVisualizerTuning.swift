//
//  AmbientVisualizerTuning.swift
//  NyaViz
//

import Foundation

enum AmbientVisualizerTuning {
    static let backgroundFrameExpansion = 1.11
    static let backgroundDriftAmplitude = 0.015
    static let backgroundDriftDuration = 9.5
    static let particleBaseCount = 72
    static let particleSizeBoost = 1.1
    static let particleOpacityBoost = 0.18

    static func backgroundDrift(size: CGSize, phase: Double) -> CGSize {
        return CGSize(
            width: phase * size.width * backgroundDriftAmplitude,
            height: phase * size.height * backgroundDriftAmplitude
        )
    }

    static func backgroundDriftPhase(time: TimeInterval) -> Double {
        sin((time / backgroundDriftDuration) * .pi * 2)
    }

    static func particleCount(density: Double) -> Int {
        Int(Double(particleBaseCount) * density)
    }

    static func particleSize(baseSize: Double, bassEnergy: Float, intensity: Double) -> Double {
        baseSize + Double(bassEnergy) * intensity * particleSizeBoost
    }

    static func particleOpacity(baseOpacity: Double, bassEnergy: Float, intensity: Double) -> Double {
        min(1.0, baseOpacity + Double(bassEnergy) * intensity * particleOpacityBoost)
    }

    static func particleBeatOffset(
        bassEnergy: Float,
        intensity: Double,
        direction: Double,
        variance: Double
    ) -> CGSize {
        let pulseDistance = Double(bassEnergy) * intensity * (8 + variance * 16)
        return CGSize(
            width: cos(direction) * pulseDistance,
            height: sin(direction) * pulseDistance
        )
    }
}
