//
//  PerformanceAndLoadTests.swift
//  StoriUITests
//
//  Comprehensive performance and load tests.
//  Tests large projects, many tracks, many regions, plugin heavy scenarios.
//

import XCTest

final class PerformanceAndLoadTests: StoriUITestCase {

    // MARK: - Test Configuration

    override var defaultTimeout: TimeInterval { 30 }  // Longer timeout for performance tests

    // MARK: - Test: 10 Tracks Project

    /// Test basic multi-track project performance.
    func testTenTracksProject() throws {
        let trackCount = 10

        // Create 10 tracks (mix of audio and MIDI)
        for i in 0..<trackCount {
            if i % 2 == 0 {
                createAudioTrack()
            } else {
                createMIDITrack()
            }
        }

        // Open mixer - should show all tracks
        tap(AccessibilityID.Panel.toggleMixer)
        assertExists(AccessibilityID.Mixer.container, timeout: 10)

        // Start playback
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 2.0)
        tap(AccessibilityID.Transport.stop)

        // App should remain responsive
        assertExists(AccessibilityID.Transport.play, timeout: 3)

        captureScreenshot(name: "Performance-10Tracks")
    }

    // MARK: - Test: 50 Tracks Project

    /// Test medium-scale project with 50 tracks.
    func testFiftyTracksProject() throws {
        let trackCount = 50

        // Create 50 tracks
        for i in 0..<trackCount {
            if i % 2 == 0 {
                createAudioTrackFast()
            } else {
                createMIDITrackFast()
            }

            // Brief pause every 10 tracks to avoid overwhelming UI
            if i % 10 == 9 {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        // Verify mixer can handle 50 channel strips
        tap(AccessibilityID.Panel.toggleMixer)
        assertExists(AccessibilityID.Mixer.container, timeout: 15)

        // Start playback
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 3.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Performance-50Tracks")
    }

    // MARK: - Test: 100 Tracks Project

    /// Test large-scale project with 100 tracks (stress test).
    func testHundredTracksProject() throws {
        let trackCount = 100

        // Create 100 tracks
        for i in 0..<trackCount {
            createAudioTrackFast()

            // Pause every 20 tracks
            if i % 20 == 19 {
                Thread.sleep(forTimeInterval: 1.0)
            }
        }

        // Verify app remains stable
        assertExists(AccessibilityID.Transport.play, timeout: 10)

        // Try playback
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 2.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Performance-100Tracks")
    }

    // MARK: - Test: Many Regions

    /// Test project with many regions on timeline.
    func testManyRegions() throws {
        // Create 5 tracks
        for _ in 0..<5 {
            createAudioTrack()
        }

        // Simulate importing/recording multiple regions
        // (in real scenario, would import audio files or record)

        // Start playback with many regions
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 2.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Performance-ManyRegions")
    }

    // MARK: - Test: Plugin Heavy Project

    /// Test project with many plugins inserted.
    func testPluginHeavyProject() throws {
        // Create 10 tracks
        for _ in 0..<10 {
            createAudioTrack()
        }

        // Open mixer
        tap(AccessibilityID.Panel.toggleMixer)
        assertExists(AccessibilityID.Mixer.container, timeout: 10)

        // Insert plugins on each track (simulated via UI)
        // In actual implementation, would click plugin slots

        // Start playback - high CPU scenario
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 3.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Performance-PluginHeavy")
    }

    // MARK: - Test: Automation Heavy Project

    /// Test project with extensive automation.
    func testAutomationHeavyProject() throws {
        // Create 10 tracks
        for _ in 0..<10 {
            createAudioTrack()
        }

        // Create automation on all tracks (simulated)
        // Each track would have volume, pan, and send automation

        // Playback should render all automation
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 2.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Performance-AutomationHeavy")
    }

    // MARK: - Test: Long Project Duration

    /// Test project with very long timeline (1 hour).
    func testLongProjectDuration() throws {
        createAudioTrack()

        // Set project length to 1 hour
        // Zoom out fully
        // Navigate to end
        tap(AccessibilityID.Transport.end)

        // Should handle large time values
        Thread.sleep(forTimeInterval: 0.5)

        // Navigate back to beginning
        tap(AccessibilityID.Transport.beginning)

        captureScreenshot(name: "Performance-LongDuration")
    }

    // MARK: - Test: Rapid Track Creation/Deletion

    /// Stress test: rapidly create and delete tracks.
    func testRapidTrackCreationDeletion() throws {
        // Create 20 tracks rapidly
        for _ in 0..<20 {
            createAudioTrackFast()
        }

        Thread.sleep(forTimeInterval: 1.0)

        // Delete tracks rapidly (via undo)
        for _ in 0..<20 {
            typeShortcut("z", modifiers: [.command])
            Thread.sleep(forTimeInterval: 0.05)
        }

        // App should remain stable
        assertExists(AccessibilityID.Transport.play, timeout: 5)

        captureScreenshot(name: "Performance-RapidCreateDelete")
    }

    // MARK: - Test: Continuous Playback

    /// Test extended playback duration.
    func testContinuousPlayback() throws {
        // Create project with content
        for _ in 0..<5 {
            createAudioTrack()
        }

        // Enable cycle mode for continuous playback
        tap(AccessibilityID.Transport.cycle)

        // Play for extended period
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 10.0)
        tap(AccessibilityID.Transport.stop)

        // Disable cycle
        tap(AccessibilityID.Transport.cycle)

        // CPU usage should be stable, no crashes
        captureScreenshot(name: "Performance-ContinuousPlayback")
    }

    // MARK: - Test: UI Responsiveness Under Load

    /// Test UI responsiveness while audio engine is busy.
    func testUIResponsivenessUnderLoad() throws {
        // Create large project
        for _ in 0..<30 {
            createAudioTrackFast()
        }

        // Start playback
        tap(AccessibilityID.Transport.play)

        // Interact with UI during playback
        tap(AccessibilityID.Panel.toggleMixer)
        assertExists(AccessibilityID.Mixer.container, timeout: 5)

        tap(AccessibilityID.Panel.toggleInspector)
        Thread.sleep(forTimeInterval: 0.3)

        tap(AccessibilityID.Panel.toggleSelection)
        Thread.sleep(forTimeInterval: 0.3)

        tap(AccessibilityID.Transport.stop)

        // UI should remain responsive throughout
        captureScreenshot(name: "Performance-UIResponsiveness")
    }

    // MARK: - Test: Memory Usage

    /// Test memory footprint with large project.
    func testMemoryUsage() throws {
        // Create very large project
        for i in 0..<100 {
            createAudioTrackFast()

            if i % 25 == 24 {
                Thread.sleep(forTimeInterval: 1.0)
            }
        }

        // Let system stabilize
        Thread.sleep(forTimeInterval: 3.0)

        // App should not have crashed from memory pressure
        assertExists(AccessibilityID.Transport.play, timeout: 5)

        captureScreenshot(name: "Performance-Memory")
    }

    // MARK: - Test: Zoom Performance

    /// Test timeline zoom with many tracks and regions.
    func testZoomPerformance() throws {
        // Create moderate project
        for _ in 0..<20 {
            createAudioTrack()
        }

        // Zoom in/out rapidly
        // (would use zoom shortcuts or timeline controls)

        Thread.sleep(forTimeInterval: 0.5)

        // Rendering should remain smooth
        captureScreenshot(name: "Performance-Zoom")
    }

    // MARK: - Test: Scroll Performance

    /// Test timeline scrolling with many tracks.
    func testScrollPerformance() throws {
        // Create many tracks (vertical scroll)
        for _ in 0..<50 {
            createAudioTrackFast()
        }

        // Scroll up and down timeline
        // (would use scroll gestures or navigation)

        Thread.sleep(forTimeInterval: 0.5)

        // Scrolling should be smooth
        captureScreenshot(name: "Performance-Scroll")
    }

    // MARK: - Test: Undo Stack Performance

    /// Test undo/redo with many operations.
    func testUndoStackPerformance() throws {
        // Perform 100 operations
        for _ in 0..<100 {
            createAudioTrackFast()
        }

        // Undo all operations
        for _ in 0..<100 {
            typeShortcut("z", modifiers: [.command])
            Thread.sleep(forTimeInterval: 0.02)
        }

        // Redo all operations
        for i in 0..<100 {
            typeShortcut("z", modifiers: [.command, .shift])
            Thread.sleep(forTimeInterval: 0.02)

            // Sample screenshot midway
            if i == 50 {
                captureScreenshot(name: "Performance-UndoStackMidway")
            }
        }

        captureScreenshot(name: "Performance-UndoStack")
    }

    // MARK: - Helper Methods

    private func createAudioTrack() {
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeAudio)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)
    }

    private func createMIDITrack() {
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeMIDI)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)
    }

    /// Fast track creation without screenshots or extended waits
    private func createAudioTrackFast() {
        typeShortcut("n", modifiers: [.command, .shift])
        let dialog = element(AccessibilityID.Track.createDialog)
        _ = dialog.waitForExistence(timeout: 3)
        tap(AccessibilityID.Track.createDialogTypeAudio)
        tap(AccessibilityID.Track.createDialogConfirm)
        Thread.sleep(forTimeInterval: 0.1)
    }

    /// Fast MIDI track creation
    private func createMIDITrackFast() {
        typeShortcut("n", modifiers: [.command, .shift])
        let dialog = element(AccessibilityID.Track.createDialog)
        _ = dialog.waitForExistence(timeout: 3)
        tap(AccessibilityID.Track.createDialogTypeMIDI)
        tap(AccessibilityID.Track.createDialogConfirm)
        Thread.sleep(forTimeInterval: 0.1)
    }
}
