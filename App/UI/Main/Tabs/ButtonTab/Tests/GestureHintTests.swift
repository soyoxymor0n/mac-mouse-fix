//
// --------------------------------------------------------------------------
// GestureHintTests.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//
// Tests for the gesture hint timeline in GestureHintModel.swift. Run with run_gesture_tests.sh in this folder.

import Foundation

@main
struct GestureHintTests {

    static var checks = 0
    static var failures = 0

    static func expect(_ condition: Bool, _ name: String) {
        checks += 1
        if condition {
            print("ok    \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func main() {

        let kinds = GestureKind.allCases
        let loop = GestureHintTimeline.loopDuration

        /// Order and pauses
        for kind in kinds {
            expect(kind.start < kind.activeEnd, "\(kind) starts before it ends")
            expect(kind.hoverStart < kind.start && kind.activeEnd < kind.hoverEnd, "\(kind) hover window contains the gesture")
            if let next = kind.next {
                expect(next.start - kind.activeEnd >= 3.0, "pause of at least 3 s after \(kind)")
            }
        }
        expect(kinds.last!.hoverEnd < loop, "the last hover window ends within the loop")

        /// While a gesture plays, its name is shown and the left button is lit
        for kind in kinds {
            let center = (kind.start + kind.activeEnd) / 2
            let state = GestureHintTimeline.state(at: center)
            expect(state.nameKind == kind && state.nameOpacity == 1, "\(kind) is named at its center")
            expect(state.mouseOpacity == 1, "the mouse is shown during \(kind)")
            let lit = stride(from: kind.start, to: kind.activeEnd, by: 0.01).contains { GestureHintTimeline.state(at: $0).leftButtonLit == 1 }
            expect(lit, "\(kind) lights the left button")
        }
        for kind in [GestureKind.clickAndDrag, .clickAndScroll, .hold] {
            let center = (kind.start + kind.activeEnd) / 2
            expect(GestureHintTimeline.state(at: center).leftButtonLit == 1, "\(kind) holds the left button at its center")
        }

        /// Only one name at a time, and each one is fully visible at its gesture's start
        for kind in kinds {
            let state = GestureHintTimeline.state(at: kind.start)
            expect(state.nameKind == kind && state.nameOpacity == 1, "\(kind) is named when it starts")
            if let next = kind.next {
                expect(GestureHintTimeline.state(at: next.start - 0.35).nameKind == nil, "no name between \(kind) and \(next)")
            }
        }

        /// The drag
        let dragged = GestureHintTimeline.state(at: 11.0)
        expect(dragged.mouseXOffset == GestureHintTimeline.dragDistance && GestureHintTimeline.dragDistance == 44, "the drag moves the mouse by 44 at 11.0")
        expect(dragged.dragArrowOpacity == 1 && dragged.dragArrowProgress == 1, "the drag arrow is fully drawn at 11.0")
        expect(GestureHintTimeline.state(at: 8.9).mouseXOffset == 0, "the mouse has not moved before the drag")
        expect(GestureHintTimeline.state(at: 11.5).dragArrowOpacity == 0, "the drag arrow is gone after the release")

        /// The scroll
        let scrolling = GestureHintTimeline.state(at: 15.9)
        expect(scrolling.wheelLit == 1 && scrolling.scrollArrowOpacity == 1, "the wheel and the scroll arrow are lit during the scroll")
        expect(GestureHintTimeline.state(at: 14.9).wheelLit == 0, "the wheel is not lit before the scroll")

        /// The hold
        expect(GestureHintTimeline.state(at: 23.4).holdProgress >= 0.95, "the hold arc is full at 23.4")
        expect(GestureHintTimeline.state(at: 22.25).holdProgress > 0.4, "the hold arc grows")
        expect(GestureHintTimeline.state(at: 23.6).holdProgress == 0, "the hold arc is gone after the hold")

        /// The end of the loop
        let end = GestureHintTimeline.state(at: 29.9)
        expect(end.mouseOpacity == 0 && end.nameKind == nil, "nothing is shown at 29.9")
        expect(end.mouseXOffset == 0 && GestureHintTimeline.state(at: 0).mouseOpacity == 0, "the mouse is back in place and hidden when the loop starts again")

        print("\(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
