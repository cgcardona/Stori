import SwiftUI
import AVFoundation

struct AIGenerationView: View {
    let targetTrack: AudioTrack
    @ObservedObject var projectManager: ProjectManager
    @StateObject private var musicGenClient = MusicGenClient()
    @StateObject private var blockchainClient = BlockchainClient()
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
    
    // STEM minting state
    @State private var showingSTEMMintingSheet = false
    @State private var generatedAudioURL: URL?
    @State private var generatedAudioFile: AudioFile?
    @State private var mintAsSTEM = false
    @State private var stemName = ""
    @State private var stemDescription = ""
    @State private var selectedSTEMType: STEMType = .other
    @State private var stemSupply = "1000"
    @State private var isMintingSTEM = false
    
    // Polling timer
    @State private var statusTimer: Timer?
    
    let genres = ["Electronic", "Rock", "Pop", "Jazz", "Classical", "Hip-Hop", "Country", "Blues", "Reggae", "Folk", "Metal", "Ambient"]
    let moods = ["Energetic", "Calm", "Happy", "Sad", "Mysterious", "Uplifting", "Dark", "Romantic", "Aggressive", "Peaceful"]
    let tempos = ["Very Slow", "Slow", "Medium", "Fast", "Very Fast"]
    let instruments = ["Piano", "Guitar", "Drums", "Bass", "Violin", "Saxophone", "Synthesizer", "Flute", "Trumpet", "Cello"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Button("Cancel") {
                    cancelGeneration()
                    dismiss()
                }
                
                Spacer()
                
                Text("Generate AI Music")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Invisible button for balance
                Button("Cancel") {
                    cancelGeneration()
                    dismiss()
                }
                .opacity(0)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(.separatorColor)),
                alignment: .bottom
            )
            
            ScrollView {
                VStack(spacing: 24) {
                    // Track info and blockchain status
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Creating music for track: \(targetTrack.name)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Blockchain connection status
                        HStack {
                            Circle()
                                .fill(blockchainClient.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            
                            Text("Blockchain: \(blockchainClient.connectionStatus.description)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if blockchainClient.isConnected {
                                Text("✨ STEM minting available")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
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
                    
                    // STEM minting option (only if blockchain is connected)
                    if blockchainClient.isConnected {
                        stemMintingSection
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
        }
        .frame(minWidth: 600, minHeight: 500)
        .alert("Generation Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingSTEMMintingSheet) {
            STEMMintingView(
                audioFile: generatedAudioFile,
                audioURL: generatedAudioURL,
                blockchainClient: blockchainClient,
                onMintComplete: { transaction in
                    showingSTEMMintingSheet = false
                    // Show success message or navigate to transaction view
                }
            )
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
    
    private var stemMintingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            stemMintingHeader
            
            if mintAsSTEM {
                stemMintingContent
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var stemMintingHeader: some View {
        HStack {
            Text("🎵 STEM Tokenization")
                .font(.headline)
            
            Spacer()
            
            Toggle("Mint as STEM NFT", isOn: $mintAsSTEM)
                .toggleStyle(SwitchToggleStyle())
        }
    }
    
    private var stemMintingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your generated music will be minted as a STEM NFT on the blockchain after generation completes.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            stemTypeSelector
            stemDetailsSection
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var stemTypeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEM Type")
                .font(.subheadline)
                .fontWeight(.medium)
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100))
            ], spacing: 8) {
                ForEach(STEMType.allCases, id: \.self) { stemType in
                    Button(action: {
                        selectedSTEMType = stemType
                    }) {
                        HStack {
                            Text(stemType.emoji)
                            Text(stemType.displayName)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(TemplateButtonStyle(isSelected: selectedSTEMType == stemType))
                }
            }
        }
    }
    
    private var stemDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEM Details")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("Name and description will be auto-generated based on your prompt.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text("Supply:")
                    .font(.caption)
                TextField("1000", text: $stemSupply)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 80)
                Text("tokens")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
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
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                await self.pollJobStatus()
            }
        }
    }
    
    private func pollJobStatus() async {
        guard let jobId = currentJobId else { return }
        
        do {
            let status = try await musicGenClient.getJobStatus(jobId: jobId)
            
            await MainActor.run {
                self.generationProgress = status.progress
                
                switch status.status.lowercased() {
                case "pending":
                    self.generationStatus = "Queued for processing..."
                case "processing":
                    self.generationStatus = "AI is creating your music... \(Int(status.progress * 100))%"
                case "completed":
                    self.generationStatus = "Generation complete! Downloading..."
                    self.completeGeneration()
                case "failed":
                    self.handleGenerationError(NSError(domain: "MusicGen", code: -1, userInfo: [NSLocalizedDescriptionKey: status.errorMessage ?? "Generation failed"]))
                default:
                    self.generationStatus = "Processing... \(Int(status.progress * 100))%"
                }
            }
        } catch {
            await MainActor.run {
                self.handleGenerationError(error)
            }
        }
    }
    
    private func completeGeneration() {
        statusTimer?.invalidate()
        statusTimer = nil
        
        generationStatus = "Downloading audio file..."
        
        Task {
            do {
                guard let jobId = currentJobId else { return }
                
                // Download the generated audio
                let tempURL = try await musicGenClient.downloadAudio(for: jobId)
                
                await MainActor.run {
                    // Create AudioFile from downloaded audio
                    let audioFile = self.createAudioRegionFromFile(tempURL)
                    
                    if mintAsSTEM && blockchainClient.isConnected {
                        // Store for STEM minting
                        generatedAudioURL = tempURL
                        generatedAudioFile = audioFile
                        
                        // Auto-populate STEM metadata
                        let finalPrompt = useTemplateBuilder ? buildPromptFromTemplate() : prompt
                        stemName = "AI Generated - \(selectedGenre) \(selectedMood)"
                        stemDescription = "Generated with prompt: \(finalPrompt)"
                        
                        generationStatus = "Generation complete! Ready to mint STEM NFT."
                        isGenerating = false
                        generationProgress = 1.0
                        
                        // Show STEM minting sheet
                        showingSTEMMintingSheet = true
                    } else {
                        generationStatus = "Success! Audio added to track."
                        isGenerating = false
                        generationProgress = 1.0
                        
                        print("🎵 Generated audio saved to: \(tempURL)")
                        
                        // Auto-dismiss after showing success
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            dismiss()
                        }
                    }
                }
                
            } catch {
                await MainActor.run {
                    // If download fails, it might not be ready yet - continue polling
                    print("⚠️ Download not ready yet, continuing to poll...")
                    generationStatus = "Still processing... \(Int(generationProgress * 100))%"
                    
                    // Restart polling if download fails (file might not be ready)
                    if !isGenerating {
                        isGenerating = true
                        startStatusPolling()
                    }
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
    
    private func createAudioRegionFromFile(_ fileURL: URL) -> AudioFile? {
        do {
            // Get audio file information using AVAudioFile
            let audioFile = try AVAudioFile(forReading: fileURL)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            let sampleRate = audioFile.fileFormat.sampleRate
            let channels = Int(audioFile.fileFormat.channelCount)
            
            // Get file size
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0
            
            // Create AudioFile model
            let audioFileModel = AudioFile(
                name: "AI Generated - \(selectedGenre) \(selectedMood)",
                url: fileURL,
                duration: duration,
                sampleRate: sampleRate,
                channels: channels,
                bitDepth: 16, // WAV files from MusicGen are typically 16-bit
                fileSize: fileSize,
                format: .wav
            )
            
            // Create AudioRegion
            let audioRegion = AudioRegion(
                audioFile: audioFileModel,
                startTime: 0, // Place at beginning of track
                duration: duration
            )
            
            // Add region to track via project manager
            var updatedTrack = targetTrack
            updatedTrack.addRegion(audioRegion)
            projectManager.updateTrack(updatedTrack)
            
            print("✅ Added audio region to track: \(audioFileModel.name)")
            return audioFileModel
            
        } catch {
            print("❌ Failed to create audio region: \(error)")
            errorMessage = "Failed to add audio to track: \(error.localizedDescription)"
            showingError = true
            return nil
        }
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
