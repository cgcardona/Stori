//
//  DAWControlBar.swift
//  Stori
//
//  Professional DAW control bar with industry-standard layout and functionality
//

import SwiftUI

struct DAWControlBar: View {
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    var metronomeEngine: MetronomeEngine
    @Binding var showingMixer: Bool
    @Binding var showingInspector: Bool
    @Binding var showingSelection: Bool
    @Binding var showingStepSequencer: Bool
    @Binding var showingPianoRoll: Bool
    @Binding var showingSynthesizer: Bool
    @Binding var catchPlayheadEnabled: Bool  // "Catch playhead" toggle for auto-scroll
    
    // MARK: - State
    @State private var showingTempoEditor = false
    @State private var showingKeySignatureEditor = false
    @State private var showingTimeSignatureEditor = false
    @State private var showingMetronomeSettings = false
    @State private var editedTempo: Double = 120
    @State private var isCountingIn = false  // True during count-in before recording
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Section: View Toggles
            HStack(spacing: 6) {
                DAWControlButton(
                    icon: "slider.horizontal.3",
                    isActive: showingMixer,
                    tooltip: "Show/Hide Mixer (⌘M)",
                    accessibilityLabel: "Mixer",
                    accessibilityIdentifier: "toggle_mixer"
                ) {
                    NotificationCenter.default.post(name: .toggleMixer, object: nil)
                }
                .keyboardShortcut("m", modifiers: .command)
                
                DAWControlButton(
                    icon: "waveform",
                    isActive: showingSynthesizer,
                    tooltip: "Show/Hide Synthesizer (⌘⌥I)",
                    accessibilityLabel: "Synthesizer",
                    accessibilityIdentifier: "toggle_synthesizer"
                ) {
                    NotificationCenter.default.post(name: .toggleSynthesizer, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                
                DAWControlButton(
                    icon: "pianokeys",
                    isActive: showingPianoRoll,
                    tooltip: "Show/Hide Piano Roll (⌘⌥P)",
                    accessibilityLabel: "Piano Roll",
                    accessibilityIdentifier: "toggle_piano_roll"
                ) {
                    NotificationCenter.default.post(name: .togglePianoRoll, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                
                DAWControlButton(
                    icon: "square.grid.3x3",
                    isActive: showingStepSequencer,
                    tooltip: "Show/Hide Step Sequencer (⌘D)",
                    accessibilityLabel: "Step Sequencer",
                    accessibilityIdentifier: "toggle_step_sequencer"
                ) {
                    NotificationCenter.default.post(name: .toggleStepSequencer, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command])
                
                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)
                
                DAWControlButton(
                    icon: "info.circle",
                    isActive: showingSelection,
                    tooltip: "Show/Hide Selection Info (⌘⌥S)",
                    accessibilityLabel: "Selection Info",
                    accessibilityIdentifier: "toggle_selection"
                ) {
                    NotificationCenter.default.post(name: .toggleSelection, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
            .padding(.leading, 12)
            
            Spacer()
            
            // MARK: - Center Section: Transport Controls & Info
            HStack(spacing: 6) {
                // Transport Controls
                HStack(spacing: 1) {
                    // Go to Beginning
                    TransportButton(
                        icon: "backward.end.fill",
                        isActive: false,
                        accessibilityLabel: "Go to Beginning",
                        accessibilityHint: "Jump to start of timeline",
                        accessibilityIdentifier: "transport_beginning",
                        action: { audioEngine.seek(toBeat: 0) }
                    )
                    .help("Go to Beginning (Return)")
                    .keyboardShortcut(.return, modifiers: [])
                    
                    // Rewind
                    TransportButton(
                        icon: "backward.fill",
                        isActive: false,
                        accessibilityLabel: "Rewind",
                        accessibilityHint: "Skip backward one beat",
                        accessibilityIdentifier: "transport_rewind",
                        action: { 
                            audioEngine.rewindBeats(1)
                        }
                    )
                    .help("Rewind 1 beat (,)")
                    .keyboardShortcut(",", modifiers: [])
                    
                    // Play/Pause
                    TransportButton(
                        icon: audioEngine.isPlaying ? "pause.fill" : "play.fill",
                        isActive: audioEngine.isPlaying,
                        accessibilityLabel: audioEngine.isPlaying ? "Pause" : "Play",
                        accessibilityHint: audioEngine.isPlaying ? "Pause playback" : "Start playback from current position",
                        accessibilityValue: audioEngine.isPlaying ? "Playing" : "Stopped",
                        accessibilityIdentifier: "transport_play",
                        action: {
                            if audioEngine.isPlaying {
                                audioEngine.pause()
                            } else {
                                audioEngine.play()
                            }
                        }
                    )
                    .help(audioEngine.isPlaying ? "Pause (Space)" : "Play (Space)")
                    .keyboardShortcut(.space, modifiers: [])
                    
                    // Stop
                    TransportButton(
                        icon: "stop.fill",
                        isActive: false,
                        accessibilityLabel: "Stop",
                        accessibilityHint: "Stop playback and return to start",
                        accessibilityIdentifier: "transport_stop",
                        action: { 
                            
                            if audioEngine.isRecording {
                                audioEngine.stopRecording()
                            } else {
                                audioEngine.stop()
                            }
                            // Note: stop() now handles resetting position to 0:00
                        }
                    )
                    .help("Stop (⌃Space)")
                    .keyboardShortcut(.space, modifiers: .control)
                    
                    // Record (with count-in support)
                    TransportButton(
                        icon: "record.circle.fill",
                        isActive: audioEngine.isRecording || isCountingIn,
                        color: .red,
                        accessibilityLabel: audioEngine.isRecording ? "Stop Recording" : (isCountingIn ? "Recording Count-in" : "Record"),
                        accessibilityHint: audioEngine.isRecording ? "Stop recording and save take" : "Start recording audio",
                        accessibilityValue: audioEngine.isRecording ? "Recording" : (isCountingIn ? "Count-in" : "Ready"),
                        accessibilityIdentifier: "transport_record",
                        action: {
                            handleRecordButton()
                        }
                    )
                    .help(audioEngine.isRecording ? "Stop Recording (R)" : (isCountingIn ? "Count-in..." : "Record (R)"))
                    .keyboardShortcut("r", modifiers: [])
                    
                    // Fast Forward
                    TransportButton(
                        icon: "forward.fill",
                        isActive: false,
                        accessibilityLabel: "Fast Forward",
                        accessibilityHint: "Skip forward one beat",
                        accessibilityIdentifier: "transport_forward",
                        action: { 
                            audioEngine.fastForwardBeats(1)
                        }
                    )
                    .help("Fast Forward 1 beat (.)")
                    .keyboardShortcut(".", modifiers: [])
                    
                    // Go to End
                    TransportButton(
                        icon: "forward.end.fill",
                        isActive: false,
                        accessibilityLabel: "Go to End",
                        accessibilityHint: "Jump to end of timeline",
                        accessibilityIdentifier: "transport_end",
                        action: { 
                            audioEngine.skipToEnd()
                        }
                    )
                    .help("Go to End (Cmd+Shift+Return)")
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                }
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 6)
                
                // Cycle
                TransportButton(
                    icon: "repeat",
                    isActive: audioEngine.isCycleEnabled,
                    accessibilityLabel: "Cycle",
                    accessibilityHint: "Toggle loop playback mode",
                    accessibilityValue: audioEngine.isCycleEnabled ? "Enabled" : "Disabled",
                    accessibilityIdentifier: "transport_cycle",
                    action: { audioEngine.toggleCycle() }
                )
                .help("Toggle Cycle Mode (C)")
                .keyboardShortcut("c", modifiers: [])
                
                // Catch Playhead (auto-scroll to follow playhead)
                TransportButton(
                    icon: "arrow.right.to.line",
                    isActive: catchPlayheadEnabled,
                    accessibilityLabel: "Catch Playhead",
                    accessibilityHint: "Toggle auto-scroll to follow playback",
                    accessibilityValue: catchPlayheadEnabled ? "Enabled" : "Disabled",
                    accessibilityIdentifier: "transport_catch_playhead",
                    action: { catchPlayheadEnabled.toggle() }
                )
                .help("Catch Playhead - auto-scroll to follow (⌘⇧F)")
                .keyboardShortcut("f", modifiers: [.command, .shift])
                
                // Metronome
                MetronomeButton(
                    metronomeEngine: metronomeEngine,
                    showingSettings: $showingMetronomeSettings
                )
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 6)
                
                // Time Display - Logic-style LCD display
                VStack(spacing: 0) {
                    Text(audioEngine.currentMusicalTimeString)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .frame(width: 100, alignment: .center)
                        .monospacedDigit()
                    
                    Text("BARS")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                )
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 6)
                
                // Project Info
                HStack(spacing: 6) {
                    // Tempo
                    Button(action: { showingTempoEditor.toggle() }) {
                        VStack(spacing: 0) {
                            Text("\(Int(projectManager.currentProject?.tempo ?? 120))")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.semibold)
                            Text("BPM")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .tracking(0.3)
                        }
                        .frame(width: 40)
                    }
                    .buttonStyle(.plain)
                    .help("Edit Tempo (⌘⌥T)")
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    .contextMenu {
                        Button("Set to 60 BPM") { setTempo(60) }
                        Button("Set to 120 BPM") { setTempo(120) }
                        Button("Set to 140 BPM") { setTempo(140) }
                        Button("Set to 180 BPM") { setTempo(180) }
                        Divider()
                        Button("Tap Tempo") { /* TODO: Implement tap tempo */ }
                    }
                    .popover(isPresented: $showingTempoEditor) {
                        tempoEditor
                            .onAppear {
                                editedTempo = projectManager.currentProject?.tempo ?? 120
                            }
                    }
                    
                    // Key Signature
                    Button(action: { showingKeySignatureEditor.toggle() }) {
                        VStack(spacing: 0) {
                            Text(projectManager.currentProject?.keySignature ?? "C")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.semibold)
                            Text("KEY")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .tracking(0.3)
                        }
                        .frame(width: 32)
                    }
                    .buttonStyle(.plain)
                    .help("Edit Key Signature (⌘K)")
                    .keyboardShortcut("k", modifiers: .command)
                    .contextMenu {
                        Button("C Major") { setKeySignature("C") }
                        Button("G Major") { setKeySignature("G") }
                        Button("D Major") { setKeySignature("D") }
                        Button("A Major") { setKeySignature("A") }
                        Button("E Major") { setKeySignature("E") }
                        Divider()
                        Button("F Major") { setKeySignature("F") }
                        Button("Bb Major") { setKeySignature("Bb") }
                        Button("Eb Major") { setKeySignature("Eb") }
                    }
                    .popover(isPresented: $showingKeySignatureEditor) {
                        keySignatureEditor
                    }
                    
                    // Time Signature
                    Button(action: { showingTimeSignatureEditor.toggle() }) {
                        VStack(spacing: 0) {
                            Text(projectManager.currentProject?.timeSignature.description ?? "4/4")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.semibold)
                            Text("TIME")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .tracking(0.3)
                        }
                        .frame(width: 36)
                    }
                    .buttonStyle(.plain)
                    .help("Edit Time Signature (⌘⇧T)")
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .contextMenu {
                        Button("4/4") { setTimeSignature(4, 4) }
                        Button("3/4") { setTimeSignature(3, 4) }
                        Button("2/4") { setTimeSignature(2, 4) }
                        Button("6/8") { setTimeSignature(6, 8) }
                        Button("12/8") { setTimeSignature(12, 8) }
                        Divider()
                        Button("7/8") { setTimeSignature(7, 8) }
                        Button("5/4") { setTimeSignature(5, 4) }
                    }
                    .popover(isPresented: $showingTimeSignatureEditor) {
                        timeSignatureEditor
                    }
                }
            }
            
            Spacer()
            
            // MARK: - Right Section: Update Indicator, Master Volume & Inspector
            HStack(spacing: 6) {
                // Update Indicator
                UpdateIndicatorView(updateService: UpdateService.shared)
                
                // Separator (only when update indicator is visible)
                if UpdateService.shared.hasUpdate || { if case .aheadOfRelease = UpdateService.shared.state { return true } else { return false } }() {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1, height: 24)
                        .padding(.horizontal, 2)
                }
                
                // Master Volume
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { audioEngine.masterVolume },
                        set: { newValue in
                            audioEngine.updateMasterVolume(Float(newValue))
                        }
                    ), in: 0...1)
                        .frame(width: 70)
                        .help("Master Volume: \(Int(audioEngine.masterVolume * 100))%")
                    
                    Text("\(Int(audioEngine.masterVolume * 100))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                }
                .help("Master Volume Control")
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 6)
                
                // Composer Toggle - hidden until Composer service is available
                // DAWControlButton(
                //     icon: "wand.and.stars",
                //     isActive: showingInspector,
                //     tooltip: "Show/Hide Composer (⌘C)",
                //     accessibilityLabel: "Composer",
                //     accessibilityIdentifier: "toggle_composer"
                // ) {
                //     NotificationCenter.default.post(name: .toggleInspector, object: nil)
                // }
                // .keyboardShortcut("c", modifiers: .command)
            }
            .padding(.trailing, 12)
        }
        .frame(height: 48)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }
    
    
    // MARK: - Helper Methods
    private func setTempo(_ tempo: Double) {
        projectManager.updateTempo(tempo)
    }
    
    private func setKeySignature(_ keySignature: String) {
        projectManager.updateKeySignature(keySignature)
    }
    
    private func setTimeSignature(_ numerator: Int, _ denominator: Int) {
        let timeSignature = TimeSignature(numerator: numerator, denominator: denominator)
        projectManager.updateTimeSignature(timeSignature)
    }
    
    // MARK: - Record with Count-In
    
    private func handleRecordButton() {
        if audioEngine.isRecording {
            audioEngine.stopRecording()
            return
        }
        
        if isCountingIn { return }
        
        // Check if count-in is enabled
        if metronomeEngine.countInEnabled {
            isCountingIn = true
            
            Task {
                // Pre-setup everything BEFORE count-in to avoid delay after
                await audioEngine.prepareRecordingDuringCountIn()
                
                // Perform count-in (uses precise DispatchSourceTimer)
                await metronomeEngine.performCountIn()
                
                // Count-in complete, start recording immediately
                // Everything is already prepared, just flip the switch
                await MainActor.run {
                    isCountingIn = false
                    audioEngine.startRecordingAfterCountIn()
                }
            }
        } else {
            // No count-in, start recording immediately
            audioEngine.record()
        }
    }
    
    // MARK: - Editor Views
    private var tempoEditor: some View {
        VStack(spacing: 12) {
            Text("Tempo")
                .font(.headline)
            
            HStack {
                TextField("BPM", value: $editedTempo, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit {
                        setTempo(editedTempo)
                        showingTempoEditor = false
                    }
                
                Text("BPM")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button("Cancel") { 
                    showingTempoEditor = false 
                }
                Button("OK") { 
                    setTempo(editedTempo)
                    showingTempoEditor = false 
                }
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


// MARK: - Metronome Button

struct MetronomeButton: View {
    @Bindable var metronomeEngine: MetronomeEngine
    @Binding var showingSettings: Bool
    
    var body: some View {
        Button(action: { metronomeEngine.toggle() }) {
            ZStack {
                // Background
                Circle()
                    .fill(metronomeEngine.isEnabled ? Color.accentColor : Color.clear)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(metronomeEngine.isEnabled ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                
                // Icon with beat flash
                Image(systemName: "metronome.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(metronomeEngine.isEnabled ? .white : .secondary)
                    .scaleEffect(metronomeEngine.beatFlash ? 1.15 : 1.0)
                    .animation(.easeOut(duration: 0.08), value: metronomeEngine.beatFlash)
                
                // Beat indicator dot
                if metronomeEngine.isEnabled && metronomeEngine.beatFlash {
                    Circle()
                        .fill(metronomeEngine.currentBeat == 1 ? Color.orange : Color.white)
                        .frame(width: 4, height: 4)
                        .offset(y: -12)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(metronomeEngine.isEnabled ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: metronomeEngine.isEnabled)
        .help("Toggle Metronome (K)")
        .keyboardShortcut("k", modifiers: [])
        .contextMenu {
            Toggle("Metronome Enabled", isOn: $metronomeEngine.isEnabled)
            
            Divider()
            
            Toggle("Count-In", isOn: $metronomeEngine.countInEnabled)
            
            Menu("Count-In Bars") {
                Button("1 Bar") { metronomeEngine.countInBars = 1 }
                Button("2 Bars") { metronomeEngine.countInBars = 2 }
                Button("4 Bars") { metronomeEngine.countInBars = 4 }
            }
            .disabled(!metronomeEngine.countInEnabled)
            
            Divider()
            
            Button("Metronome Settings...") {
                showingSettings = true
            }
        }
        .popover(isPresented: $showingSettings) {
            MetronomeSettingsView(metronomeEngine: metronomeEngine)
        }
    }
}

// MARK: - Metronome Settings View

struct MetronomeSettingsView: View {
    @Bindable var metronomeEngine: MetronomeEngine
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "metronome.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Metronome")
                    .font(.headline)
                Spacer()
            }
            
            Divider()
            
            // Enable Toggle
            Toggle("Enable Metronome", isOn: $metronomeEngine.isEnabled)
                .toggleStyle(.switch)
            
            // Volume Slider
            VStack(alignment: .leading, spacing: 6) {
                Text("Volume")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(value: $metronomeEngine.volume, in: 0...1)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(metronomeEngine.volume * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 36)
                }
            }
            
            Divider()
            
            // Count-In Section
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Count-In Before Recording", isOn: $metronomeEngine.countInEnabled)
                    .toggleStyle(.switch)
                
                if metronomeEngine.countInEnabled {
                    Picker("Count-In Bars:", selection: $metronomeEngine.countInBars) {
                        Text("1 Bar").tag(1)
                        Text("2 Bars").tag(2)
                        Text("4 Bars").tag(4)
                    }
                    .pickerStyle(.segmented)
                }
            }
            
            Divider()
            
            // Beat Indicator Preview
            HStack(spacing: 8) {
                Text("Beat:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ForEach(1...4, id: \.self) { beat in
                    Circle()
                        .fill(metronomeEngine.currentBeat == beat ? 
                              (beat == 1 ? Color.orange : Color.accentColor) : 
                              Color.secondary.opacity(0.3))
                        .frame(width: 12, height: 12)
                        .scaleEffect(metronomeEngine.currentBeat == beat && metronomeEngine.beatFlash ? 1.3 : 1.0)
                        .animation(.easeOut(duration: 0.08), value: metronomeEngine.beatFlash)
                }
                
                Spacer()
            }
            
            // Close Button
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 280)
    }
}
