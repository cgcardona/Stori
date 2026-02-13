//
//  AccessibilityIdentifiers.swift
//  Stori
//
//  Centralized accessibility identifiers for XCUITest automation.
//  These IDs must be stable, semantic, and never positional.
//
//  Convention: "section.subsection.action" or "section.subsection.<dynamic>"
//  Dynamic segments use string interpolation at the call site.
//

import SwiftUI

// MARK: - Accessibility ID Constants

/// Centralized accessibility identifier constants for the entire app.
/// Used by both the main app (to set IDs) and UI tests (to query elements).
///
/// Naming convention:
/// - Dot-separated hierarchy: `area.component.action`
/// - Always lowercase with underscores for multi-word segments
/// - Never use positional or index-based IDs
/// - Dynamic IDs use static methods that accept a UUID or name
enum AccessibilityID {

    // MARK: - Transport Controls
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
        static let tempoDisplay = "transport_tempo_display"
        static let positionDisplay = "transport_position_display"
        static let timeSignatureDisplay = "transport_time_signature"
    }

    // MARK: - Panel Toggles
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

    // MARK: - Timeline
    enum Timeline {
        static let editor = "timeline.editor"
        static let ruler = "timeline.ruler"
        static let playhead = "timeline.playhead"
        static let selection = "timeline.selection"
        static let trackList = "timeline.track_list"

        static func trackRow(_ trackId: UUID) -> String {
            "timeline.track.\(trackId.uuidString)"
        }
        static func trackHeader(_ trackId: UUID) -> String {
            "timeline.track_header.\(trackId.uuidString)"
        }
        static func audioRegion(_ regionId: UUID) -> String {
            "timeline.audio_region.\(regionId.uuidString)"
        }
        static func midiRegion(_ regionId: UUID) -> String {
            "timeline.midi_region.\(regionId.uuidString)"
        }
    }

    // MARK: - Mixer
    enum Mixer {
        static let container = "mixer.container"
        static let toolbar = "mixer.toolbar"

        static func trackVolume(_ trackId: UUID) -> String {
            "mixer.track.\(trackId.uuidString).volume"
        }
        static func trackPan(_ trackId: UUID) -> String {
            "mixer.track.\(trackId.uuidString).pan"
        }
        static func trackMute(_ trackId: UUID) -> String {
            "mixer.track.\(trackId.uuidString).mute"
        }
        static func trackSolo(_ trackId: UUID) -> String {
            "mixer.track.\(trackId.uuidString).solo"
        }
        static func trackRecord(_ trackId: UUID) -> String {
            "mixer.track.\(trackId.uuidString).record_arm"
        }
        static func trackName(_ trackId: UUID) -> String {
            "mixer.track.\(trackId.uuidString).name"
        }
        static func channelStrip(_ trackId: UUID) -> String {
            "mixer.track.\(trackId.uuidString).strip"
        }
        static func insertSlot(_ trackId: UUID, slot: Int) -> String {
            "mixer.track.\(trackId.uuidString).insert.\(slot)"
        }

        static let masterVolume = "mixer.master.volume"
        static let masterMeter = "mixer.master.meter"
    }

    // MARK: - Track Management
    enum Track {
        static let addButton = "track.add"
        static let addAudio = "track.add.audio"
        static let addMIDI = "track.add.midi"

        static let createDialog = "track.create_dialog"
        static let createDialogTypeAudio = "track.create_dialog.type.audio"
        static let createDialogTypeMIDI = "track.create_dialog.type.midi"
        static let createDialogCount = "track.create_dialog.count"
        static let createDialogConfirm = "track.create_dialog.confirm"
        static let createDialogCancel = "track.create_dialog.cancel"

        static func deleteTrack(_ trackId: UUID) -> String {
            "track.delete.\(trackId.uuidString)"
        }
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

    // MARK: - Export
    enum Export {
        static let button = "export.button"
        static let dialog = "export.dialog"
        static let dialogConfirm = "export.dialog.confirm"
        static let dialogCancel = "export.dialog.cancel"
        static let formatPicker = "export.format_picker"
        static let bitDepthPicker = "export.bit_depth_picker"
        static let progressView = "export.progress"
    }

    // MARK: - Project Management
    enum Project {
        static let newButton = "project.new"
        static let openButton = "project.open"
        static let saveButton = "project.save"
        static let browserView = "project.browser"
        static let nameField = "project.name_field"
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

    // MARK: - Main Tabs
    enum MainTab {
        static let daw = "main_tab.daw"
        static let marketplace = "main_tab.marketplace"
        static let wallet = "main_tab.wallet"
    }
}

// MARK: - SwiftUI Convenience Extension

extension View {
    /// Apply a stable accessibility identifier from the centralized ID system.
    /// This is a convenience wrapper that makes the call site cleaner.
    func storiAccessibilityID(_ identifier: String) -> some View {
        self.accessibilityIdentifier(identifier)
    }
}
