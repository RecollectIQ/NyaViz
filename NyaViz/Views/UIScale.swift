//
//  UIScale.swift
//  NyaViz
//

import SwiftUI

/// A single, window-size-derived scale factor shared by the chrome of
/// full-screen lyrics mode: the track info card, the track list and the
/// floating controls.
///
/// Historically each element derived its own scale — the track info card used
/// `min(w, h) / 800` clamped to `0.6...1.5` while the floating controls did not
/// scale at all — so the chrome changed shape at every window size.
///
/// Lyric text is deliberately **not** scaled by this.  Its size is the user's
/// `lyricFontSize` setting and nothing else, so moving the window or entering
/// full screen never changes how large the lyrics read.
enum UIScale {

    /// The reference frame at which the scale is exactly `1.0`.
    ///
    /// This matches the app's minimum window size (`900x600`, widened slightly to
    /// a 16:10 basis) so that the smallest usable window renders at the sizes the
    /// app has always used, and every larger window scales up from there.
    static let referenceWidth: CGFloat = 960
    static let referenceHeight: CGFloat = 600

    /// Never shrink below the reference sizes.
    static let minimum: CGFloat = 1.0

    /// Ceiling for very large displays.
    static let maximum: CGFloat = 1.3

    /// How much of the frame's growth the chrome takes on.
    ///
    /// Scaling chrome in step with the frame (a rate of `1.0`) makes it loom on a
    /// full-screen display: controls meant to sit quietly at the edge become the
    /// loudest thing on screen.  Growing at roughly a third of that rate keeps
    /// them legible on a large display without turning them into furniture.
    static let growthRate: CGFloat = 0.35

    /// Computes the scale factor for a given frame.
    ///
    /// The width and height ratios are combined with `min` so a wide-but-short
    /// window scales by its height rather than overflowing top and bottom.
    static func factor(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return minimum }
        let ratio = min(size.width / referenceWidth, size.height / referenceHeight)
        let damped = 1.0 + (ratio - 1.0) * growthRate
        return min(max(damped, minimum), maximum)
    }
}

// MARK: - Environment

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    /// The shared full-screen UI scale factor. See ``UIScale``.
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}
