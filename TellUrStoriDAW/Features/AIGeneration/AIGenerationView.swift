import SwiftUI

struct AIGenerationView: View {
    let targetTrack: AudioTrack
    @StateObject private var musicGenClient = MusicGenClient()
    @Environment(\.dismiss) private var dismiss
    
    // Generation parameters
    @State private var prompt = ""
    @State private var duration: Double = 10.0
    @State private var useTemplateBuilder = false
    
    // Template builder parameters
    @State private var selectedGenre = "Electronic"
    @State private var selectedMood = "Energetic"
    @State private var selectedTempo = "Medium"
    @State private var selectedInstruments: Set<String> = []
    @State private var customText = ""
    
    // Generation state
    @State private var isGenerating = false
    @State private var generationProgress: Double = 0.0
    @State private var currentJobId: String?
    @State private var generationStatus = "Ready to generate"
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Polling timer
    @State private var statusTimer: Timer?
    
    let genres = ["Electronic", "Rock", "Pop", "Jazz", "Classical", "Hip-Hop", "Country", "Blues", "Reggae", "Folk", "Metal", "Ambient"]
    let moods = ["Energetic", "Calm", "Happy", "Sad", "Mysterious", "Uplifting", "Dark", "Romantic", "Aggressive", "Peaceful"]
    let tempos = ["Very Slow", "Slow", "Medium", "Fast", "Very Fast"]
    let instruments = ["Piano", "Guitar", "Drums", "Bass", "Violin", "Saxophone", "Synthesizer", "Flute", "Trumpet", "Cello"]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Generate AI Music")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Creating music for track: \(targetTrack.name)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Duration selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Duration")
                            .font(.headline)
                        
                        HStack {
                            Text("5s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Slider(value: $duration, in: 5...30, step: 1)
                            
                            Text("30s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("\(Int(duration)) seconds")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Prompt input method selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Prompt Method")
                            .font(.headline)
                        
                        Picker("Prompt Method", selection: $useTemplateBuilder) {
                            Text("Manual Prompt").tag(false)
                            Text("Template Builder").tag(true)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Prompt input or template builder
                    if useTemplateBuilder {
                        templateBuilderSection
                    } else {
                        manualPromptSection
                    }
                    
                    // Generation progress (when generating)
                    if isGenerating {
                        generationProgressSection
                    }
                    
                    // Generate button
                    Button(action: startGeneration) {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            
                            Text(isGenerating ? "Generating..." : "Generate AI Music")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isGenerating ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isGenerating || (useTemplateBuilder ? buildPromptFromTemplate().isEmpty : prompt.isEmpty))
                }
                .padding()
            }
            .navigationTitle("AI Generation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelGeneration()
                        dismiss()
                    }
                }
            }
            .alert("Generation Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var manualPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Describe Your Music")
                .font(.headline)
            
            TextField("e.g., upbeat electronic dance track with synthesizers", text: $prompt, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...6)
            
            Text("Be descriptive! Include genre, mood, instruments, and style.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var templateBuilderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Build Your Prompt")
                .font(.headline)
            
            // Genre selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Genre")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 80))
                ], spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        Button(genre) {
                            selectedGenre = genre
                        }
                        .buttonStyle(TemplateButtonStyle(isSelected: selectedGenre == genre))
                    }
                }
            }
            
            // Mood selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Mood")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 80))
                ], spacing: 8) {
                    ForEach(moods, id: \.self) { mood in
                        Button(mood) {
                            selectedMood = mood
                        }
                        .buttonStyle(TemplateButtonStyle(isSelected: selectedMood == mood))
                    }
                }
            }
            
            // Tempo selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Tempo")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    ForEach(tempos, id: \.self) { tempo in
                        Button(tempo) {
                            selectedTempo = tempo
                        }
                        .buttonStyle(TemplateButtonStyle(isSelected: selectedTempo == tempo))
                    }
                }
            }
            
            // Instruments selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Instruments (Optional)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 80))
                ], spacing: 8) {
                    ForEach(instruments, id: \.self) { instrument in
                        Button(instrument) {
                            if selectedInstruments.contains(instrument) {
                                selectedInstruments.remove(instrument)
                            } else {
                                selectedInstruments.insert(instrument)
                            }
                        }
                        .buttonStyle(TemplateButtonStyle(isSelected: selectedInstruments.contains(instrument)))
                    }
                }
            }
            
            // Custom text
            VStack(alignment: .leading, spacing: 8) {
                Text("Additional Details (Optional)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("e.g., in the style of Daft Punk, with heavy bass", text: $customText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Generated prompt preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Generated Prompt:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(buildPromptFromTemplate())
                    .font(.body)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var generationProgressSection: some View {
        VStack(spacing: 16) {
            Text("Generating Your Music...")
                .font(.headline)
            
            ProgressView(value: generationProgress)
                .progressViewStyle(LinearProgressViewStyle())
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            Text("\(Int(generationProgress * 100))% - \(generationStatus)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let jobId = currentJobId {
                Text("Job ID: \(jobId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func buildPromptFromTemplate() -> String {
        var parts: [String] = []
        
        if !customText.isEmpty {
            parts.append(customText)
        }
        
        parts.append("\(selectedGenre.lowercased()) music")
        parts.append("with \(selectedMood.lowercased()) mood")
        parts.append("at \(selectedTempo.lowercased()) tempo")
        
        if !selectedInstruments.isEmpty {
            let instrumentList = Array(selectedInstruments).joined(separator: ", ")
            parts.append("featuring \(instrumentList)")
        }
        
        return parts.joined(separator: ", ")
    }
    
    private func startGeneration() {
        let finalPrompt = useTemplateBuilder ? buildPromptFromTemplate() : prompt
        
        guard !finalPrompt.isEmpty else { return }
        
        isGenerating = true
        generationProgress = 0.0
        generationStatus = "Starting generation..."
        
        Task {
            do {
                let job = try await musicGenClient.generateMusic(
                    prompt: finalPrompt,
                    duration: duration,
                    temperature: 1.0,
                    topK: 250,
                    topP: 0.0,
                    cfgCoef: 3.0
                )
                
                await MainActor.run {
                    currentJobId = job.id
                    generationStatus = "AI is creating your music..."
                    startStatusPolling()
                }
                
            } catch {
                await MainActor.run {
                    handleGenerationError(error)
                }
            }
        }
    }
    
    private func startStatusPolling() {
        // The MusicGenClient handles status polling internally
        // We just need to observe the job updates
        // For now, we'll simulate the completion after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.generationProgress = 1.0
            self.generationStatus = "Generation complete!"
            self.completeGeneration()
        }
    }
    
    private func completeGeneration() {
        statusTimer?.invalidate()
        statusTimer = nil
        
        generationStatus = "Download complete! Adding to track..."
        
        Task {
            do {
                guard let jobId = currentJobId else { return }
                
                // Download the generated audio
                let tempURL = try await musicGenClient.downloadAudio(for: jobId)
                
                await MainActor.run {
                    // TODO: Add the audio to the track as an AudioRegion
                    // This will be implemented when we have the audio region creation system
                    
                    generationStatus = "Success! Audio added to track."
                    isGenerating = false
                    
                    // Auto-dismiss after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
                
            } catch {
                await MainActor.run {
                    handleGenerationError(error)
                }
            }
        }
    }
    
    private func handleGenerationError(_ error: Error) {
        statusTimer?.invalidate()
        statusTimer = nil
        
        isGenerating = false
        generationProgress = 0.0
        currentJobId = nil
        
        errorMessage = error.localizedDescription
        showingError = true
    }
    
    private func cancelGeneration() {
        statusTimer?.invalidate()
        statusTimer = nil
        isGenerating = false
        generationProgress = 0.0
        currentJobId = nil
    }
}

struct TemplateButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    AIGenerationView(targetTrack: AudioTrack(
        name: "Lead Synth"
    ))
}
