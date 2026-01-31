import SwiftUI

// MARK: - MIDI Transform Operations

/// Available transform operations for batch MIDI editing
enum MIDITransformOperation: String, CaseIterable, Identifiable {
    case transpose = "Transpose"
    case quantize = "Quantize"
    case humanize = "Humanize"
    case velocityScale = "Scale Velocity"
    case velocitySet = "Set Velocity"
    case velocityRamp = "Velocity Ramp"
    case timeStretch = "Time Stretch"
    case reverse = "Reverse"
    case legato = "Legato All"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .transpose: return "arrow.up.arrow.down"
        case .quantize: return "grid"
        case .humanize: return "waveform.path.ecg"
        case .velocityScale: return "slider.horizontal.3"
        case .velocitySet: return "dial.min"
        case .velocityRamp: return "chart.line.uptrend.xyaxis"
        case .timeStretch: return "arrow.left.and.right"
        case .reverse: return "arrow.uturn.backward"
        case .legato: return "arrow.right.to.line"
        }
    }
    
    var description: String {
        switch self {
        case .transpose: return "Shift notes up or down by semitones"
        case .quantize: return "Snap note positions to grid"
        case .humanize: return "Add natural timing/velocity variation"
        case .velocityScale: return "Scale velocity by percentage"
        case .velocitySet: return "Set all notes to fixed velocity"
        case .velocityRamp: return "Create gradual velocity change"
        case .timeStretch: return "Scale note timing proportionally"
        case .reverse: return "Reverse note order in time"
        case .legato: return "Extend all notes to next note"
        }
    }
}

// MARK: - MIDI Transform View

/// Professional MIDI transform dialog for batch note operations
struct MIDITransformView: View {
    @Binding var region: MIDIRegion
    @Binding var selectedNotes: Set<UUID>
    @Binding var isPresented: Bool
    
    @State private var selectedOperation: MIDITransformOperation = .transpose
    
    // Transpose parameters
    @State private var transposeSemitones: Int = 0
    
    // Quantize parameters
    @State private var quantizeResolution: SnapResolution = .sixteenth
    @State private var quantizeStrength: Double = 100  // 0-100%
    
    // Humanize parameters
    @State private var humanizeTimingAmount: Double = 10  // 0-100 ms
    @State private var humanizeVelocityAmount: Double = 10  // 0-30
    
    // Velocity parameters
    @State private var velocityScalePercent: Double = 100  // 50-200%
    @State private var velocitySetValue: Int = 100  // 1-127
    @State private var velocityRampStart: Int = 64
    @State private var velocityRampEnd: Int = 100
    
    // Time stretch parameter
    @State private var timeStretchPercent: Double = 100  // 50-200%
    
    // Unified undo manager
    private var undoManager: UndoManager? {
        UndoService.shared.undoManager
    }
    
    private var notesToTransform: [MIDINote] {
        if selectedNotes.isEmpty {
            return region.notes
        } else {
            return region.notes.filter { selectedNotes.contains($0.id) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            HStack(spacing: 0) {
                // Operation list
                operationList
                    .frame(width: 180)
                
                Divider()
                
                // Parameters panel
                parameterPanel
                    .frame(minWidth: 280)
            }
            
            Divider()
            
            // Footer with apply button
            footer
        }
        .frame(width: 480, height: 400)
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text("MIDI Transform")
                .font(.headline)
            
            Spacer()
            
            Text("\(notesToTransform.count) notes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - Operation List
    
    private var operationList: some View {
        List(MIDITransformOperation.allCases, selection: $selectedOperation) { operation in
            HStack {
                Image(systemName: operation.icon)
                    .frame(width: 20)
                Text(operation.rawValue)
            }
            .tag(operation)
        }
        .listStyle(.sidebar)
    }
    
    // MARK: - Parameter Panel
    
    private var parameterPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Operation title and description
            VStack(alignment: .leading, spacing: 4) {
                Label(selectedOperation.rawValue, systemImage: selectedOperation.icon)
                    .font(.headline)
                
                Text(selectedOperation.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Operation-specific parameters
            Group {
                switch selectedOperation {
                case .transpose:
                    transposeParams
                case .quantize:
                    quantizeParams
                case .humanize:
                    humanizeParams
                case .velocityScale:
                    velocityScaleParams
                case .velocitySet:
                    velocitySetParams
                case .velocityRamp:
                    velocityRampParams
                case .timeStretch:
                    timeStretchParams
                case .reverse, .legato:
                    noParamsNeeded
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Parameter Views
    
    private var transposeParams: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Semitones")
                .font(.subheadline)
            
            HStack {
                Slider(value: Binding(
                    get: { Double(transposeSemitones) },
                    set: { transposeSemitones = Int($0) }
                ), in: -24...24, step: 1)
                
                Text("\(transposeSemitones > 0 ? "+" : "")\(transposeSemitones)")
                    .monospacedDigit()
                    .frame(width: 40)
            }
            
            HStack {
                Button("-12") { transposeSemitones = -12 }
                Button("-1") { transposeSemitones -= 1 }
                Button("0") { transposeSemitones = 0 }
                Button("+1") { transposeSemitones += 1 }
                Button("+12") { transposeSemitones = 12 }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var quantizeParams: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grid Resolution")
                .font(.subheadline)
            
            Picker("Resolution", selection: $quantizeResolution) {
                ForEach(SnapResolution.allCases, id: \.rawValue) { res in
                    Text(res.rawValue).tag(res)
                }
            }
            .labelsHidden()
            
            Text("Strength")
                .font(.subheadline)
            
            HStack {
                Slider(value: $quantizeStrength, in: 0...100, step: 5)
                Text("\(Int(quantizeStrength))%")
                    .monospacedDigit()
                    .frame(width: 40)
            }
        }
    }
    
    private var humanizeParams: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timing Variation (ms)")
                .font(.subheadline)
            
            HStack {
                Slider(value: $humanizeTimingAmount, in: 0...50, step: 1)
                Text("\(Int(humanizeTimingAmount))")
                    .monospacedDigit()
                    .frame(width: 30)
            }
            
            Text("Velocity Variation")
                .font(.subheadline)
            
            HStack {
                Slider(value: $humanizeVelocityAmount, in: 0...30, step: 1)
                Text("±\(Int(humanizeVelocityAmount))")
                    .monospacedDigit()
                    .frame(width: 40)
            }
        }
    }
    
    private var velocityScaleParams: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scale Factor")
                .font(.subheadline)
            
            HStack {
                Slider(value: $velocityScalePercent, in: 25...200, step: 5)
                Text("\(Int(velocityScalePercent))%")
                    .monospacedDigit()
                    .frame(width: 50)
            }
            
            HStack {
                Button("50%") { velocityScalePercent = 50 }
                Button("75%") { velocityScalePercent = 75 }
                Button("100%") { velocityScalePercent = 100 }
                Button("125%") { velocityScalePercent = 125 }
                Button("150%") { velocityScalePercent = 150 }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var velocitySetParams: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fixed Velocity")
                .font(.subheadline)
            
            HStack {
                Slider(value: Binding(
                    get: { Double(velocitySetValue) },
                    set: { velocitySetValue = Int($0) }
                ), in: 1...127, step: 1)
                
                Text("\(velocitySetValue)")
                    .monospacedDigit()
                    .frame(width: 40)
            }
            
            HStack {
                Button("pp (32)") { velocitySetValue = 32 }
                Button("mp (64)") { velocitySetValue = 64 }
                Button("mf (80)") { velocitySetValue = 80 }
                Button("f (100)") { velocitySetValue = 100 }
                Button("ff (127)") { velocitySetValue = 127 }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var velocityRampParams: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start Velocity")
                .font(.subheadline)
            
            HStack {
                Slider(value: Binding(
                    get: { Double(velocityRampStart) },
                    set: { velocityRampStart = Int($0) }
                ), in: 1...127, step: 1)
                
                Text("\(velocityRampStart)")
                    .monospacedDigit()
                    .frame(width: 40)
            }
            
            Text("End Velocity")
                .font(.subheadline)
            
            HStack {
                Slider(value: Binding(
                    get: { Double(velocityRampEnd) },
                    set: { velocityRampEnd = Int($0) }
                ), in: 1...127, step: 1)
                
                Text("\(velocityRampEnd)")
                    .monospacedDigit()
                    .frame(width: 40)
            }
        }
    }
    
    private var timeStretchParams: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Scale")
                .font(.subheadline)
            
            HStack {
                Slider(value: $timeStretchPercent, in: 25...200, step: 5)
                Text("\(Int(timeStretchPercent))%")
                    .monospacedDigit()
                    .frame(width: 50)
            }
            
            HStack {
                Button("50%") { timeStretchPercent = 50 }
                Button("75%") { timeStretchPercent = 75 }
                Button("100%") { timeStretchPercent = 100 }
                Button("150%") { timeStretchPercent = 150 }
                Button("200%") { timeStretchPercent = 200 }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var noParamsNeeded: some View {
        VStack {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundColor(.green)
            Text("No parameters needed")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button("Apply") {
                applyTransform()
                isPresented = false
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Transform Logic
    
    private func applyTransform() {
        let oldNotes = region.notes
        let noteIds = selectedNotes.isEmpty ? Set(region.notes.map { $0.id }) : selectedNotes
        
        switch selectedOperation {
        case .transpose:
            applyTranspose(to: noteIds, semitones: transposeSemitones)
        case .quantize:
            applyQuantize(to: noteIds, resolution: quantizeResolution, strength: quantizeStrength / 100)
        case .humanize:
            applyHumanize(to: noteIds, timingMs: humanizeTimingAmount, velocityRange: Int(humanizeVelocityAmount))
        case .velocityScale:
            applyVelocityScale(to: noteIds, percent: velocityScalePercent / 100)
        case .velocitySet:
            applyVelocitySet(to: noteIds, value: UInt8(velocitySetValue))
        case .velocityRamp:
            applyVelocityRamp(to: noteIds, start: UInt8(velocityRampStart), end: UInt8(velocityRampEnd))
        case .timeStretch:
            applyTimeStretch(to: noteIds, percent: timeStretchPercent / 100)
        case .reverse:
            applyReverse(to: noteIds)
        case .legato:
            applyLegatoAll(to: noteIds)
        }
        
        // Register undo
        if let undoManager = undoManager {
            undoManager.registerUndo(withTarget: undoManager) { _ in
                self.region.notes = oldNotes
            }
            undoManager.setActionName(selectedOperation.rawValue)
        }
    }
    
    private func applyTranspose(to noteIds: Set<UUID>, semitones: Int) {
        for i in region.notes.indices {
            if noteIds.contains(region.notes[i].id) {
                let newPitch = Int(region.notes[i].pitch) + semitones
                region.notes[i].pitch = UInt8(clamping: newPitch)
            }
        }
    }
    
    private func applyQuantize(to noteIds: Set<UUID>, resolution: SnapResolution, strength: Double) {
        for i in region.notes.indices {
            if noteIds.contains(region.notes[i].id) {
                let original = region.notes[i].startTime
                let quantized = resolution.quantize(original)
                // Apply strength: lerp between original and quantized
                region.notes[i].startTime = original + (quantized - original) * strength
            }
        }
    }
    
    private func applyHumanize(to noteIds: Set<UUID>, timingMs: Double, velocityRange: Int) {
        for i in region.notes.indices {
            if noteIds.contains(region.notes[i].id) {
                // Add random timing variation (convert ms to beats at ~120 BPM)
                let timingBeats = (timingMs / 1000) * 2  // Rough conversion
                let timingOffset = Double.random(in: -timingBeats...timingBeats)
                region.notes[i].startTime = max(0, region.notes[i].startTime + timingOffset)
                
                // Add random velocity variation
                let velocityOffset = Int.random(in: -velocityRange...velocityRange)
                let newVelocity = Int(region.notes[i].velocity) + velocityOffset
                region.notes[i].velocity = UInt8(clamping: newVelocity)
            }
        }
    }
    
    private func applyVelocityScale(to noteIds: Set<UUID>, percent: Double) {
        for i in region.notes.indices {
            if noteIds.contains(region.notes[i].id) {
                let newVelocity = Double(region.notes[i].velocity) * percent
                region.notes[i].velocity = UInt8(clamping: Int(newVelocity))
            }
        }
    }
    
    private func applyVelocitySet(to noteIds: Set<UUID>, value: UInt8) {
        for i in region.notes.indices {
            if noteIds.contains(region.notes[i].id) {
                region.notes[i].velocity = value
            }
        }
    }
    
    private func applyVelocityRamp(to noteIds: Set<UUID>, start: UInt8, end: UInt8) {
        // Sort notes by start time
        let sortedNotes = region.notes.filter { noteIds.contains($0.id) }.sorted { $0.startTime < $1.startTime }
        guard sortedNotes.count > 1 else { return }
        
        for (index, note) in sortedNotes.enumerated() {
            let progress = Double(index) / Double(sortedNotes.count - 1)
            let velocity = UInt8(Double(start) + progress * Double(Int(end) - Int(start)))
            
            if let i = region.notes.firstIndex(where: { $0.id == note.id }) {
                region.notes[i].velocity = velocity
            }
        }
    }
    
    private func applyTimeStretch(to noteIds: Set<UUID>, percent: Double) {
        // Find the earliest note start time as anchor
        let relevantNotes = region.notes.filter { noteIds.contains($0.id) }
        guard let anchor = relevantNotes.map({ $0.startTime }).min() else { return }
        
        for i in region.notes.indices {
            if noteIds.contains(region.notes[i].id) {
                // Scale position relative to anchor
                let relativePosition = region.notes[i].startTime - anchor
                region.notes[i].startTime = anchor + relativePosition * percent
                
                // Scale duration
                region.notes[i].duration = region.notes[i].duration * percent
            }
        }
    }
    
    private func applyReverse(to noteIds: Set<UUID>) {
        let relevantNotes = region.notes.filter { noteIds.contains($0.id) }
        guard relevantNotes.count > 1 else { return }
        
        // Get time range
        let minTime = relevantNotes.map { $0.startTime }.min() ?? 0
        let maxTime = relevantNotes.map { $0.startTime + $0.duration }.max() ?? 0
        
        for i in region.notes.indices {
            if noteIds.contains(region.notes[i].id) {
                // Mirror the position around the center
                let noteEnd = region.notes[i].startTime + region.notes[i].duration
                let newStart = maxTime - noteEnd + minTime
                region.notes[i].startTime = max(0, newStart)
            }
        }
    }
    
    private func applyLegatoAll(to noteIds: Set<UUID>) {
        let sortedNotes = region.notes.filter { noteIds.contains($0.id) }.sorted { $0.startTime < $1.startTime }
        
        for i in 0..<sortedNotes.count - 1 {
            let currentNote = sortedNotes[i]
            let nextNote = sortedNotes[i + 1]
            
            // Extend current note to start of next
            if let index = region.notes.firstIndex(where: { $0.id == currentNote.id }) {
                let newDuration = nextNote.startTime - currentNote.startTime
                if newDuration > 0 {
                    region.notes[index].duration = newDuration
                }
            }
        }
    }
}
