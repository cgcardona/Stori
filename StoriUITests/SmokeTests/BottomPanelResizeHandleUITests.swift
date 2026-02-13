//
//  BottomPanelResizeHandleUITests.swift
//  StoriUITests
//
//  Regression UI tests for bottom panel resize handle (issue #157).
//  Ensures the five-dot resize handle remains visible and hittable after shrinking.
//

import XCTest

final class BottomPanelResizeHandleUITests: StoriUITestCase {

    // MARK: - Mixer Resize Handle

    /// Open mixer and verify the resize handle exists and is hittable.
    func testMixerResizeHandleExistsAndIsHittableWhenMixerOpen() throws {
        tap(AccessibilityID.Panel.toggleMixer)
        Thread.sleep(forTimeInterval: 0.5)

        let handle = element(AccessibilityID.Panel.resizeHandleMixer)
        XCTAssertTrue(handle.waitForExistence(timeout: defaultTimeout),
                      "Mixer resize handle should exist when mixer is open")
        XCTAssertTrue(handle.isHittable,
                      "Mixer resize handle should be hittable when mixer is open")
    }

    /// Open mixer, drag resize handle down (shrink), then verify handle is still hittable.
    /// Regression for issue #157 — handle used to become inactive after collapse.
    func testMixerResizeHandleRemainsHittableAfterShrinking() throws {
        tap(AccessibilityID.Panel.toggleMixer)
        Thread.sleep(forTimeInterval: 0.6)

        let handle = element(AccessibilityID.Panel.resizeHandleMixer)
        XCTAssertTrue(handle.waitForExistence(timeout: defaultTimeout), "Resize handle should exist")

        // Drag down to shrink panel (handle stays at min height and remains hittable)
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 100))
        start.press(forDuration: 0.3, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.4)

        // Handle must still be present so user can expand again (regression #157)
        let handleAfter = element(AccessibilityID.Panel.resizeHandleMixer)
        XCTAssertTrue(handleAfter.waitForExistence(timeout: 5), "Resize handle should still exist after shrink")
        if handleAfter.exists {
            XCTAssertTrue(handleAfter.isHittable, "Resize handle should remain hittable after shrink")
        }
    }

    // MARK: - Step Sequencer Resize Handle

    /// Open step sequencer and verify the resize handle exists and is hittable.
    func testStepSequencerResizeHandleExistsAndIsHittableWhenSequencerOpen() throws {
        tap(AccessibilityID.Panel.toggleStepSequencer)
        Thread.sleep(forTimeInterval: 0.5)

        let handle = element(AccessibilityID.Panel.resizeHandleSequencer)
        XCTAssertTrue(handle.waitForExistence(timeout: defaultTimeout),
                      "Step sequencer resize handle should exist when sequencer is open")
        XCTAssertTrue(handle.isHittable,
                      "Step sequencer resize handle should be hittable when sequencer is open")
    }

    /// Open step sequencer, drag resize handle down (shrink), then verify handle is still hittable.
    func testStepSequencerResizeHandleRemainsHittableAfterShrinking() throws {
        tap(AccessibilityID.Panel.toggleStepSequencer)
        Thread.sleep(forTimeInterval: 0.6)

        let handle = element(AccessibilityID.Panel.resizeHandleSequencer)
        XCTAssertTrue(handle.waitForExistence(timeout: defaultTimeout), "Resize handle should exist")

        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 100))
        start.press(forDuration: 0.3, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.4)

        let handleAfter = element(AccessibilityID.Panel.resizeHandleSequencer)
        XCTAssertTrue(handleAfter.waitForExistence(timeout: 5), "Resize handle should still exist after shrink (regression #157)")
        if handleAfter.exists {
            XCTAssertTrue(handleAfter.isHittable, "Resize handle should remain hittable after shrink")
        }
    }
}
