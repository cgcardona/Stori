//
//  NotificationHandlersModifier.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Notification Handlers Modifier
struct NotificationHandlersModifier: ViewModifier {
    let projectManager: ProjectManager
    let audioEngine: AudioEngine
    let selectedMainTab: Binding<MainTab>
    let showingMixer: Binding<Bool>
    let showingInspector: Binding<Bool>
    let showingSelection: Binding<Bool>
    let showingStepSequencer: Binding<Bool>
    let showingPianoRoll: Binding<Bool>
    let showingSynthesizer: Binding<Bool>
    let showCreateTrackDialog: () -> Void
    let addAudioTrack: () -> Void
    let addMIDITrack: () -> Void
    let deleteSelectedTrack: () -> Void
    let importAudio: () -> Void
    let importMIDI: () -> Void
    let saveProject: () -> Void
    let exportProject: () -> Void
    let skipToBeginning: () -> Void
    let skipToEnd: () -> Void
    
    func body(content: Content) -> some View {
        content
            .modifier(TrackNotificationsModifier(
                onNewTrackDialog: handleNewTrackDialog,
                onNewAudioTrack: handleNewAudioTrack,
                onNewMIDITrack: handleNewMIDITrack,
                onDeleteTrack: handleDeleteTrack,
                onImportAudio: handleImportAudio,
                onImportMIDI: handleImportMIDIFile
            ))
            .modifier(PanelNotificationsModifier(
                onToggleMixer: handleToggleMixer,
                onToggleInspector: handleToggleInspector,
                onToggleSelection: handleToggleSelection,
                onOpenTrackInspector: handleOpenTrackInspector,
                onOpenRegionInspector: handleOpenRegionInspector,
                onOpenProjectInspector: handleOpenProjectInspector
            ))
            .modifier(ProjectNotificationsModifier(
                audioEngine: audioEngine,
                onSaveProject: saveProject,
                onExportProject: exportProject,
                onSkipToBeginning: skipToBeginning,
                onSkipToEnd: skipToEnd
            ))
    }
    
    // MARK: - Handler Methods
    
    private func handleNewTrackDialog() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            showCreateTrackDialog()
        }
    }
    
    private func handleNewAudioTrack() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            addAudioTrack()
        }
    }
    
    private func handleNewMIDITrack() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            addMIDITrack()
        }
    }
    
    private func handleDeleteTrack() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            deleteSelectedTrack()
        }
    }
    
    private func handleImportAudio() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            importAudio()
        }
    }
    
    private func handleImportMIDIFile() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            importMIDI()
        }
    }
    
    private func handleToggleMixer() {
        if selectedMainTab.wrappedValue == .daw {
            if showingMixer.wrappedValue {
                showingMixer.wrappedValue = false
            } else {
                // Close all other bottom panels
                showingStepSequencer.wrappedValue = false
                showingPianoRoll.wrappedValue = false
                showingSynthesizer.wrappedValue = false
                showingMixer.wrappedValue = true
            }
        }
    }
    
    private func handleToggleInspector() {
        showingInspector.wrappedValue.toggle()
    }
    
    private func handleToggleSelection() {
        if selectedMainTab.wrappedValue == .daw {
            showingSelection.wrappedValue.toggle()
        }
    }
    
    private func handleOpenTrackInspector() {
        if selectedMainTab.wrappedValue == .daw {
            showingSelection.wrappedValue = true
        }
    }
    
    private func handleOpenRegionInspector() {
        if selectedMainTab.wrappedValue == .daw {
            showingSelection.wrappedValue = true
        }
    }
    
    private func handleOpenProjectInspector() {
        if selectedMainTab.wrappedValue == .daw {
            showingSelection.wrappedValue = true
        }
    }
}

// MARK: - View Extension for Notification Handlers
extension View {
    func notificationHandlers(
        projectManager: ProjectManager,
        audioEngine: AudioEngine,
        selectedMainTab: Binding<MainTab>,
        showingMixer: Binding<Bool>,
        showingInspector: Binding<Bool>,
        showingSelection: Binding<Bool>,
        showingStepSequencer: Binding<Bool>,
        showingPianoRoll: Binding<Bool>,
        showingSynthesizer: Binding<Bool>,
        showCreateTrackDialog: @escaping () -> Void,
        addAudioTrack: @escaping () -> Void,
        addMIDITrack: @escaping () -> Void,
        deleteSelectedTrack: @escaping () -> Void,
        importAudio: @escaping () -> Void,
        importMIDI: @escaping () -> Void,
        saveProject: @escaping () -> Void,
        exportProject: @escaping () -> Void,
        skipToBeginning: @escaping () -> Void,
        skipToEnd: @escaping () -> Void
    ) -> some View {
        self.modifier(
            NotificationHandlersModifier(
                projectManager: projectManager,
                audioEngine: audioEngine,
                selectedMainTab: selectedMainTab,
                showingMixer: showingMixer,
                showingInspector: showingInspector,
                showingSelection: showingSelection,
                showingStepSequencer: showingStepSequencer,
                showingPianoRoll: showingPianoRoll,
                showingSynthesizer: showingSynthesizer,
                showCreateTrackDialog: showCreateTrackDialog,
                addAudioTrack: addAudioTrack,
                addMIDITrack: addMIDITrack,
                deleteSelectedTrack: deleteSelectedTrack,
                importAudio: importAudio,
                importMIDI: importMIDI,
                saveProject: saveProject,
                exportProject: exportProject,
                skipToBeginning: skipToBeginning,
                skipToEnd: skipToEnd
            )
        )
    }
}
