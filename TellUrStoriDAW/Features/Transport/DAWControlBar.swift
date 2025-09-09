//
//  DAWControlBar.swift
//  TellUrStoriDAW
//
//  Professional DAW control bar with industry-standard layout and functionality
//

import SwiftUI

struct DAWControlBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    
    // MARK: - State
    @State private var showingTempoEditor = false
    @State private var showingKeySignatureEditor = false
    @State private var showingTimeSignatureEditor = false
    @State private var masterVolume: Double = 0.8
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Section: View Toggles
            HStack(spacing: 6) {
                DAWControlButton(
                    icon: "slider.horizontal.3",
                    isActive: false, // TODO: Connect to mixer visibility state
                    tooltip: "Show/Hide Mixer"
                ) {
                    // TODO: Toggle mixer visibility
                }
                
                DAWControlButton(
                    icon: "books.vertical",
                    isActive: false,
                    tooltip: "Show/Hide Library"
                ) {
                    // TODO: Toggle library visibility
                }
                
                DAWControlButton(
                    icon: "sidebar.right",
                    isActive: false,
                    tooltip: "Show/Hide Inspector"
                ) {
                    // TODO: Toggle inspector visibility
                }
            }
            .padding(.leading, 12)
            
            Spacer()
            
            // MARK: - Center Section: Transport Controls & Info
            HStack(spacing: 8) {
                // Transport Controls
                HStack(spacing: 2) {
                    // Go to Beginning
                    TransportButton(
                        icon: "backward.end.fill",
                        isActive: false,
                        action: { audioEngine.seek(to: 0) }
                    )
                    
                    // Rewind
                    TransportButton(
                        icon: "backward.fill",
                        isActive: false,
                        action: { 
                            let currentTime = audioEngine.currentPosition.timeInterval
                            audioEngine.seek(to: max(0, currentTime - 10))
                        }
                    )
                    
                    // Play/Pause
                    TransportButton(
                        icon: audioEngine.isPlaying ? "pause.fill" : "play.fill",
                        isActive: audioEngine.isPlaying,
                        action: {
                            if audioEngine.isPlaying {
                                audioEngine.stop()
                            } else {
                                audioEngine.play()
                            }
                        }
                    )
                    
                    // Stop
                    TransportButton(
                        icon: "stop.fill",
                        isActive: false,
                        action: { 
                            audioEngine.stop()
                            audioEngine.seek(to: 0)
                        }
                    )
                    
                    // Record
                    TransportButton(
                        icon: "record.circle.fill",
                        isActive: audioEngine.isRecording,
                        action: {
                            if audioEngine.isRecording {
                                audioEngine.stopRecording()
                            } else {
                                audioEngine.record()
                            }
                        }
                    )
                    
                    // Fast Forward
                    TransportButton(
                        icon: "forward.fill",
                        isActive: false,
                        action: { 
                            let currentTime = audioEngine.currentPosition.timeInterval
                            audioEngine.seek(to: currentTime + 10)
                        }
                    )
                    
                    // Go to End
                    TransportButton(
                        icon: "forward.end.fill",
                        isActive: false,
                        action: { 
                            if let project = projectManager.currentProject {
                                let duration = project.tracks.compactMap { track in
                                    track.regions.map { $0.startTime + $0.duration }.max()
                                }.max() ?? 0
                                audioEngine.seek(to: duration)
                            }
                        }
                    )
                }
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 8)
                
                // Cycle
                TransportButton(
                    icon: "repeat",
                    isActive: audioEngine.isCycleEnabled,
                    action: { audioEngine.toggleCycle() }
                )
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 8)
                
                // Time Display
                VStack(spacing: 1) {
                    Text(audioEngine.currentTimeString)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("BARS \(audioEngine.currentMusicalTimeString)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 8)
                
                // Project Info
                HStack(spacing: 8) {
                    // Tempo
                    Button(action: { showingTempoEditor.toggle() }) {
                        VStack(spacing: 1) {
                            Text("\(Int(projectManager.currentProject?.tempo ?? 120))")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.medium)
                            Text("BPM")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingTempoEditor) {
                        tempoEditor
                    }
                    
                    // Key Signature
                    Button(action: { showingKeySignatureEditor.toggle() }) {
                        VStack(spacing: 1) {
                            Text(projectManager.currentProject?.keySignature ?? "C")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.medium)
                            Text("KEY")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingKeySignatureEditor) {
                        keySignatureEditor
                    }
                    
                    // Time Signature
                    Button(action: { showingTimeSignatureEditor.toggle() }) {
                        VStack(spacing: 1) {
                            Text(projectManager.currentProject?.timeSignature.description ?? "4/4")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.medium)
                            Text("TIME")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingTimeSignatureEditor) {
                        timeSignatureEditor
                    }
                }
            }
            
            Spacer()
            
            // MARK: - Right Section: Master Volume & View Controls
            HStack(spacing: 8) {
                // Master Volume
                VStack(spacing: 2) {
                    Text("MASTER")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Slider(value: $masterVolume, in: 0...1)
                            .frame(width: 60)
                        
                        Text("\(Int(masterVolume * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 28)
                    }
                }
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 32)
                    .padding(.horizontal, 6)
                
                // CPU Usage
                VStack(spacing: 1) {
                    Text("\(Int(audioEngine.cpuUsage * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(cpuColor)
                    Text("CPU")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // More View Toggles
                HStack(spacing: 6) {
                    DAWControlButton(
                        icon: "waveform",
                        isActive: false,
                        tooltip: "Show/Hide Track Area"
                    ) {
                        // TODO: Toggle track area visibility
                    }
                    
                    DAWControlButton(
                        icon: "list.bullet",
                        isActive: false,
                        tooltip: "Show/Hide Event List"
                    ) {
                        // TODO: Toggle event list visibility
                    }
                    
                    DAWControlButton(
                        icon: "square.grid.3x3",
                        isActive: false,
                        tooltip: "Show/Hide Step Sequencer"
                    ) {
                        // TODO: Toggle step sequencer visibility
                    }
                }
            }
            .padding(.trailing, 12)
        }
        .frame(height: 56)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }
    
    // MARK: - CPU Color
    private var cpuColor: Color {
        let usage = audioEngine.cpuUsage
        if usage > 0.8 {
            return .red
        } else if usage > 0.6 {
            return .orange
        } else {
            return .green
        }
    }
    
    // MARK: - Editor Views
    private var tempoEditor: some View {
        VStack(spacing: 12) {
            Text("Tempo")
                .font(.headline)
            
            HStack {
                TextField("BPM", value: .constant(projectManager.currentProject?.tempo ?? 120), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                
                Text("BPM")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button("Cancel") { showingTempoEditor = false }
                Button("OK") { showingTempoEditor = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 200)
    }
    
    private var keySignatureEditor: some View {
        VStack(spacing: 12) {
            Text("Key Signature")
                .font(.headline)
            
            // Key signature picker would go here
            Text("Key signature editor coming soon")
                .foregroundColor(.secondary)
            
            Button("OK") { showingKeySignatureEditor = false }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 200)
    }
    
    private var timeSignatureEditor: some View {
        VStack(spacing: 12) {
            Text("Time Signature")
                .font(.headline)
            
            // Time signature picker would go here
            Text("Time signature editor coming soon")
                .foregroundColor(.secondary)
            
            Button("OK") { showingTimeSignatureEditor = false }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 200)
    }
}

#Preview {
    DAWControlBar(
        audioEngine: AudioEngine(),
        projectManager: ProjectManager()
    )
    .frame(width: 800)
}
