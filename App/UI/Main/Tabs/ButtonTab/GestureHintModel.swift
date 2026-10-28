//
// --------------------------------------------------------------------------
// GestureHintModel.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//
// The timeline of the gesture hint in the add field, as a pure function of time.
// The hint in the add field and the gesture legend under it both draw what `GestureHintTimeline.state(at:)` returns.
// Only needs Foundation, so it can be tested on its own (see Tests/run_gesture_tests.sh).

import Foundation

/// The gestures the hint plays, in the order they are played
enum GestureKind: Int, CaseIterable {

    case click, doubleClick, clickAndDrag, clickAndScroll, hold

    /// When the gesture starts, in seconds within one loop
    var start: Double {
        switch self {
        case .click: return 1.0
        case .doubleClick: return 4.8
        case .clickAndDrag: return 8.8
        case .clickAndScroll: return 14.6
        case .hold: return 20.8
        }
    }

    /// When the gesture is over, in seconds within one loop
    var activeEnd: Double {
        switch self {
        case .click: return 1.4
        case .doubleClick: return 5.4
        case .clickAndDrag: return 11.3
        case .clickAndScroll: return 17.2
        case .hold: return 23.7
        }
    }

    /// The localized string key of the gesture's name
    var nameKey: String {
        switch self {
        case .click: return "add-field.hint.click"
        case .doubleClick: return "add-field.hint.double-click"
        case .clickAndDrag: return "add-field.hint.click-and-drag"
        case .clickAndScroll: return "add-field.hint.click-and-scroll"
        case .hold: return "add-field.hint.hold"
        }
    }

    /// The localized string key of the gesture's line in the explainer popover
    var explainerKey: String {
        switch self {
        case .click: return "add-field.explainer.click"
        case .doubleClick: return "add-field.explainer.double-click"
        case .clickAndDrag: return "add-field.explainer.click-and-drag"
        case .clickAndScroll: return "add-field.explainer.click-and-scroll"
        case .hold: return "add-field.explainer.hold"
        }
    }

    /// The gesture played after this one, or nil for the last one
    var next: GestureKind? { GestureKind(rawValue: rawValue + 1) }

    /// Playing just this gesture (when its legend item is hovered) shows the loop from `hoverStart` to `hoverEnd`
    var hoverStart: Double { start - 0.3 }
    var hoverEnd: Double { activeEnd + 0.8 }
}

/// What the hint shows at one moment. Opacities and progresses go from 0 to 1.
struct GestureHintState: Equatable {

    var mouseOpacity: Double = 0
    /// How far the mouse has moved to the right, in points at full size
    var mouseXOffset: Double = 0
    var leftButtonLit: Double = 0
    /// The ring around the left button that pulses on a click
    var ringOpacity: Double = 0
    /// The arc around the left button that grows while the button is held. 0 hides it.
    var holdProgress: Double = 0
    var dragArrowOpacity: Double = 0
    var dragArrowProgress: Double = 0
    var wheelLit: Double = 0
    var scrollArrowOpacity: Double = 0
    /// The gesture whose name is shown, if any
    var nameKind: GestureKind? = nil
    var nameOpacity: Double = 0

    /// Nothing is shown
    static let hidden = GestureHintState()

    /// Reduce Motion: the mouse and the first name, without animation
    static let still = GestureHintState(mouseOpacity: 1, nameKind: .click, nameOpacity: 1)
}

enum GestureHintTimeline {

    /// Length of one loop in seconds
    static let loopDuration = 30.0
    /// How far the mouse moves to the right during the drag, in points at full size
    static let dragDistance = 44.0

    /// The state at time `t` in seconds within the loop, 0 <= t < `loopDuration`.
    ///     0.0 to 0.4    the mouse fades in
    ///     1.0           click
    ///     4.8           double click
    ///     8.8           click and drag. The mouse moves to the right while the left button is held, and stays there until it fades out.
    ///     14.6          click and scroll. The wheel is lit, and an arrow shows the scrolling.
    ///     20.8          hold. An arc around the left button fills up while it is held.
    ///     25.0 to 25.4  the mouse fades out, and nothing is shown until the loop starts again
    /// Each gesture's name is shown from 0.3 s before it starts until 0.4 s before the next one starts.
    static func state(at t: Double) -> GestureHintState {

        var state = GestureHintState()

        state.mouseOpacity = interpolate(t, [(0, 0), (0.4, 1), (25.0, 1), (25.4, 0)])
        state.mouseXOffset = t < 25.4 ? interpolate(t, [(9.0, 0), (10.8, dragDistance)]) : 0

        state.leftButtonLit = pulses(t, [(1.0, 1.15), (4.8, 4.95), (5.1, 5.25), (9.0, 11.0), (14.8, 17.0), (21.0, 23.5)])
        state.ringOpacity = pulses(t, [(1.0, 1.4), (4.8, 5.25)])

        state.dragArrowOpacity = pulses(t, [(9.0, 11.3)])
        state.dragArrowProgress = interpolate(t, [(9.0, 0), (10.8, 1)])

        state.wheelLit = pulses(t, [(15.0, 16.8)])
        state.scrollArrowOpacity = pulses(t, [(15.0, 16.8)])

        state.holdProgress = (21.0 ..< 23.5).contains(t) ? interpolate(t, [(21.0, 0), (23.5, 1)]) : 0

        for kind in GestureKind.allCases {
            let shown = kind.start - 0.3
            let hidden = kind.next.map { $0.start - 0.4 } ?? 25.4
            if (shown ..< hidden).contains(t) {
                state.nameKind = kind
                state.nameOpacity = interpolate(t, [(shown, 0), (shown + 0.2, 1), (hidden - 0.2, 1), (hidden, 0)])
            }
        }

        return state
    }

    /// Piecewise linear interpolation between (time, value) keys. Before the first key and after the last one, the value is held.
    private static func interpolate(_ t: Double, _ keys: [(Double, Double)]) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for (a, b) in zip(keys, keys.dropFirst()) where t < b.0 {
            return a.1 + (b.1 - a.1) * (t - a.0) / (b.0 - a.0)
        }
        return last.1
    }

    /// 1 during each interval and 0 otherwise. Each interval switches on and off over 0.02 s.
    private static func pulses(_ t: Double, _ intervals: [(Double, Double)]) -> Double {
        for (start, stop) in intervals where (start ..< stop + 0.02).contains(t) {
            return interpolate(t, [(start, 0), (start + 0.02, 1), (stop, 1), (stop + 0.02, 0)])
        }
        return 0
    }
}
