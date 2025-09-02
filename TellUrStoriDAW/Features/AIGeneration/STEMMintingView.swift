//
//  STEMMintingView.swift
//  TellUrStoriDAW
//
//  🎵 TellUrStori V2 - STEM NFT Minting Interface
//
//  Allows users to mint their generated audio as STEM NFTs on the blockchain
//  with comprehensive metadata and IPFS integration.
//

import SwiftUI
import AVFoundation

struct STEMMintingView: View {
    let audioFile: AudioFile?
    let audioURL: URL?
    @ObservedObject var blockchainClient: BlockchainClient
    let onMintComplete: (PendingTransaction) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    // STEM metadata
    @State private var stemName: String = ""
    @State private var stemDescription: String = ""
    @State private var selectedSTEMType: STEMType = .other
    @State private var stemGenre: String = ""
    @State private var stemKey: String = ""
    @State private var stemBPM: String = ""
    @State private var stemSupply: String = "1000"
    
    // Minting state
    @State private var isMinting: Bool = false
    @State private var mintingProgress: Double = 0.0
    @State private var mintingStatus: String = "Ready to mint"
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    
    // Audio preview
    @State private var isPlaying: Bool = false
    @State private var audioPlayer: AVAudioPlayer?
    
    let genres = ["Electronic", "Rock", "Pop", "Jazz", "Classical", "Hip-Hop", "Country", "Blues", "Reggae", "Folk", "Metal", "Ambient", "Other"]
    let musicalKeys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B", "Cm", "C#m", "Dm", "D#m", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "A#m", "Bm"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Text("🎵 Mint STEM NFT")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .opacity(0) // For balance
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
                    // Audio preview section
                    if let audioFile = audioFile {
                        audioPreviewSection(audioFile)
                    }
                    
                    // STEM metadata form
                    stemMetadataSection
                    
                    // Blockchain info
                    blockchainInfoSection
                    
                    // Minting progress (when minting)
                    if isMinting {
                        mintingProgressSection
                    }
                    
                    // Mint button
                    Button(action: startMinting) {
                        HStack {
                            if isMinting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            
                            Text(isMinting ? "Minting STEM NFT..." : "Mint STEM NFT")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isMinting ? Color.gray : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isMinting || stemName.isEmpty || stemDescription.isEmpty || blockchainClient.currentWallet == nil)
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            setupInitialData()
        }
        .onDisappear {
            stopAudioPreview()
        }
        .alert("Minting Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func audioPreviewSection(_ audioFile: AudioFile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🎵 Audio Preview")
                .font(.headline)
            
            HStack {
                // Play/Pause button
                Button(action: toggleAudioPreview) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(audioFile.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Text("Duration: \(formatDuration(audioFile.duration))")
                        Text("•")
                        Text("Sample Rate: \(Int(audioFile.sampleRate)) Hz")
                        Text("•")
                        Text("Channels: \(audioFile.channels)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var stemMetadataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("📋 STEM Metadata")
                .font(.headline)
            
            // Name and Description
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name *")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("e.g., Energetic Electronic Beat", text: $stemName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description *")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("Describe your STEM...", text: $stemDescription, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...5)
                }
            }
            
            // STEM Type
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
            
            // Musical Properties
            VStack(alignment: .leading, spacing: 12) {
                Text("Musical Properties (Optional)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 16) {
                    // Genre
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Genre")
                            .font(.caption)
                        Picker("Genre", selection: $stemGenre) {
                            Text("Select Genre").tag("")
                            ForEach(genres, id: \.self) { genre in
                                Text(genre).tag(genre)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Key
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Key")
                            .font(.caption)
                        Picker("Key", selection: $stemKey) {
                            Text("Select Key").tag("")
                            ForEach(musicalKeys, id: \.self) { key in
                                Text(key).tag(key)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity)
                    }
                    
                    // BPM
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BPM")
                            .font(.caption)
                        TextField("120", text: $stemBPM)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 60)
                    }
                }
            }
            
            // Supply
            VStack(alignment: .leading, spacing: 4) {
                Text("Token Supply")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    TextField("1000", text: $stemSupply)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 100)
                    
                    Text("tokens will be minted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var blockchainInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("⛓️ Blockchain Information")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Network:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(blockchainClient.networkInfo?.networkName ?? "TellUrStori L1")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let wallet = blockchainClient.currentWallet {
                    HStack {
                        Text("Wallet:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(wallet.address.prefix(6))...\(wallet.address.suffix(4))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Wallet:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text("Not Connected")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        
                        Text("⚠️ You need to connect a wallet to mint STEMs. Please go to the Marketplace tab and connect your wallet first.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                }
                
                HStack {
                    Text("Estimated Gas:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("~0.05 AVAX")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(blockchainClient.currentWallet != nil ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var mintingProgressSection: some View {
        VStack(spacing: 16) {
            Text("Minting Your STEM NFT...")
                .font(.headline)
            
            ProgressView(value: mintingProgress)
                .progressViewStyle(LinearProgressViewStyle())
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            Text("\(Int(mintingProgress * 100))% - \(mintingStatus)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Functions
    
    private func setupInitialData() {
        if let audioFile = audioFile {
            // Auto-populate name if empty
            if stemName.isEmpty {
                stemName = audioFile.name
            }
            
            // Auto-populate description if empty
            if stemDescription.isEmpty {
                stemDescription = "AI-generated music STEM created with TellUrStori V2"
            }
        }
        
        // Setup audio player
        if let audioURL = audioURL {
            setupAudioPlayer(url: audioURL)
        }
    }
    
    private func setupAudioPlayer(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
        } catch {
            print("Failed to setup audio player: \(error)")
        }
    }
    
    private func toggleAudioPreview() {
        guard let player = audioPlayer else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            
            // Auto-stop when finished
            DispatchQueue.main.asyncAfter(deadline: .now() + player.duration) {
                if isPlaying {
                    isPlaying = false
                }
            }
        }
    }
    
    private func stopAudioPreview() {
        audioPlayer?.stop()
        isPlaying = false
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func startMinting() {
        guard let audioURL = audioURL,
              let audioFile = audioFile else {
            errorMessage = "Audio file not available"
            showingError = true
            return
        }
        
        // Check if wallet is connected
        guard blockchainClient.currentWallet != nil else {
            errorMessage = "No wallet connected"
            showingError = true
            return
        }
        
        isMinting = true
        mintingProgress = 0.0
        mintingStatus = "Preparing metadata..."
        
        Task {
            do {
                // Create STEM metadata
                let metadata = STEMMetadata(
                    name: stemName,
                    description: stemDescription,
                    stemType: selectedSTEMType,
                    duration: Int(audioFile.duration),
                    bpm: Int(stemBPM) ?? nil,
                    key: stemKey.isEmpty ? nil : stemKey,
                    genre: stemGenre.isEmpty ? nil : stemGenre,
                    format: audioFile.format.rawValue,
                    sampleRate: Int(audioFile.sampleRate),
                    bitDepth: audioFile.bitDepth,
                    channels: audioFile.channels
                )
                
                await MainActor.run {
                    mintingProgress = 0.2
                    mintingStatus = "Uploading to IPFS..."
                }
                
                // Read audio data
                let audioData = try Data(contentsOf: audioURL)
                
                await MainActor.run {
                    mintingProgress = 0.4
                    mintingStatus = "Creating blockchain transaction..."
                }
                
                // Mint STEM NFT
                let transaction = try await blockchainClient.mintSTEM(
                    audioData: audioData,
                    metadata: metadata,
                    supply: stemSupply
                )
                
                await MainActor.run {
                    mintingProgress = 1.0
                    mintingStatus = "STEM NFT minted successfully!"
                    isMinting = false
                    
                    // Call completion handler
                    onMintComplete(transaction)
                }
                
            } catch {
                await MainActor.run {
                    handleMintingError(error)
                }
            }
        }
    }
    
    private func handleMintingError(_ error: Error) {
        isMinting = false
        mintingProgress = 0.0
        mintingStatus = "Ready to mint"
        
        errorMessage = error.localizedDescription
        showingError = true
    }
}
