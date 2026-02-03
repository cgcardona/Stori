//
//  NewProjectView.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

struct NewProjectView: View {
    var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var projectName = "Untitled"
    @State private var tempo: Double = 120
    @State private var timeSignature = TimeSignature.fourFour
    @State private var sampleRate: Double = 48000
    @State private var animateGradient = false
    @State private var isCreating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated gradient header
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.8),
                    Color.purple.opacity(0.6),
                    Color.pink.opacity(0.4)
                ],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .frame(height: 120)
            .overlay(
                VStack(spacing: 12) {
                    // Project icon with glow effect
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    // Title with gradient text
                    Text("New Project")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            
            // Form content with enhanced styling
            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    // Project Name with icon
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "textformat")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                            Text("Project Name")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        TextField("Enter project name", text: $projectName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.controlBackgroundColor))
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // BPM with icon
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "metronome")
                                .font(.system(size: 14))
                                .foregroundColor(.purple)
                            Text("Tempo (BPM)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        TextField("120", value: $tempo, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.controlBackgroundColor))
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Sample Rate with icon (fixed to 48 kHz - device native)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 14))
                                .foregroundColor(.pink)
                            Text("Sample Rate")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        // Fixed to 48 kHz - matches audio engine device format
                        HStack {
                            Text("48 kHz")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                            Spacer()
                            Text("(Fixed)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.controlBackgroundColor).opacity(0.5))
                                .stroke(Color.pink.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                
                Spacer()
                
                // Enhanced buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .keyboardShortcut(.escape, modifiers: [])  // Enable Escape key
                    
                    Button(action: createProject) {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                            }
                            Text(isCreating ? "Creating..." : "Create Project")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])  // Enable Enter key
                    .disabled(isCreating || projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 520, height: 480)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private func createProject() {
        guard !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isCreating = true
        
        // Add a small delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                try projectManager.createNewProject(
                    name: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                    tempo: tempo
                )
                dismiss()
            } catch {
                isCreating = false
                // Show error message to user
                if let projectError = error as? ProjectError {
                    // You could show an alert here or set an error state
                    // For now, we'll just print the error
                    // In a production app, you'd want to show this to the user
                } else {
                }
            }
        }
    }
    
    private var sampleRateText: String {
        switch sampleRate {
        case 44100: return "44.1 kHz"
        case 48000: return "48 kHz"
        case 96000: return "96 kHz"
        default: return "\(Int(sampleRate/1000)) kHz"
        }
    }
}
