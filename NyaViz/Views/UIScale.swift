//
//  UIScale.swift
//  NyaViz
//

import SwiftUI

/// A single, window-size-derived scale factor shared by every chrome element in
/// full-screen lyrics mode (track info card, floating controls, lyric text).
///
/// Historically each element derived its own scale — the track info card used
/// `min(w, h) / 800` clamped to `0.6...1.5` while the floating controls and the
/// lyric text did not scale at all.  The result was a composition that changed
/// shape at every window size.  `UIScale` replaces those with one value so the
/// whole layout grows and shrinks together.
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

    /// Keep very large displays (5K and up) from rendering absurdly large text.
    static let maximum: CGFloat = 2.0

    /// Computes the scale factor for a given frame.
    ///
    /// The width and height ratios are combined with `min` so that a wide-but-short
    /// window scales by its height — otherwise long lyric lines would overflow the
    /// top and bottom of the frame.
    static func factor(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return minimum }
        let ratio = min(size.width / referenceWidth, size.height / referenceHeight)
        return min(max(ratio, minimum), maximum)
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
