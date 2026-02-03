//
//  SelectionPanelView.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Selection Panel View

struct SelectionPanelView: View {
    @Binding var selectedTrackId: UUID?
    @Binding var selectedRegionId: UUID?
    let project: AudioProject?
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Selection")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // Selection content
            ScrollView {
                VStack(spacing: 16) {
                    if let regionId = selectedRegionId,
                       let project = project,
                       let region = findRegion(withId: regionId, in: project) {
                        // Show region details
                        Text("Region: \(region.audioFile.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let trackId = selectedTrackId,
                              let project = project,
                              let track = project.tracks.first(where: { $0.id == trackId }) {
                        // Show track details
                        Text("Track: \(track.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No Selection")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        Text("Select a region or track to view its properties.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }
            
            Spacer()
        }
        .background(Color(.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(.separatorColor)),
            alignment: .trailing
        )
    }
    
    private func findRegion(withId id: UUID, in project: AudioProject) -> AudioRegion? {
        for track in project.tracks {
            if let region = track.regions.first(where: { $0.id == id }) {
                return region
            }
        }
        return nil
    }
}
