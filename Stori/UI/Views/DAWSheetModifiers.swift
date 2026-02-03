//
//  DAWSheetModifiers.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - DAW Sheet Modifiers

struct DAWSheetModifiers: ViewModifier {
    @Binding var showingNewProjectSheet: Bool
    @Binding var showingProjectBrowser: Bool
    @Binding var showingAboutWindow: Bool
    @Binding var showingCreateTrackDialog: Bool
    @Binding var showingRenameTrackDialog: Bool
    @Binding var renameTrackText: String
    @Binding var showingExportSettings: Bool
    @Binding var activeSheet: DAWSheet?
    
    let projectManager: ProjectManager
    let exportService: ProjectExportService
    let availableBuses: [MixerBus]
    let onCreateTracks: (NewTrackConfig) async -> Void
    let onRenameTrack: () -> Void
    let onExportWithSettings: (ExportSettings) -> Void
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingNewProjectSheet) {
                NewProjectView(projectManager: projectManager)
            }
            .sheet(isPresented: $showingProjectBrowser) {
                ProjectBrowserView(projectManager: projectManager)
            }
            .sheet(isPresented: $showingAboutWindow) {
                AboutView()
            }
            .sheet(isPresented: $showingCreateTrackDialog) {
                CreateTrackDialog(
                    isPresented: $showingCreateTrackDialog,
                    availableBuses: availableBuses,
                    onCreateTracks: onCreateTracks
                )
            }
            .sheet(isPresented: $showingRenameTrackDialog) {
                RenameTrackDialog(trackName: $renameTrackText, onRename: onRenameTrack)
            }
            .sheet(isPresented: $showingExportSettings) {
                let project = self.projectManager.currentProject
                let duration = project.map { self.exportService.calculateProjectDuration($0) } ?? 0
                
                ExportSettingsSheet(
                    projectName: project?.name ?? "Untitled",
                    projectDuration: duration,
                    onExport: onExportWithSettings
                )
            }
            .sheet(item: $activeSheet) { sheet in
                DAWSheetContent(sheet: sheet)
            }
    }
}
