//
//  CreateTrackDialog.swift
//  Stori
//
//  Professional track creation dialog with instrument selection
//

import SwiftUI

enum TrackCreationType: String, CaseIterable {
    case midi = "MIDI"
    case audio = "Audio"
    
    var icon: String {
        switch self {
        case .midi: return "music.note"
        case .audio: return "waveform"
        }
    }
    
    var color: Color {
        switch self {
        case .midi: return .green
        case .audio: return .blue
        }
    }
}

/// Configuration for a new track
struct NewTrackConfig {
    let type: TrackCreationType
    let count: Int
    let outputBusId: UUID?
}

struct CreateTrackDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    
    let availableBuses: [MixerBus]
    let onCreateTracks: (NewTrackConfig) async -> Void
    
    @State private var selectedType: TrackCreationType = .midi
    @State private var numberOfTracks: Int = 1
    @State private var showingDetails: Bool = true
    
    // Output routing
    @State private var selectedOutputBusId: UUID?
    
    // Loading state
    @State private var isCreating: Bool = false
    
    private var selectedBusName: String {
        guard let busId = selectedOutputBusId,
              let bus = availableBuses.first(where: { $0.id == busId }) else {
            return "Stereo Output"
        }
        return bus.name
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title - Fixed at top with subtle separator
            VStack(spacing: 0) {
                Text("Create New Track")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                
                Divider()
                    .background(Color(nsColor: .separatorColor).opacity(0.5))
            }
            
            // Scrollable content area
            ScrollView {
                VStack(spacing: 0) {
                    // Track Type Selection - Professional cards
                    HStack(spacing: 16) {
                        // MIDI Track Card
                        TrackTypeCard(
                            type: .midi,
                            isSelected: selectedType == .midi,
                            action: { selectedType = .midi }
                        )
                        
                        // Audio Track Card  
                        TrackTypeCard(
                            type: .audio,
                            isSelected: selectedType == .audio,
                            action: { selectedType = .audio }
                        )
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    
                    // MIDI Track - Info about instrument selection
                    if selectedType == .midi {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("Select an instrument in the mixer after creating the track.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.05))
                            )
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                    }
                    
                    // Output Routing Section (if buses exist)
                    if !availableBuses.isEmpty {
                        outputRoutingSection
                    }
                    
                    // Details Section - Professional disclosure
                    VStack(spacing: 0) {
                        Divider()
                            .padding(.horizontal, 28)
                            .padding(.top, 24)
                        
                        // Custom Details Header - Fully clickable
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingDetails.toggle()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: showingDetails ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                    .frame(width: 12)
                                
                                Text("Details")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                
                                Spacer()
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        // Details Content
                        if showingDetails {
                            VStack(spacing: 18) {
                                if selectedType == .audio {
                                    // Audio Input Selection
                                    HStack(alignment: .center, spacing: 12) {
                                        Text("Audio Input:")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                            .frame(width: 110, alignment: .trailing)
                                        
                                        Text("Input 1 (MacBook Pro Microphone)")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                
                                // Number of tracks
                                HStack(spacing: 12) {
                                    Text("Number of tracks:")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                    
                                    Spacer()
                                    
                                    TextField("", value: $numberOfTracks, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 70)
                                        .multilineTextAlignment(.center)
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                            .padding(.top, 8)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            
            Spacer()
            
            // Bottom Action Bar - Professional footer
            VStack(spacing: 0) {
                Divider()
                    .background(Color(nsColor: .separatorColor).opacity(0.5))
                
                HStack(spacing: 10) {
                    // Loading indicator
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Creating track...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Cancel Button
                    Button("Cancel") {
                        isPresented = false
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isCreating)
                    .storiAccessibilityID(AccessibilityID.Track.createDialogCancel)
                    
                // Create Button
                Button("Create") {
                    Task {
                        isCreating = true
                        let config = NewTrackConfig(
                            type: selectedType,
                            count: max(1, numberOfTracks),
                            outputBusId: selectedOutputBusId
                        )
                        await onCreateTracks(config)
                        isCreating = false
                        isPresented = false
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isCreating)
                .storiAccessibilityID(AccessibilityID.Track.createDialogConfirm)
                }
                .accessibilityElement(children: .contain)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        }
        .frame(width: 700, height: 600)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .overlay(
                    Color.black.opacity(0.02)
                )
        )
        .accessibilityIdentifier(AccessibilityID.Track.createDialog)
    }
    
    // MARK: - Output Routing Section
    
    private var outputRoutingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Output")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            Menu {
                Button("Stereo Output") {
                    selectedOutputBusId = nil
                }
                
                if !availableBuses.isEmpty {
                    Divider()
                    
                    ForEach(availableBuses) { bus in
                        Button(bus.name) {
                            selectedOutputBusId = bus.id
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedBusName)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
    }
}

// MARK: - Embedded Instrument Picker

// MARK: - Track Type Card

struct TrackTypeCard: View {
    let type: TrackCreationType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }) {
            VStack(spacing: 18) {
                // Icon Circle - Professional and refined
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [type.color, type.color.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                        .shadow(
                            color: isSelected ? type.color.opacity(0.35) : type.color.opacity(0.15), 
                            radius: isSelected ? 10 : 5,
                            y: isSelected ? 3 : 2
                        )
                    
                    Image(systemName: type.icon)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
                
                // Label
                Text(type.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .shadow(color: .black.opacity(isSelected ? 0.08 : 0.03), radius: isSelected ? 8 : 3, y: isSelected ? 2 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected 
                            ? Color.accentColor.opacity(0.6) 
                            : Color(nsColor: .separatorColor).opacity(0.2), 
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .scaleEffect(isSelected ? 1.0 : 0.98)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(type == .audio ? AccessibilityID.Track.createDialogTypeAudio : AccessibilityID.Track.createDialogTypeMIDI)
    }
}
