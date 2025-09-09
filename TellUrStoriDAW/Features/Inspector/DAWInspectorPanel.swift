//
//  DAWInspectorPanel.swift
//  TellUrStoriDAW
//
//  Professional DAW inspector panel for track and region properties
//

import SwiftUI

struct DAWInspectorPanel: View {
    @Binding var selectedTrackId: UUID?
    let project: AudioProject?
    @ObservedObject var audioEngine: AudioEngine
    
    @State private var selectedTab: InspectorTab = .track
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Inspector")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Inspector Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.controlBackgroundColor))
            
            // Tab selector
            HStack(spacing: 0) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        Text(tab.displayName)
                            .font(.system(size: 11))
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // Content area
            ScrollView {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .track:
                        trackInspectorContent
                    case .region:
                        regionInspectorContent
                    case .project:
                        projectInspectorContent
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
            alignment: .leading
        )
    }
    
    // MARK: - Track Inspector Content
    private var trackInspectorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let trackId = selectedTrackId,
               let project = project,
               let track = project.tracks.first(where: { $0.id == trackId }) {
                
                // Track Info Section
                InspectorSection(title: "Track Info") {
                    VStack(spacing: 12) {
                        InspectorField(label: "Name", value: track.name)
                        InspectorField(label: "Type", value: "Audio Track")
                        InspectorField(label: "Color", value: track.color.rawValue.capitalized)
                    }
                }
                
                // Audio Settings Section
                InspectorSection(title: "Audio Settings") {
                    VStack(spacing: 12) {
                        InspectorSlider(
                            label: "Volume",
                            value: .constant(Double(track.mixerSettings.volume)),
                            range: 0...1,
                            format: "%.0f%%"
                        )
                        
                        InspectorSlider(
                            label: "Pan",
                            value: .constant(Double(track.mixerSettings.pan)),
                            range: -1...1,
                            format: "%.1f"
                        )
                        
                        InspectorToggle(
                            label: "Muted",
                            isOn: .constant(track.mixerSettings.isMuted)
                        )
                        
                        InspectorToggle(
                            label: "Solo",
                            isOn: .constant(track.mixerSettings.isSolo)
                        )
                    }
                }
                
                // EQ Settings Section
                InspectorSection(title: "EQ Settings") {
                    VStack(spacing: 12) {
                        InspectorSlider(
                            label: "High",
                            value: .constant(Double(track.mixerSettings.highEQ)),
                            range: -20...20,
                            format: "%.1f dB"
                        )
                        
                        InspectorSlider(
                            label: "Mid",
                            value: .constant(Double(track.mixerSettings.midEQ)),
                            range: -20...20,
                            format: "%.1f dB"
                        )
                        
                        InspectorSlider(
                            label: "Low",
                            value: .constant(Double(track.mixerSettings.lowEQ)),
                            range: -20...20,
                            format: "%.1f dB"
                        )
                    }
                }
                
            } else {
                Text("No track selected")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
    }
    
    // MARK: - Region Inspector Content
    private var regionInspectorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No region selected")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
        }
    }
    
    // MARK: - Project Inspector Content
    private var projectInspectorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let project = project {
                InspectorSection(title: "Project Info") {
                    VStack(spacing: 12) {
                        InspectorField(label: "Name", value: project.name)
                        InspectorField(label: "Tempo", value: "\(Int(project.tempo)) BPM")
                        InspectorField(label: "Key", value: project.keySignature)
                        InspectorField(label: "Time Signature", value: project.timeSignature.description)
                        InspectorField(label: "Sample Rate", value: "\(Int(project.sampleRate)) Hz")
                        InspectorField(label: "Tracks", value: "\(project.tracks.count)")
                    }
                }
                
                InspectorSection(title: "Performance") {
                    VStack(spacing: 12) {
                        InspectorField(label: "Buffer Size", value: "\(project.bufferSize) samples")
                    }
                }
            } else {
                Text("No project loaded")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
    }
}

// MARK: - Inspector Tab
enum InspectorTab: CaseIterable {
    case track, region, project
    
    var displayName: String {
        switch self {
        case .track: return "Track"
        case .region: return "Region"
        case .project: return "Project"
        }
    }
}

// MARK: - Inspector Components
struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            content
        }
    }
}

struct InspectorField: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

struct InspectorSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(String(format: format, value * (format.contains("%%") ? 100 : 1)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
            }
            
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

struct InspectorToggle: View {
    let label: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .controlSize(.small)
        }
    }
}

#Preview {
    DAWInspectorPanel(
        selectedTrackId: .constant(nil),
        project: nil,
        audioEngine: AudioEngine()
    )
    .frame(width: 250, height: 600)
}
