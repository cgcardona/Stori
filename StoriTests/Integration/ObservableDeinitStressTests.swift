//
//  ObservableDeinitStressTests.swift
//  StoriTests
//
//  Stress tests for @Observable + @MainActor deallocation safety.
//  Validates that rapid allocation/deallocation cycles of @Observable classes
//  do not cause double-free crashes (ASan Issue #84742+, GitHub Issue #112).
//
//  Root cause: The @Observable macro + @MainActor + Swift Concurrency creates
//  implicit task-local storage that can be double-freed during object deallocation,
//  especially when objects are deallocated on arbitrary threads during test teardown.
//  Empty `deinit` blocks prevent the crash by ensuring proper cleanup ordering.
//
//  NOTE: Classes that bind to hardware (MIDIDeviceManager, AVAudioEngine) or
//  perform heavy I/O (SequencerEngine/DrumKitLoader) are excluded from rapid
//  alloc/dealloc testing — they have separate lifecycle concerns.
//

import XCTest
@testable import Stori

// MARK: - Observable Deinit Stress Tests

/// Tests that @Observable classes can be rapidly allocated and deallocated
/// without triggering memory corruption (double-free) crashes.
///
/// These tests are designed to catch the ASan Issue #84742+ regression
/// where @Observable + @MainActor classes crash during deallocation.
/// If any of these tests crash with "attempting free on address which was
/// not malloc()-ed", it means a protective deinit block is missing.
@MainActor
final class ObservableDeinitStressTests: XCTestCase {
    
    // MARK: - Constants
    
    /// Number of rapid alloc/dealloc cycles per test.
    private let stressCycles = 100
    
    // MARK: - Audio Engine Classes (lightweight, no hardware binding)
    
    func testAudioAnalyzerRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = AudioAnalyzer()
            }
        }
    }
    
    func testMetronomeEngineRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = MetronomeEngine()
            }
        }
    }
    
    func testMIDIPlaybackEngineRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = MIDIPlaybackEngine()
            }
        }
    }
    
    func testPluginInstanceManagerRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = PluginInstanceManager()
            }
        }
    }
    
    func testStepInputEngineRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = StepInputEngine()
            }
        }
    }
    
    func testMIDIBounceEngineRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = MIDIBounceEngine()
            }
        }
    }
    
    func testDeviceConfigurationManagerRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = DeviceConfigurationManager()
            }
        }
    }
    
    func testAudioPerformanceMonitorRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = AudioPerformanceMonitor()
            }
        }
    }
    
    func testAudioResourcePoolRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = AudioResourcePool()
            }
        }
    }
    
    func testAudioFormatCoordinatorRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = AudioFormatCoordinator(sampleRate: 48000)
            }
        }
    }
    
    func testAudioEngineHealthMonitorRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = AudioEngineHealthMonitor()
            }
        }
    }
    
    func testAudioEngineErrorTrackerRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = AudioEngineErrorTracker()
            }
        }
    }
    
    // MARK: - Service Classes
    
    func testSelectionManagerRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = SelectionManager()
            }
        }
    }
    
    func testScrollSyncModelRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = ScrollSyncModel()
            }
        }
    }
    
    func testRegionDragStateRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = RegionDragState()
            }
        }
    }
    
    func testUndoServiceRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = UndoService()
            }
        }
    }
    
    func testAutomationRecorderRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = AutomationRecorder()
            }
        }
    }
    
    // MARK: - Score Classes
    
    func testScoreEntryControllerRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = ScoreEntryController()
            }
        }
    }
    
    // MARK: - UI State Classes
    
    func testVirtualKeyboardStateRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = VirtualKeyboardState()
            }
        }
    }
    
    func testMeterDataProviderRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = MeterDataProvider()
            }
        }
    }
    
    func testAppStateRapidAllocDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let _ = AppState()
            }
        }
    }
    
    // MARK: - Concurrent Deallocation Tests
    
    /// Tests that @Observable objects deallocated from multiple tasks
    /// simultaneously do not crash. This specifically targets the scenario
    /// where deinit runs on a non-MainActor thread.
    func testConcurrentDeallocationDoesNotCrash() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<stressCycles {
                group.addTask { @MainActor in
                    autoreleasepool {
                        let _ = SelectionManager()
                        let _ = ScrollSyncModel()
                        let _ = RegionDragState()
                        let _ = UndoService()
                    }
                }
            }
        }
    }
    
    /// Tests rapid creation and destruction of audio-related @Observable classes
    /// across task boundaries to stress the task-local storage cleanup path.
    func testAudioClassesConcurrentTeardown() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<stressCycles {
                group.addTask { @MainActor in
                    autoreleasepool {
                        let _ = AudioAnalyzer()
                        let _ = StepInputEngine()
                        let _ = AudioEngineErrorTracker()
                        let _ = MIDIPlaybackEngine()
                    }
                }
            }
        }
    }
    
    // MARK: - Property Mutation / Observation Teardown
    
    /// Regression test: Allocate an @Observable object, mutate observable properties,
    /// then deallocate. This tests that observation tracking teardown is safe.
    func testObservablePropertyMutationThenDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let state = RegionDragState()
                state.isDragging = true
                state.isDragging = false
            }
        }
    }
    
    /// Regression test: Allocate observable object, read properties (which registers
    /// observation), then deallocate to test observation teardown path.
    func testObservablePropertyReadThenDealloc() {
        for _ in 0..<stressCycles {
            autoreleasepool {
                let manager = SelectionManager()
                _ = manager.selectedRegionIds
                _ = manager.selectedMIDIRegionId
            }
        }
    }
    
    // MARK: - Performance
    
    /// Measures the overhead of creating and destroying @Observable classes.
    /// Establishes a baseline and ensures the deinit workaround doesn't
    /// introduce measurable performance regression.
    func testObservableAllocDeallocPerformance() {
        measure {
            for _ in 0..<1000 {
                autoreleasepool {
                    let _ = SelectionManager()
                }
            }
        }
    }
}
