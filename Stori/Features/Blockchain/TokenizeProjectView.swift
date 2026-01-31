/**
 TokenizeProjectView.swift
 Stori
 
 Professional modal for tokenizing an entire project as a Digital Master (ERC-721) on the blockchain.
 
 The Digital Master represents ownership of the original creation. License instances (ERC-1155)
 for monetization (streaming, limited play, commercial, etc.) are created later in the Marketplace.
 
 Flow:
 1. User configures metadata (title, description, STEMs, artwork, royalties)
 2. Assets are uploaded to IPFS (images + audio)
 3. Metadata JSON is created and uploaded to IPFS
 4. Digital Master is minted on Stori L1 (ERC-721)
 5. User can then create license instances in the Marketplace
 */

import SwiftUI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

// MARK: - Environment Configuration

/// Environment-specific URLs for TellUrStori platform
/// - Development: http://localhost:3000
/// - Staging: https://staging.example.com
/// - Production: https://example.com
// StoriEnvironment is now in StoriEnvironment.swift

// MARK: - Signing Service Response Models

/// Response from the signing service after minting
private struct MintResponse: Codable {
    let success: Bool
    let tokenId: String?
    let transactionHash: String?
    let metadataURI: String?
    let error: String?
    let gatewayURLs: GatewayURLs?
}

private struct GatewayURLs: Codable {
    let metadata: String?
    let coverImage: String?
}

/// Request body for minting Digital Master
private struct MintRequest: Codable {
    let title: String
    let description: String
    let owners: [OwnerInfo]
    let royaltyPercentage: Int
    let stems: [STEMInfo]
    let coverImageData: String?
}

private struct OwnerInfo: Codable {
    let address: String
    let sharePercentage: Int
}

private struct STEMInfo: Codable {
    let name: String
    let duration: Double
    let audioData: String?
    let imageData: String?
}

// MARK: - Royalty Owner Model

/// Represents a single owner in the multi-owner royalty structure
struct RoyaltyOwner: Identifiable, Equatable {
    let id = UUID()
    var address: String
    var sharePercentage: Int // Basis points representation internally, but shown as percentage
    
    static func == (lhs: RoyaltyOwner, rhs: RoyaltyOwner) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Tokenize Project View

struct TokenizeProjectView: View {
    var projectManager: ProjectManager
    var blockchainClient: BlockchainClient
    var audioEngine: AudioEngine
    
    @State private var exportService = ProjectExportService()
    private let walletService = WalletService.shared
    @Environment(\.dismiss) private var dismiss
    
    // STEM selection state
    @State private var selectedSTEMIds: Set<UUID> = []
    
    // Multi-owner royalty state
    @State private var royaltyOwners: [RoyaltyOwner] = []
    @State private var royaltyPercentage: Double = 10.0 // Total royalty % on secondary sales
    
    // Project metadata
    @State private var projectTitle: String = ""
    @State private var projectDescription: String = ""
    @State private var projectImageURL: URL? = nil
    @State private var showImagePicker = false
    
    // Tokenization workflow state
    @State private var currentStep: TokenizationStep = .configure
    @State private var uploadProgress: Double = 0.0
    @State private var uploadStatusMessage: String = ""
    @State private var isTokenizing = false
    @State private var tokenizationComplete = false
    @State private var mintedTokenId: String?
    @State private var transactionHash: String?
    @State private var metadataIPFSURL: String?
    @State private var coverImageIPFSURL: String?
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Phase 5: Task management for cancellation
    @State private var tokenizationTask: Task<Void, Never>?
    @State private var totalUploadSizeBytes: Int64 = 0
    @State private var uploadedSizeBytes: Int64 = 0
    @State private var canRetry = false
    @State private var lastError: Error?
    
    private var project: AudioProject? { projectManager.currentProject }
    
    // Validation
    private var isValidConfiguration: Bool {
        !selectedSTEMIds.isEmpty &&
        !projectTitle.isEmpty &&
        !projectDescription.isEmpty &&
        !royaltyOwners.isEmpty &&
        totalOwnershipShares == 100 &&
        royaltyOwners.allSatisfy { isValidAddress($0.address) }
    }
    
    private var totalOwnershipShares: Int {
        royaltyOwners.reduce(0) { $0 + $1.sharePercentage }
    }
    
    private func isValidAddress(_ address: String) -> Bool {
        // Basic Ethereum address validation
        address.hasPrefix("0x") && address.count == 42
    }
    
    enum TokenizationStep {
        case configure
        case uploading
        case minting
        case success
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            tokenizeHeader
            
            Divider()
            
            // Main content based on current step
            switch currentStep {
            case .configure:
                configurationView
                
            case .uploading:
                uploadingView
                
            case .minting:
                mintingView
                
            case .success:
                successView
            }
        }
        .frame(width: 720, height: 860)
        .background(
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.windowBackgroundColor).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            setupInitialValues()
        }
        .alert("Error", isPresented: $showError) {
            if canRetry {
                Button("Retry") {
                    startTokenization()
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Configuration View
    
    private var configurationView: some View {
                ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Wallet Connection Status
                walletStatusBanner
                
                // Project Info Section
                        projectInfoSection
                
                // Project Image Section
                projectImageSection
                
                // STEM Selection Section
                        stemSelectionSection
                
                // Royalty Configuration Section
                        royaltySection
                        
                // Info Banner
                infoBanner
                
                // Tokenize Button
                tokenizeButton
            }
            .padding(24)
        }
    }
    
    // MARK: - Uploading View
    
    private var uploadingView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Upload animation
            ZStack {
                Circle()
                    .stroke(Color.purple.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: uploadProgress)
                    .stroke(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: uploadProgress)
                
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.to.line.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.purple)
                    
                    Text("\(Int(uploadProgress * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            
            VStack(spacing: 8) {
                Text("Uploading to IPFS")
                    .font(.system(size: 22, weight: .bold))
                
                Text(uploadStatusMessage)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Show upload size if available
                if totalUploadSizeBytes > 0 {
                    Text(formatUploadSize(uploaded: uploadedSizeBytes, total: totalUploadSizeBytes))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            // Cancel button
            Button {
                cancelTokenization()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                    Text("Cancel Upload")
                }
                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
    
    /// Format upload size as "X.X MB / Y.Y MB"
    private func formatUploadSize(uploaded: Int64, total: Int64) -> String {
        let uploadedMB = Double(uploaded) / (1024.0 * 1024.0)
        let totalMB = Double(total) / (1024.0 * 1024.0)
        return String(format: "%.1f MB / %.1f MB", uploadedMB, totalMB)
    }
    
    // MARK: - Minting View
    
    private var mintingView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Minting animation
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Color.purple.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                        .frame(width: CGFloat(100 + i * 30), height: CGFloat(100 + i * 30))
                        .scaleEffect(isTokenizing ? 1.2 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.2),
                            value: isTokenizing
                        )
                }
                
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .scaleEffect(isTokenizing ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isTokenizing)
            }
            .onAppear { isTokenizing = true }
            
            VStack(spacing: 8) {
                Text("Minting Digital Master")
                    .font(.system(size: 22, weight: .bold))
                
                Text("Creating your ERC-721 token on Stori L1...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
        }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Header
    
    private var tokenizeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    // Logo/Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create Digital Master")
                            .font(.system(size: 20, weight: .bold))
                
                if let project = project {
                    Text(project.name)
                                .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Step indicator
            if currentStep == .configure {
                HStack(spacing: 4) {
                    Text("ERC-721")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                }
            }
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Project Info Section
    
    private var projectInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Digital Master Details", icon: "doc.text.fill")
            
        VStack(alignment: .leading, spacing: 12) {
                // Title Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                    TextField("e.g., Midnight Dreams EP", text: $projectTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(projectTitle.isEmpty ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
            }
            
                // Description Field
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                Text("Description")
                            .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(projectDescription.count)/500")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(projectDescription.count > 500 ? .red : .secondary)
                    }
                
                TextEditor(text: $projectDescription)
                        .font(.system(size: 13))
                    .frame(height: 80)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(projectDescription.isEmpty ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                }
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Project Image Section
    
    private var projectImageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Cover Artwork", icon: "photo.artframe")
            
            HStack(spacing: 16) {
                // Image Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    if let imageURL = projectImageURL,
                       let image = NSImage(contentsOf: imageURL) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if let projectImage = projectManager.getProjectImageURL(),
                              let image = NSImage(contentsOf: projectImage) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            
                            Text("No artwork")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                )
                
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project Cover Image")
                        .font(.system(size: 13, weight: .medium))
                    
                    Text("This image will represent your Digital Master on the marketplace. Use high-quality artwork (recommended: 1400×1400px).")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Button {
                        selectProjectImage()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Choose Image")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func selectProjectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select cover artwork for your Digital Master"
        
        if panel.runModal() == .OK {
            projectImageURL = panel.url
        }
    }
    
    // MARK: - STEM Selection Section
    
    private var stemSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader(title: "STEMs to Include", icon: "waveform.path")
                
                Spacer()
                
                // Select All / None buttons
                HStack(spacing: 8) {
                    Button("All") {
                        if let tracks = project?.tracks {
                            selectedSTEMIds = Set(tracks.map { $0.id })
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.purple)
                    .buttonStyle(.plain)
                    
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Button("None") {
                        selectedSTEMIds.removeAll()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                }
                
                Text("\(selectedSTEMIds.count)/\(project?.tracks.count ?? 0)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selectedSTEMIds.isEmpty ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                    .foregroundColor(selectedSTEMIds.isEmpty ? .red : .green)
                    .cornerRadius(4)
            }
            
            if let tracks = project?.tracks {
                VStack(spacing: 6) {
                    ForEach(tracks) { track in
                        stemSelectionRow(track: track)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.slash")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("No tracks in project")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func stemSelectionRow(track: AudioTrack) -> some View {
        let isSelected = selectedSTEMIds.contains(track.id)
        
        return HStack(spacing: 12) {
            // Custom checkbox
            Button {
                    if isSelected {
                        selectedSTEMIds.remove(track.id)
                } else {
                    selectedSTEMIds.insert(track.id)
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.purple : Color.clear)
                        .frame(width: 20, height: 20)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.purple : Color.secondary.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Track thumbnail
            ZStack {
            if let trackImageURL = projectManager.getTrackImageURL(track.id),
               let trackImage = NSImage(contentsOf: trackImageURL) {
                Image(nsImage: trackImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [track.color.color.opacity(0.3), track.color.color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: track.iconName ?? "music.quarternote.3")
                                .font(.system(size: 16))
                            .foregroundColor(track.color.color)
                    )
            }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(track.color.color.opacity(0.5), lineWidth: 1)
            )
            
            // Track info
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                HStack(spacing: 6) {
                    Label("\(track.regions.count) region(s)", systemImage: "rectangle.split.3x1")
                    Text("•")
                    let tempo = projectManager.currentProject?.tempo ?? 120.0
                    let durationSeconds = (track.durationBeats ?? 0) * (60.0 / tempo)
                    Label(formatDuration(durationSeconds), systemImage: "clock")
                }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Has image indicator
            if projectManager.getTrackImageURL(track.id) != nil {
                Image(systemName: "photo.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green.opacity(0.7))
                    .help("Has artwork")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.purple.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedSTEMIds.remove(track.id)
            } else {
                selectedSTEMIds.insert(track.id)
            }
        }
    }
    
    // MARK: - Royalty Section (Multi-Owner)
    
    private var royaltySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader(title: "Ownership & Royalties", icon: "person.2.fill")
                
                Spacer()
                
                // Total shares indicator
                let total = totalOwnershipShares
                Text("\(total)%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(total == 100 ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .foregroundColor(total == 100 ? .green : .red)
                    .cornerRadius(6)
            }
            
            // Royalty Percentage Slider
                VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Secondary Sale Royalty")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                        
                    Text("\(Int(royaltyPercentage))%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.purple)
                    }
                
                HStack(spacing: 12) {
                    Text("0%")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Slider(value: $royaltyPercentage, in: 0...50, step: 1)
                        .accentColor(.purple)
                        
                    Text("50%")
                        .font(.system(size: 10))
                            .foregroundColor(.secondary)
            }
            
                Text("Earned on every resale of license instances")
                .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
        }
            .padding(12)
            .background(Color.purple.opacity(0.05))
        .cornerRadius(8)
            
            Divider()
                .padding(.vertical, 4)
            
            // Owner List Header
            HStack {
                Text("Owners & Shares")
                    .font(.system(size: 13, weight: .semibold))
            
                Text("(must total 100%)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    addNewOwner()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Owner")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.purple)
                }
                .buttonStyle(.plain)
            }
            
            // Owner Rows
            if royaltyOwners.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("Add at least one owner")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(royaltyOwners.enumerated()), id: \.element.id) { index, owner in
                        ownerRow(index: index, owner: owner)
            }
                }
            }
            
            // Validation message
            if totalOwnershipShares != 100 && !royaltyOwners.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Ownership shares must total exactly 100%")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func ownerRow(index: Int, owner: RoyaltyOwner) -> some View {
        OwnerRowView(
            owner: $royaltyOwners[index],
            index: index,
            canDelete: royaltyOwners.count > 1,
            isValidAddress: isValidAddress,
            onDelete: { royaltyOwners.remove(at: index) }
        )
    }
}

// MARK: - Owner Row View (Separate View to avoid binding flickering)

/// Separate view for each owner row to properly manage local editing state
/// This fixes the flickering issue where percentage values briefly revert before updating
private struct OwnerRowView: View {
    @Binding var owner: RoyaltyOwner
    let index: Int
    let canDelete: Bool
    let isValidAddress: (String) -> Bool
    let onDelete: () -> Void
    
    // Local state for editing to prevent flickering
    @State private var editingAddress: String = ""
    @State private var editingPercentage: String = ""
    @FocusState private var isAddressFocused: Bool
    @FocusState private var isPercentageFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Owner number badge
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.purple)
            }
            
            // Address field - uses local state to prevent flickering
            VStack(alignment: .leading, spacing: 2) {
                Text("Wallet Address")
                    .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                TextField("0x...", text: $editingAddress)
                    .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                    .focused($isAddressFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isValidAddress(editingAddress) ? Color.clear : Color.red.opacity(0.5),
                                lineWidth: 1
                            )
                    )
                    .onAppear {
                        editingAddress = owner.address
                    }
                    .onChange(of: isAddressFocused) { _, focused in
                        if !focused {
                            // Commit value when focus leaves
                            commitAddress()
                        }
                    }
                    .onSubmit {
                        // Commit value when Enter is pressed
                        commitAddress()
                    }
            }
            .frame(maxWidth: .infinity)
            
            // Percentage field - uses local state to prevent flickering
            VStack(alignment: .leading, spacing: 2) {
                Text("Share %")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    TextField("0", text: $editingPercentage)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .frame(width: 40)
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .focused($isPercentageFocused)
                        .onAppear {
                            editingPercentage = String(owner.sharePercentage)
                        }
                        .onChange(of: isPercentageFocused) { _, focused in
                            if !focused {
                                // Commit value when focus leaves
                                commitPercentage()
                            }
                        }
                        .onSubmit {
                            // Commit value when Enter is pressed
                            commitPercentage()
                        }
                    
                    Text("%")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            // Remove button
                        Button {
                onDelete()
                        } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
            .disabled(!canDelete)
            .opacity(canDelete ? 1.0 : 0.3)
        }
        .padding(10)
        .background(Color.gray.opacity(0.03))
        .cornerRadius(8)
                    }
    
    private func commitAddress() {
        // Trim whitespace and commit
        let trimmed = editingAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        owner.address = trimmed
        editingAddress = trimmed
    }
    
    private func commitPercentage() {
        if let value = Int(editingPercentage) {
            let clamped = min(100, max(0, value))
            owner.sharePercentage = clamped
            editingPercentage = String(clamped)
        } else {
            // Reset to current value if invalid
            editingPercentage = String(owner.sharePercentage)
        }
    }
}

// MARK: - TokenizeProjectView Helper Functions Extension

extension TokenizeProjectView {
    
    func addNewOwner() {
        // Calculate remaining percentage
        let remaining = 100 - totalOwnershipShares
        royaltyOwners.append(RoyaltyOwner(address: "", sharePercentage: max(0, remaining)))
    }
    
    // MARK: - Wallet Status Banner
    
    private var walletStatusBanner: some View {
        Group {
            if walletService.isUnlocked, let address = walletService.address {
                // Connected wallet banner
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wallet Connected")
                            .font(.system(size: 12, weight: .semibold))
                        
                        Text(truncateAddress(address))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(walletService.selectedNetwork.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
                .padding(14)
                .background(Color.green.opacity(0.08))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
            } else {
                // No wallet banner - prompt user
                HStack(spacing: 12) {
                    Image(systemName: "wallet.pass")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Wallet Connected")
                            .font(.system(size: 12, weight: .semibold))
                        
                        Text("Create or import a wallet in the Wallet tab to auto-fill your address")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(14)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        let prefix = address.prefix(8)
        let suffix = address.suffix(4)
        return "\(prefix)...\(suffix)"
    }
    
    // MARK: - Info Banner
    
    private var infoBanner: some View {
                HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("What happens next?")
                    .font(.system(size: 12, weight: .semibold))
                    
                Text("After minting your Digital Master, you can create license instances (Full Ownership, Streaming, Commercial, etc.) in the Marketplace to monetize your work.")
                    .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
                }
        .padding(14)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Tokenize Button
    
    private var tokenizeButton: some View {
        VStack(spacing: 12) {
            Button {
                startTokenization()
            } label: {
                HStack(spacing: 10) {
                    if isTokenizing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 16))
                    }
                    
                    Text(isTokenizing ? "Creating Digital Master..." : "Mint Digital Master")
                        .font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: isValidConfiguration ? [
                            Color(red: 0.6, green: 0.2, blue: 0.8),
                            Color(red: 0.9, green: 0.3, blue: 0.5)
                        ] : [Color.gray.opacity(0.5), Color.gray.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: isValidConfiguration ? Color.purple.opacity(0.3) : Color.clear, radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!isValidConfiguration || isTokenizing)
            
            // Validation hints
            if !isValidConfiguration {
                HStack(spacing: 16) {
                    if projectTitle.isEmpty {
                        validationHint(text: "Title required", icon: "doc.text")
                    }
                    if projectDescription.isEmpty {
                        validationHint(text: "Description required", icon: "text.alignleft")
                    }
                    if selectedSTEMIds.isEmpty {
                        validationHint(text: "Select STEMs", icon: "waveform")
                    }
                    if royaltyOwners.isEmpty || totalOwnershipShares != 100 {
                        validationHint(text: "Fix ownership", icon: "person.2")
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.orange)
            }
        }
    }
    
    private func validationHint(text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
    }
    
    // MARK: - Success View
    
    private var successView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Success animation
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Color.green.opacity(0.2 - Double(i) * 0.05), lineWidth: 2)
                        .frame(width: CGFloat(100 + i * 40), height: CGFloat(100 + i * 40))
                }
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.green.opacity(0.4), radius: 20)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("Digital Master Created!")
                    .font(.system(size: 26, weight: .bold))
            
                Text("Your project has been tokenized as an ERC-721 on Stori L1")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
            
            // Transaction details
            VStack(spacing: 16) {
                if let tokenId = mintedTokenId {
                    detailRow(label: "Token ID", value: "#\(tokenId)")
                }
                
                if let txHash = transactionHash {
                    detailRow(label: "Transaction", value: String(txHash.prefix(10)) + "..." + String(txHash.suffix(8)))
                }
                
                detailRow(label: "Network", value: "Stori L1 (Chain ID: 507)")
                detailRow(label: "Standard", value: "ERC-721")
            }
            .padding(20)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            
            Spacer()
            
            VStack(spacing: 12) {
            Button {
                    openMyDigitalMasters()
            } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                        Text("View in Marketplace")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
                
                // Show IPFS metadata link if available
                if let metadataURL = metadataIPFSURL {
                    Button {
                        if let url = URL(string: metadataURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("View Metadata on IPFS")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Section Header Helper
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.purple)
            
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
    }
    
    // MARK: - Helper Functions
    
    private func setupInitialValues() {
        // Auto-select all tracks
        if let tracks = project?.tracks {
            selectedSTEMIds = Set(tracks.map { $0.id })
        }
        
        // Set project title from project name
        if let project = project {
            projectTitle = project.name
        }
        
        // Set initial owner to connected wallet (if available)
        // Priority: 1) Local WalletService, 2) BlockchainClient wallet
        if let localWalletAddress = walletService.address {
            royaltyOwners = [RoyaltyOwner(address: localWalletAddress, sharePercentage: 100)]
        } else if blockchainClient.isConnected, let wallet = blockchainClient.currentWallet {
            royaltyOwners = [RoyaltyOwner(address: wallet.address, sharePercentage: 100)]
        } else {
            // Default to empty owner that user must fill in
            royaltyOwners = [RoyaltyOwner(address: "", sharePercentage: 100)]
        }
        
        // Try to load project image if available
        projectImageURL = projectManager.getProjectImageURL()
    }
    
    private func startTokenization() {
        guard isValidConfiguration else { return }
        
        // Reset state
        isTokenizing = true
        currentStep = .uploading
        uploadProgress = 0.0
        uploadStatusMessage = "Checking IPFS connection..."
        totalUploadSizeBytes = 0
        uploadedSizeBytes = 0
        canRetry = false
        lastError = nil
        
        // Store task for cancellation
        tokenizationTask = Task {
            // Phase 5: Check IPFS daemon is running first
            let ipfsReady = await checkIPFSHealth()
            if !ipfsReady {
            await MainActor.run {
                    isTokenizing = false
                    currentStep = .configure
                    errorMessage = "IPFS daemon is not running.\n\nPlease start IPFS with: ipfs daemon"
                    canRetry = true
                    showError = true
                }
                return
            }
            
            await performTokenization()
        }
    }
    
    /// Cancel the ongoing tokenization task
    private func cancelTokenization() {
        tokenizationTask?.cancel()
        tokenizationTask = nil
        
        isTokenizing = false
        currentStep = .configure
        uploadProgress = 0.0
        uploadStatusMessage = ""
        totalUploadSizeBytes = 0
        uploadedSizeBytes = 0
    }
    
    /// Check if IPFS daemon is running and accessible
    /// First tries the indexer health endpoint, then falls back to direct IPFS check
    private func checkIPFSHealth() async -> Bool {
        // Method 1: Try indexer's health endpoint (preferred for production)
        if await checkIndexerIPFSHealth() {
            return true
        }
        
        // Method 2: Check IPFS directly at port 5001 (for development)
        if await checkIPFSDirect() {
            return true
        }
        
        return false
    }
    
    /// Check IPFS via indexer service health endpoint
    private func checkIndexerIPFSHealth() async -> Bool {
        guard let url = URL(string: "\(StoriEnvironment.indexerGraphQLURL.replacingOccurrences(of: "/graphql", with: "/health"))") else {
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            // Parse response to check IPFS connection
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String,
               status == "healthy",
               let services = json["services"] as? [String: Any],
               let ipfsReady = services["ipfs"] as? Bool,
               ipfsReady {
                return true
            }
            
            return false
        } catch {
            return false
        }
    }
    
    /// Check IPFS directly at its API port (5001)
    private func checkIPFSDirect() async -> Bool {
        // IPFS API endpoint for version check
        guard let url = URL(string: "http://127.0.0.1:5001/api/v0/version") else {
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"  // IPFS API uses POST
            request.timeoutInterval = 3
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            // Parse response to verify IPFS is responding
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["Version"] != nil {
                return true
            }
            
            return false
        } catch {
            return false
        }
    }
    
    private func performTokenization() async {
        guard let project = project else { return }
        
        // Check for cancellation
        guard !Task.isCancelled else { return }
        
        // Step 1: Prepare request
        await MainActor.run {
            uploadStatusMessage = "Preparing Digital Master data..."
            uploadProgress = 0.05
        }
        
        // Step 1a: Read cover image if available
        var coverImageData: Data? = nil
        if let coverURL = getCoverImageURL() {
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                uploadStatusMessage = "Reading cover artwork..."
                uploadProgress = 0.08
            }
            
            coverImageData = try? Data(contentsOf: coverURL)
        }
        
        // Step 2: Export full project mix (single render for all tracks)
        await MainActor.run {
            uploadStatusMessage = "Rendering audio mix..."
            uploadProgress = 0.1
        }
        
        var masterAudioData: Data? = nil
        
        // Start a progress monitoring task
        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                // Map export service progress (0-1) to our range (0.1-0.35)
                let exportProgress = exportService.exportProgress
                uploadProgress = 0.1 + (exportProgress * 0.25)
                
                if exportProgress > 0.1 {
                    uploadStatusMessage = "Rendering audio... \(Int(exportProgress * 100))%"
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        do {
            masterAudioData = try await exportService.exportProjectMixToData(
                project: project,
                audioEngine: audioEngine
            )
        } catch {
        }
        
        progressTask.cancel()
        
        guard !Task.isCancelled else { return }
        
        // Step 3: Build stem metadata and export MIDI files (no audio bouncing per stem)
        await MainActor.run {
            uploadStatusMessage = "Processing track metadata..."
            uploadProgress = 0.4
        }
        
        let selectedTracks = selectedSTEMIds.compactMap { stemId in
            project.tracks.first(where: { $0.id == stemId })
        }
        
        // Filter out empty tracks (no content)
        let tracksWithContent = selectedTracks.filter { track in
            track.hasContent
        }
        
        var mintingStems: [DigitalMasterMintingService.MintingStem] = []
        
        for (index, track) in tracksWithContent.enumerated() {
            guard !Task.isCancelled else { return }
            
            let isMIDI = track.isMIDITrack
            var midiData: Data? = nil
            
            // Only export MIDI files for MIDI tracks (fast, no audio rendering)
            if isMIDI && !track.midiRegions.isEmpty {
                await MainActor.run {
                    uploadStatusMessage = "Exporting MIDI \(index + 1)/\(tracksWithContent.count): \(track.name)..."
                    uploadProgress = 0.4 + (0.1 * Double(index) / Double(max(tracksWithContent.count, 1)))
                }
                
                do {
                    midiData = try exportService.exportMIDIToData(
                        track: track,
                        project: project
                    )
                } catch {
                }
            }
            
            let tempo = projectManager.currentProject?.tempo ?? 120.0
            // Add stem metadata (no individual audio - full mix is used for playback)
            mintingStems.append(DigitalMasterMintingService.MintingStem(
                name: track.name,
                duration: (track.durationBeats ?? 0) * (60.0 / tempo),
                audioData: nil,  // No individual stem audio - use masterAudioURI for playback
                midiData: midiData,
                isMIDI: isMIDI
            ))
        }
        
        guard !Task.isCancelled else { return }
        
        // Check we have something to mint
        guard !mintingStems.isEmpty else {
            await MainActor.run {
                errorMessage = "No valid stems to tokenize. Make sure your tracks have audio or MIDI content."
                showError = true
                isTokenizing = false
            }
            return
        }
        
        // Check we have the master audio
        guard masterAudioData != nil else {
            await MainActor.run {
                errorMessage = "Failed to export project audio. Please try again."
                showError = true
                isTokenizing = false
            }
            return
        }
        
        await MainActor.run {
            uploadStatusMessage = "Uploading to IPFS..."
            uploadProgress = 0.5
        }
        
        // Step 4: Use wallet-based minting service
        do {
            // Check wallet is connected
            guard WalletService.shared.hasWallet, WalletService.shared.address != nil else {
                throw NSError(domain: "Wallet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please connect your wallet first"])
            }
            
            await MainActor.run {
                currentStep = .minting
            }
            
            // Convert owners to the format expected
            let mintingOwners: [(address: String, sharePercentage: Int)] = royaltyOwners.map { owner in
                (address: owner.address, sharePercentage: owner.sharePercentage)
            }
            
            // Call the wallet-based minting service
            let mintingService = DigitalMasterMintingService.shared
            
            let result = try await mintingService.mintDigitalMaster(
                title: projectTitle,
                description: projectDescription,
                owners: mintingOwners,
                royaltyPercentage: Int(royaltyPercentage),
                coverImageData: coverImageData,
                masterAudioData: masterAudioData,
                stems: mintingStems
            )
            
            // Success!
            await MainActor.run {
                isTokenizing = false
                mintedTokenId = result.tokenId
                transactionHash = result.transactionHash
                metadataIPFSURL = result.metadataGatewayURL
                coverImageIPFSURL = result.coverImageGatewayURL
                currentStep = .success
            }
            
        } catch {
            // Check if this was a cancellation
            if Task.isCancelled {
                return
            }
            
            // Determine error type for better messaging
            let userFriendlyError = getUserFriendlyError(error)
            
            await MainActor.run {
                isTokenizing = false
                currentStep = .configure
                lastError = error
                canRetry = true
                errorMessage = userFriendlyError
                showError = true
            }
        }
    }
    
    /// Convert errors to user-friendly messages
    private func getUserFriendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        
        // Network errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection.\n\nPlease check your network and try again."
            case NSURLErrorTimedOut:
                return "Upload timed out.\n\nThe files may be too large or the connection is slow. Try again or reduce file sizes."
            case NSURLErrorCannotConnectToHost:
                return "Cannot connect to services.\n\nMake sure the indexer and blockchain are running."
            default:
                return "Network error: \(error.localizedDescription)"
            }
        }
        
        // Wallet errors
        if nsError.domain == "Wallet" {
            return "Wallet error:\n\(nsError.localizedDescription)"
        }
        
        // Minting errors
        if let mintingError = error as? MintingError {
            return "Minting error:\n\(mintingError.localizedDescription)"
        }
        
        // IPFS errors
        if let ipfsError = error as? IPFSError {
            return "IPFS error:\n\(ipfsError.localizedDescription)"
        }
        
        return "Tokenization failed:\n\(error.localizedDescription)"
    }
    
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(round(duration))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    // MARK: - Image/Audio Data Helpers
    
    /// Read an image from URL and convert to base64 string for IPFS upload
    /// - Parameter url: The file URL of the image
    /// - Returns: Base64 encoded string of the image data, or nil if failed
    private func readImageAsBase64(from url: URL) -> String? {
        return readImageAsBase64WithSize(from: url)?.0
    }
    
    /// Read an image from URL and convert to base64 string for IPFS upload (with size)
    /// - Parameter url: The file URL of the image
    /// - Returns: Tuple of (base64 string, file size in bytes), or nil if failed
    private func readImageAsBase64WithSize(from url: URL) -> (String, Int64)? {
        do {
            // Read the image file
            let imageData = try Data(contentsOf: url)
            
            // Convert to base64
            let base64String = imageData.base64EncodedString()
            let fileSize = Int64(imageData.count)
            
            
            return (base64String, fileSize)
        } catch {
            return nil
        }
    }
    
    /// Get the cover image URL, preferring user-selected over project default
    private func getCoverImageURL() -> URL? {
        // First check if user selected a custom image
        if let customURL = projectImageURL {
            return customURL
        }
        // Fall back to project's default image
        return projectManager.getProjectImageURL()
    }
    
    /// Read an audio file from URL and convert to base64 string for IPFS upload
    /// - Parameter url: The file URL of the audio file
    /// - Returns: Base64 encoded string of the audio data, or nil if failed
    private func readAudioAsBase64(from url: URL) -> String? {
        return readAudioAsBase64WithSize(from: url)?.0
    }
    
    /// Read an audio file from URL and convert to base64 string for IPFS upload (with size)
    /// - Parameter url: The file URL of the audio file
    /// - Returns: Tuple of (base64 string, file size in bytes), or nil if failed
    private func readAudioAsBase64WithSize(from url: URL) -> (String, Int64)? {
        do {
            // Read the audio file
            let audioData = try Data(contentsOf: url)
            
            // Convert to base64
            let base64String = audioData.base64EncodedString()
            let fileSize = Int64(audioData.count)
            
            
            return (base64String, fileSize)
        } catch {
            return nil
        }
    }
    
    /// Format bytes as human-readable string (KB, MB, GB)
    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0
        
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.2f MB", mb)
        } else {
            return String(format: "%.1f KB", kb)
    }
    }
    
    /// Get the primary audio file URL for a track (from the first region)
    /// - Parameter track: The audio track
    /// - Returns: URL to the audio file, or nil if track has no regions
    private func getPrimaryAudioURL(for track: AudioTrack) -> URL? {
        // Get the first region's audio file URL
        guard let firstRegion = track.regions.first else {
            return nil
        }
        return firstRegion.audioFile.url
    }
    
    /// Opens the minted Digital Master in the Marketplace
    private func openMyDigitalMasters() {
        dismiss()
        // Open the marketplace - user can navigate to My Creations tab
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .openMarketplace, object: nil)
        }
    }
}

