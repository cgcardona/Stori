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
    }

    // MARK: - Mixer
    enum Mixer {
        static let container = "mixer.container"

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

    // MARK: - Project
    enum Project {
        static let newButton = "project.new"
        static let saveButton = "project.save"
        static let browserView = "project.browser"
    }
}
