//
//  AccessibilityID+UITests.swift
//  StoriUITests
//
//  Re-exports accessibility identifier constants for use in UI tests.
//  XCUITests cannot import @testable Stori, so we mirror the IDs here.
//
//  IMPORTANT: Keep this in sync with Stori/Core/Utilities/AccessibilityIdentifiers.swift.
//  A build script or test could verify synchronization if drift becomes an issue.
//

import Foundation

/// Accessibility ID constants mirrored from the main app target.
/// These must match the values set in the production SwiftUI views.
enum AccessibilityID {

    // MARK: - Transport
    enum Transport {
        static let play = "transport_play"
        static let stop = "transport_stop"
        static let record = "transport_record"
        static let beginning = "transport_beginning"
        static let rewind = "transport_rewind"
        static let forward = "transport_forward"
        static let end = "transport_end"
        static let cycle = "transport_cycle"
        static let catchPlayhead = "transport_catch_playhead"
        static let metronome = "transport_metronome"
    }

    // MARK: - Panels
    enum Panel {
        static let toggleMixer = "toggle_mixer"
        static let toggleSynthesizer = "toggle_synthesizer"
        static let togglePianoRoll = "toggle_piano_roll"
        static let toggleStepSequencer = "toggle_step_sequencer"
        static let toggleSelection = "toggle_selection"
        static let toggleInspector = "toggle_inspector"

        /// Bottom panel resize handles (five-dot drag strip).
        static let resizeHandleMixer = "panels.mixer.resizeHandle"
        static let resizeHandleSequencer = "panels.sequencer.resizeHandle"
        static let resizeHandlePianoRoll = "panels.pianoRoll.resizeHandle"
        static let resizeHandleSynthesizer = "panels.synthesizer.resizeHandle"
    }

    // MARK: - Mixer
    enum Mixer {
        static let container = "mixer.container"
        static let toolbar = "mixer.toolbar"
        static let masterVolume = "mixer.master.volume"
        static let masterMeter = "mixer.master.meter"

        static func trackMute(_ trackId: UUID) -> String {
            "mixer.track.\(trackId.uuidString).mute"
        }
        static func trackSolo(_ trackId: UUID) -> String {
            "mixer.track.\(trackId.uuidString).solo"
        }
        static func channelStrip(_ trackId: UUID) -> String {
            "mixer.track.\(trackId.uuidString).strip"
        }
    }

    // MARK: - Piano Roll
    enum PianoRoll {
        static let container = "piano_roll.container"
        static let toolSelector = "piano_roll.tool_selector"
        static let quantizeButton = "piano_roll.quantize"
        static let velocitySlider = "piano_roll.velocity"
    }

    // MARK: - Step Sequencer
    enum StepSequencer {
        static let container = "step_sequencer.container"
        static let presetPicker = "step_sequencer.preset_picker"
    }

    // MARK: - Synthesizer
    enum Synthesizer {
        static let container = "synthesizer.container"
    }

    // MARK: - Plugins
    enum Plugin {
        static let browser = "plugin.browser"
        static let insert = "plugin.insert"
        static let bypass = "plugin.bypass"
        static let editor = "plugin.editor"

        static func pluginSlot(_ trackId: UUID, slot: Int) -> String {
            "plugin.slot.\(trackId.uuidString).\(slot)"
        }
    }

    // MARK: - Track
    enum Track {
        static let createDialog = "track.create_dialog"
        static let createDialogTypeAudio = "track.create_dialog.type.audio"
        static let createDialogTypeMIDI = "track.create_dialog.type.midi"
        static let createDialogConfirm = "track.create_dialog.confirm"
        static let createDialogCancel = "track.create_dialog.cancel"
    }

    // MARK: - Export
    enum Export {
        static let dialog = "export.dialog"
        static let dialogConfirm = "export.dialog.confirm"
        static let dialogCancel = "export.dialog.cancel"
    }

    // MARK: - Window
    enum Window {
        static let resetDefaultView = "window.resetDefaultView"
    }

    // MARK: - Project
    enum Project {
        static let newButton = "project.new"
        static let saveButton = "project.save"
        static let browserView = "project.browser"
        /// Save-before-quit / save-before-new-project dialog (Issue #158)
        static let saveBeforeQuitSave = "project.saveBeforeQuit.save"
        static let saveBeforeQuitDontSave = "project.saveBeforeQuit.dontSave"
        static let saveBeforeQuitCancel = "project.saveBeforeQuit.cancel"
    }
}
