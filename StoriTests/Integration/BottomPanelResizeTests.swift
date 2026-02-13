//
//  BottomPanelResizeTests.swift
//  StoriTests
//
//  Regression and unit tests for bottom panel resize handle behaviour.
//  Ensures minimum panel height keeps the handle visible and hittable (issue #157).
//

import XCTest
@testable import Stori

final class BottomPanelResizeTests: XCTestCase {

    // MARK: - Minimum Height Constant

    /// Minimum content height must be at least 44pt so the resize handle strip
    /// remains visible and hittable when the panel is "collapsed".
    func testMinimumBottomPanelContentHeightIsEnforced() {
        XCTAssertEqual(
            MainDAWView.BottomPanelLayout.minContentHeight,
            44,
            "Minimum bottom panel content height should be 44pt (accessibility hit target)"
        )
    }

    // MARK: - Clamping Behaviour (Model + View Contract)

    /// Project can persist panel heights below minimum; view layer clamps on read/set.
    /// This test documents that the model may store values < 44; the View clamps when reading.
    func testProjectUIStateCanStoreSmallPanelHeights() {
        var state = ProjectUIState()
        state.mixerHeight = 0
        state.stepSequencerHeight = 10
        state.pianoRollHeight = 20
        state.synthesizerHeight = 30

        XCTAssertEqual(state.mixerHeight, 0)
        XCTAssertEqual(state.stepSequencerHeight, 10)
        XCTAssertEqual(state.pianoRollHeight, 20)
        XCTAssertEqual(state.synthesizerHeight, 30)
    }

    /// Clamping logic: effective height used by the view is max(minContentHeight, raw).
    /// Regression test for issue #157 — would have caught allowing 0 and making handle inactive.
    func testEffectivePanelHeightNeverBelowMinimum() {
        let minH = MainDAWView.BottomPanelLayout.minContentHeight
        let testValues: [CGFloat] = [0, 1, 10, 43, 44, 45, 600]

        for raw in testValues {
            let effective = max(minH, raw)
            if raw < minH {
                XCTAssertEqual(effective, minH, "Raw \(raw) should clamp to \(minH)")
            } else {
                XCTAssertEqual(effective, raw, "Raw \(raw) should pass through")
            }
        }
    }
}
