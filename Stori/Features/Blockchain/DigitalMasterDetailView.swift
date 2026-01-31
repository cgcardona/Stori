//
//  DigitalMasterDetailView.swift
//  Stori
//
//  Created by TellUrStori on 12/9/25.
//

import SwiftUI
import AVFoundation

/// Detail view for a Digital Master showing full info and license management
struct DigitalMasterDetailView: View {
    let master: DigitalMasterItem
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateLicense: Bool = false
    @State private var selectedStem: MasterStemInfo?
    @State private var copiedTokenId: Bool = false
    @State private var copiedTxHash: Bool = false
    
    // License instances (fetched from indexer)
    @State private var licenseInstances: [LicenseInstance] = []
    @State private var isLoadingLicenses: Bool = false
    @State private var licensesError: String?
    
    // Audio playback
    @State private var audioPlayer: AVPlayer?
    @State private var playingStemId: UUID?
    @State private var isLoadingAudio: Bool = false
    @State private var isPlayingFullSong: Bool = false
    
    // Lightbox
    @State private var showingImageLightbox: Bool = false
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: master.createdAt)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Cover and basic info
                    coverSection
                    
                    // Description
                    if !master.description.isEmpty {
                        descriptionSection
                    }
                    
                    // STEMs
                    stemsSection
                    
                    // Owners
                    ownersSection
                    
                    // License Instances (placeholder for future)
                    licensesSection
                    
                    // Blockchain info
                    blockchainSection
                }
                .padding(24)
            }
            
            // Footer actions
            footerActions
        }
        .frame(width: 720, height: 820)
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $showingCreateLicense) {
            CreateLicenseView(master: master)
        }
        .overlay {
            // Image Lightbox
            if showingImageLightbox {
                imageLightbox
            }
        }
        .onAppear {
            loadLicenseInstances()
        }
        .onChange(of: showingCreateLicense) { _, isShowing in
            // Refresh licenses when the create sheet closes
            if !isShowing {
                loadLicenseInstances()
            }
        }
    }
    
    // MARK: - Image Lightbox
    
    private var imageLightbox: some View {
        ZStack {
            // Dark backdrop
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showingImageLightbox = false
                    }
                }
            
            VStack(spacing: 20) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingImageLightbox = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding()
                }
                
                Spacer()
                
                // Large image
                if let imageURL = master.imageURL {
                    AsyncImage(url: ipfsGatewayURL(for: imageURL)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.5), radius: 20)
                        case .failure:
                            VStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .font(.system(size: 60))
                                    .foregroundColor(.white.opacity(0.5))
                                Text("Failed to load image")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: 600, maxHeight: 600)
                }
                
                // Title
                Text(master.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(40)
        }
        .transition(.opacity)
    }
    
    // MARK: - Data Loading
    
    private func loadLicenseInstances() {
        isLoadingLicenses = true
        licensesError = nil
        
        Task {
            do {
                let instances = try await DigitalMasterService.shared.fetchLicenseInstancesByMaster(
                    masterId: master.tokenId
                )
                
                await MainActor.run {
                    licenseInstances = instances
                    isLoadingLicenses = false
                }
            } catch {
                await MainActor.run {
                    licensesError = error.localizedDescription
                    isLoadingLicenses = false
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("Digital Master")
                .font(.headline)
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
    
    // MARK: - Cover Section
    
    private var coverSection: some View {
        HStack(alignment: .top, spacing: 20) {
            // Cover image - load from IPFS if available (tappable for lightbox)
            ZStack {
                if let imageURL = master.imageURL {
                    // Convert IPFS URL to gateway URL and load
                    AsyncImage(url: ipfsGatewayURL(for: imageURL)) { phase in
                        switch phase {
                        case .empty:
                            gradientPlaceholder
                                .overlay(ProgressView().scaleEffect(0.8))
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            gradientPlaceholder
                        @unknown default:
                            gradientPlaceholder
                        }
                    }
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    gradientPlaceholder
                }
                
                // Hover overlay hint
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.001)) // Nearly invisible but captures taps
                    .overlay(
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .opacity(0)
                    )
            }
            .frame(width: 160, height: 160)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            .onTapGesture {
                if master.imageURL != nil {
                    showingImageLightbox = true
                }
            }
            .cursor(master.imageURL != nil ? .pointingHand : .arrow)
            
            // Info
            VStack(alignment: .leading, spacing: 12) {
                Text(master.title)
                    .font(.title)
                    .fontWeight(.bold)
                
                // Token ID with copy
                HStack(spacing: 8) {
                    Text("Token ID:")
                        .foregroundColor(.secondary)
                    Text(master.tokenId)
                        .monospaced()
                    
                    Button {
                        copyToClipboard(master.tokenId)
                        withAnimation { copiedTokenId = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { copiedTokenId = false }
                        }
                    } label: {
                        Image(systemName: copiedTokenId ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(copiedTokenId ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption)
                
                // Stats
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(master.stems.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("STEMs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(master.licenseCount)")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Licenses")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatBasisPoints(master.royaltyPercentage))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        Text("Royalty")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if master.totalRevenue > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(String(format: "%.2f", master.totalRevenue))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("TUS")
                                    .font(.caption)
                            }
                            .foregroundColor(.green)
                            Text("Revenue")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
                
                // Play Full Song button
                if master.masterAudioURI != nil {
                    Button {
                        toggleFullSongPlayback()
                    } label: {
                        HStack(spacing: 8) {
                            if isLoadingAudio && isPlayingFullSong {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: isPlayingFullSong ? "stop.fill" : "play.fill")
                            }
                            Text(isPlayingFullSong ? "Stop" : "Play Full Song")
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isPlayingFullSong ? Color.red.opacity(0.9) : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                
                // Created date
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text("Created \(formattedDate)")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Description Section
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            
            Text(master.description)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                )
        }
    }
    
    // MARK: - STEMs Section
    
    private var stemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STEMs")
                    .font(.headline)
                
                Text("(\(master.stems.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                ForEach(master.stems) { stem in
                    stemRow(stem)
                }
            }
        }
    }
    
    private func stemRow(_ stem: MasterStemInfo) -> some View {
        HStack(spacing: 12) {
            // Icon based on type
            ZStack {
                Circle()
                    .fill(stem.isMIDI ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: stem.isMIDI ? "pianokeys" : "waveform")
                    .font(.system(size: 14))
                    .foregroundColor(stem.isMIDI ? .blue : .green)
            }
            
            // Name and duration
            VStack(alignment: .leading, spacing: 2) {
                Text(stem.name)
                    .font(.system(size: 14, weight: .medium))
                
                Text(formatDuration(stem.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Type badge
            if stem.isMIDI {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                    Text("MIDI")
                }
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
            }
            
            // MIDI download indicator
            if stem.midiURI != nil {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
                    .help("MIDI file available for commercial license")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }
    
    // MARK: - Audio Playback
    
    private func toggleFullSongPlayback() {
        // If currently playing, stop it
        if isPlayingFullSong {
            stopPlayback()
            return
        }
        
        // Stop any current playback
        stopPlayback()
        
        guard let audioURI = master.masterAudioURI else { return }
        
        // Convert IPFS URI to gateway URL
        let urlString: String
        if audioURI.hasPrefix("ipfs://") {
            let hash = String(audioURI.dropFirst(7))
            urlString = "\(StoriEnvironment.ipfsGatewayURL)/ipfs/\(hash)"
        } else {
            urlString = audioURI
        }
        
        guard let url = URL(string: urlString) else { return }
        
        isLoadingAudio = true
        isPlayingFullSong = true
        
        // Create player and play
        let playerItem = AVPlayerItem(url: url)
        audioPlayer = AVPlayer(playerItem: playerItem)
        
        // Observe when ready to play
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            self.stopPlayback()
        }
        
        audioPlayer?.play()
        isLoadingAudio = false
    }
    
    private func stopPlayback() {
        audioPlayer?.pause()
        audioPlayer = nil
        playingStemId = nil
        isPlayingFullSong = false
        isLoadingAudio = false
    }
    
    // MARK: - Owners Section
    
    private var ownersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Owners & Shares")
                    .font(.headline)
                
                Spacer()
                
                Text("100%")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.green.opacity(0.1))
                    )
            }
            
            VStack(spacing: 8) {
                ForEach(master.owners) { owner in
                    ownerRow(owner)
                }
            }
        }
    }
    
    private func ownerRow(_ owner: MasterOwnerInfo) -> some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [colorFromAddress(owner.address), colorFromAddress(owner.address).opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(owner.address.dropFirst(2).prefix(2)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                )
            
            // Address
            Text(owner.address)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Share percentage
            Text(formatBasisPoints(owner.sharePercentage))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }
    
    // MARK: - Licenses Section
    
    private var licensesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("License Instances")
                    .font(.headline)
                
                if isLoadingLicenses {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                Spacer()
                
                Button {
                    showingCreateLicense = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create License")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.purple)
                }
                .buttonStyle(.plain)
            }
            
            if licenseInstances.isEmpty && !isLoadingLicenses {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No license instances yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Create license instances to monetize your Digital Master")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                .foregroundColor(.secondary.opacity(0.3))
                        )
                )
            } else if !licenseInstances.isEmpty {
                // License instances list
                VStack(spacing: 8) {
                    ForEach(licenseInstances) { instance in
                        licenseInstanceRow(instance)
                    }
                }
            }
            
            if let error = licensesError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Spacer()
                    
                    Button("Retry") {
                        loadLicenseInstances()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
    }
    
    private func licenseInstanceRow(_ instance: LicenseInstance) -> some View {
        HStack(spacing: 12) {
            // License type icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: instance.licenseType.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Image(systemName: instance.licenseType.systemIcon)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.licenseType.title)
                    .font(.system(size: 13, weight: .medium))
                
                HStack(spacing: 8) {
                    Text("\(instance.price, specifier: "%.3f") TUS")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    if instance.maxSupply > 0 {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("\(instance.totalMinted)/\(instance.maxSupply) minted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Unlimited")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Instance ID
            Text("#\(instance.instanceId.prefix(8))")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospaced()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }
    
    // MARK: - Blockchain Section
    
    private var blockchainSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blockchain Info")
                .font(.headline)
            
            VStack(spacing: 8) {
                infoRow(label: "Network", value: "Stori L1")
                infoRow(label: "Chain ID", value: "507")
                
                // Transaction hash with copy
                HStack {
                    Text("Transaction")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    Text(master.transactionHash)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Button {
                        copyToClipboard(master.transactionHash)
                        withAnimation { copiedTxHash = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { copiedTxHash = false }
                        }
                    } label: {
                        Image(systemName: copiedTxHash ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(copiedTxHash ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.system(size: 12))
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Footer Actions
    
    private var footerActions: some View {
        HStack(spacing: 16) {
            // View on explorer
            Button {
                // TODO: Open in explorer
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.square")
                    Text("View on Explorer")
                }
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Create License CTA
            Button {
                showingCreateLicense = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create License Instance")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(.windowBackgroundColor))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1),
            alignment: .top
        )
    }
    
    // MARK: - Helpers
    
    /// Gradient placeholder view for missing images
    private var gradientPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: gradientColors(for: master.title),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "waveform")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.white.opacity(0.3))
        }
    }
    
    /// Convert IPFS URI to gateway URL
    private func ipfsGatewayURL(for url: URL) -> URL {
        let urlString = url.absoluteString
        if urlString.hasPrefix("ipfs://") {
            let hash = String(urlString.dropFirst(7))
            return URL(string: "\(StoriEnvironment.ipfsGatewayURL)/ipfs/\(hash)")!
        }
        return url
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func gradientColors(for title: String) -> [Color] {
        let hash = abs(title.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 360) % 360) / 360.0
        
        return [
            Color(hue: hue1, saturation: 0.6, brightness: 0.7),
            Color(hue: hue2, saturation: 0.5, brightness: 0.5)
        ]
    }
    
    private func colorFromAddress(_ address: String) -> Color {
        let hash = abs(address.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.7)
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    /// Format basis points (10000 = 100%) to percentage string
    private func formatBasisPoints(_ basisPoints: Int) -> String {
        let percentage = Double(basisPoints) / 100.0
        if percentage == percentage.rounded() {
            return "\(Int(percentage))%"
        } else {
            return String(format: "%.1f%%", percentage)
        }
    }
}
