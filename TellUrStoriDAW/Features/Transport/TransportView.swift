//
//  TransportView.swift
//  TellUrStoriDAW
//
//  Transport controls for playback and recording
//

import SwiftUI

struct TransportView: View {
    @ObservedObject var audioEngine: AudioEngine
    
    var body: some View {
        HStack(spacing: 0) {
            // Transport controls
            HStack(spacing: 16) {
                // Rewind
                TransportButton(
                    icon: "backward.fill",
                    isActive: false,
                    color: .secondary,
                    action: { audioEngine.rewind() }
                )
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                // Stop
                TransportButton(
                    icon: "stop.fill",
                    isActive: audioEngine.transportState == .stopped,
                    action: { audioEngine.stop() }
                )
                .keyboardShortcut(.space, modifiers: [.command])
                
                // Play/Pause
                TransportButton(
                    icon: audioEngine.transportState == .playing ? "pause.fill" : "play.fill",
                    isActive: audioEngine.transportState == .playing,
                    action: {
                        if audioEngine.transportState == .playing {
                            audioEngine.pause()
                        } else {
                            audioEngine.play()
                        }
                    }
                )
                .keyboardShortcut(.space, modifiers: [])
                
                // Record
                TransportButton(
                    icon: "record.circle.fill",
                    isActive: audioEngine.transportState == .recording,
                    color: .red,
                    action: {
                        if audioEngine.transportState == .recording {
                            audioEngine.stopRecording()
                        } else {
                            audioEngine.record()
                        }
                    }
                )
                .keyboardShortcut("r", modifiers: [])
                
                // Forward
                TransportButton(
                    icon: "forward.fill",
                    isActive: false,
                    color: .secondary,
                    action: { audioEngine.fastForward() }
                )
                .keyboardShortcut(.rightArrow, modifiers: [])
                
                // Cycle
                TransportButton(
                    icon: "repeat",
                    isActive: audioEngine.isCycleEnabled,
                    color: audioEngine.isCycleEnabled ? .yellow : .secondary,
                    action: { audioEngine.toggleCycle() }
                )
                .keyboardShortcut("c", modifiers: [])
            }
            .padding(.leading, 20)
            
            Spacer()
            
            // Position display
            VStack(spacing: 4) {
                // Time display
                HStack(spacing: 8) {
                    Text("TIME")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(audioEngine.currentTimeString)
                        .font(.title2.monospacedDigit())
                        .fontWeight(.medium)
                }
                
                // Musical time display
                HStack(spacing: 8) {
                    Text("BARS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(audioEngine.currentMusicalTimeString)
                        .font(.title3.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .frame(height: 80)
        .background(Color(.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .top
        )
    }
}

// MARK: - Transport Button
struct TransportButton: View {
    let icon: String
    let isActive: Bool
    let color: Color
    let action: () -> Void
    
    init(icon: String, isActive: Bool = false, color: Color = .accentColor, action: @escaping () -> Void) {
        self.icon = icon
        self.isActive = isActive
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(isActive ? .white : color)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isActive ? color : Color.clear)
                        .overlay(
                            Circle()
                                .stroke(color, lineWidth: 2)
                        )
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isActive)
    }
}