//
//  BrowseLicensesView.swift
//  Stori
//
//  Created by TellUrStori on 12/10/25.
//

import SwiftUI
import AVFoundation

/// Browse available License Instances for purchase
struct BrowseLicensesView: View {
    private let walletManager = WalletManager.shared
    
    // State
    @State private var licenseInstances: [AvailableLicenseInstance] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @State private var selectedLicenseType: LicenseType? = nil
    @State private var sortOption: LicenseSortOption = .newest
    
    // Purchase flow
    @State private var selectedInstance: AvailableLicenseInstance?
    
    // Audio preview
    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentlyPlayingId: String?
    
    private var filteredInstances: [AvailableLicenseInstance] {
        var result = licenseInstances
        
        // Filter by license type
        if let type = selectedLicenseType {
            result = result.filter { $0.licenseType == type }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artistName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Sort
        switch sortOption {
        case .newest:
            result.sort { $0.createdAt > $1.createdAt }
        case .priceLowToHigh:
            result.sort { $0.price < $1.price }
        case .priceHighToLow:
            result.sort { $0.price > $1.price }
        case .mostPopular:
            result.sort { $0.totalMinted > $1.totalMinted }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filters Bar
            filtersBar
            
            Divider()
            
            // Content
            if isLoading {
                loadingView
            } else if licenseInstances.isEmpty {
                emptyStateView
            } else if filteredInstances.isEmpty {
                noResultsView
            } else {
                contentView
            }
        }
        .onAppear {
            loadLicenseInstances()
        }
        .sheet(item: $selectedInstance) { instance in
            PurchaseLicenseSheet(instance: instance) {
                // On successful purchase, refresh list
                loadLicenseInstances()
            }
        }
    }
    
    // MARK: - Filters Bar
    
    private var filtersBar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search licenses...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
            .frame(maxWidth: 250)
            
            Spacer()
            
            // License Type Filter
            Menu {
                Button {
                    selectedLicenseType = nil
                } label: {
                    HStack {
                        Text("All Types")
                        if selectedLicenseType == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Divider()
                
                ForEach(LicenseType.allCases, id: \.self) { type in
                    Button {
                        selectedLicenseType = type
                    } label: {
                        HStack {
                            Image(systemName: type.systemIcon)
                            Text(type.title)
                            if selectedLicenseType == type {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedLicenseType?.systemIcon ?? "line.3.horizontal.decrease.circle")
                    Text(selectedLicenseType?.title ?? "All Types")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedLicenseType != nil ? Color.accentColor.opacity(0.2) : Color(.controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)
            
            // Sort
            Menu {
                ForEach(LicenseSortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                    } label: {
                        HStack {
                            Image(systemName: option.icon)
                            Text(option.rawValue)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: sortOption.icon)
                    Text(sortOption.rawValue)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)
            
            // Refresh
            Button {
                loadLicenseInstances()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(16)
    }
    
    // MARK: - Content
    
    private var contentView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 20)
                ],
                spacing: 20
            ) {
                ForEach(Array(filteredInstances.enumerated()), id: \.element.id) { index, instance in
                    LicenseInstanceCard(
                        instance: instance,
                        isPlaying: currentlyPlayingId == instance.id,
                        onPlayPreview: {
                            playPreview(for: instance)
                        },
                        onTap: {
                            HapticFeedback.selection()
                            selectedInstance = instance
                        }
                    )
                    .staggeredAppear(index: index, total: filteredInstances.count)
                }
            }
            .padding(20)
        }
    }
    
    private var loadingView: some View {
        ScrollView {
            SkeletonGrid(columns: 5, count: 10)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No License Instances Available")
                .font(.headline)
            
            Text("License instances will appear here when creators list them for sale")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No matches found")
                .font(.headline)
            
            Button("Clear Filters") {
                searchText = ""
                selectedLicenseType = nil
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Data Loading
    
    private func loadLicenseInstances() {
        isLoading = true
        errorMessage = nil
        
        Task {
            await fetchLicenseInstances()
        }
    }
    
    private func playPreview(for instance: AvailableLicenseInstance) {
        // If already playing this one, stop it
        if currentlyPlayingId == instance.id {
            audioPlayer?.stop()
            audioPlayer = nil
            currentlyPlayingId = nil
            return
        }
        
        // Stop any current playback
        audioPlayer?.stop()
        audioPlayer = nil
        
        guard let audioURI = instance.previewAudioURI else { return }
        
        // Convert IPFS URI to gateway URL
        let urlString: String
        if audioURI.hasPrefix("ipfs://") {
            let cid = String(audioURI.dropFirst(7))
            urlString = "http://127.0.0.1:8080/ipfs/\(cid)"
        } else {
            urlString = audioURI
        }
        
        guard let url = URL(string: urlString) else { return }
        
        // Download and play
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    do {
                        audioPlayer = try AVAudioPlayer(data: data)
                        audioPlayer?.prepareToPlay()
                        audioPlayer?.play()
                        currentlyPlayingId = instance.id
                        
                        // Auto-stop after playback ends (simple approach)
                        DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 30)) {
                            if currentlyPlayingId == instance.id {
                                currentlyPlayingId = nil
                            }
                        }
                    } catch {
                    }
                }
            } catch {
            }
        }
    }
    
    private func fetchLicenseInstances() async {
        do {
            // Fetch real license instances from the indexer
            let userAddress = await MainActor.run { WalletService.shared.address ?? "" }
            let fetchedLicenses = try await DigitalMasterService.shared.fetchAllLicenseInstances(userAddress: userAddress)
            
            // Convert to AvailableLicenseInstance format
            let instances = fetchedLicenses.map { license in
                AvailableLicenseInstance(
                    id: license.id,
                    instanceId: license.instanceId,
                    masterId: license.masterId,
                    title: license.masterTitle,
                    artistName: license.masterArtist,
                    imageURI: license.masterImageURI,
                    licenseType: license.licenseType,
                    price: license.price,
                    maxSupply: license.maxSupply,
                    totalMinted: license.totalMinted,
                    remainingSupply: license.remainingSupply,
                    createdAt: license.createdAt,
                    previewAudioURI: license.masterPreviewAudioURI,
                    isOwnedByCurrentUser: license.isOwnedByCurrentUser
                )
            }
            
            await MainActor.run {
                licenseInstances = instances
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Available License Instance Model

struct AvailableLicenseInstance: Identifiable {
    let id: String
    let instanceId: String
    let masterId: String
    let title: String
    let artistName: String
    let description: String
    let imageURL: URL?
    let imageURI: String?
    let licenseType: LicenseType
    let price: Double
    let maxSupply: Int?
    let totalMinted: Int
    let remainingSupplyValue: Int?
    let playsPerInstance: Int?
    let durationInDays: Int?
    let isTransferable: Bool
    let createdAt: Date
    let creatorAddress: String
    let previewAudioURI: String?
    let isOwnedByCurrentUser: Bool
    
    // Convenience initializer for indexer data
    init(
        id: String,
        instanceId: String,
        masterId: String,
        title: String,
        artistName: String,
        imageURI: String?,
        licenseType: LicenseType,
        price: Double,
        maxSupply: Int,
        totalMinted: Int,
        remainingSupply: Int,
        createdAt: Date,
        previewAudioURI: String? = nil,
        isOwnedByCurrentUser: Bool = false
    ) {
        self.id = id
        self.instanceId = instanceId
        self.masterId = masterId
        self.title = title
        self.artistName = artistName
        self.description = ""
        self.imageURL = nil
        self.imageURI = imageURI
        self.licenseType = licenseType
        self.price = price
        self.maxSupply = maxSupply
        self.totalMinted = totalMinted
        self.remainingSupplyValue = remainingSupply
        self.playsPerInstance = nil
        self.durationInDays = nil
        self.isTransferable = true
        self.createdAt = createdAt
        self.creatorAddress = ""
        self.previewAudioURI = previewAudioURI
        self.isOwnedByCurrentUser = isOwnedByCurrentUser
    }
    
    // Full initializer for mock data
    init(
        id: String,
        instanceId: String,
        masterId: String,
        title: String,
        artistName: String,
        description: String,
        imageURL: URL?,
        licenseType: LicenseType,
        price: Double,
        maxSupply: Int?,
        totalMinted: Int,
        playsPerInstance: Int?,
        durationInDays: Int?,
        isTransferable: Bool,
        createdAt: Date,
        creatorAddress: String,
        previewAudioURI: String? = nil,
        isOwnedByCurrentUser: Bool = false
    ) {
        self.id = id
        self.instanceId = instanceId
        self.masterId = masterId
        self.title = title
        self.artistName = artistName
        self.description = description
        self.imageURL = imageURL
        self.imageURI = nil
        self.licenseType = licenseType
        self.price = price
        self.maxSupply = maxSupply
        self.totalMinted = totalMinted
        self.remainingSupplyValue = maxSupply.map { $0 - totalMinted }
        self.playsPerInstance = playsPerInstance
        self.durationInDays = durationInDays
        self.isTransferable = isTransferable
        self.createdAt = createdAt
        self.creatorAddress = creatorAddress
        self.previewAudioURI = previewAudioURI
        self.isOwnedByCurrentUser = isOwnedByCurrentUser
    }
    
    var remainingSupply: Int? {
        remainingSupplyValue ?? maxSupply.map { $0 - totalMinted }
    }
    
    var isUnlimited: Bool {
        maxSupply == nil || maxSupply == 0
    }
    
    var availabilityText: String {
        if isUnlimited {
            return "Unlimited"
        } else if let remaining = remainingSupply {
            return "\(remaining) left"
        }
        return "Available"
    }
    
    /// Get the image URL, converting IPFS URI if needed
    var resolvedImageURL: URL? {
        if let url = imageURL {
            return url
        }
        guard let uri = imageURI, !uri.isEmpty else { return nil }
        if uri.hasPrefix("ipfs://") {
            let cid = String(uri.dropFirst(7))
            return URL(string: "http://127.0.0.1:8080/ipfs/\(cid)")
        }
        return URL(string: uri)
    }
    
    // Mock data
    static let mockData: [AvailableLicenseInstance] = [
        AvailableLicenseInstance(
            id: "ali-1",
            instanceId: "1",
            masterId: "1",
            title: "Electric Soul",
            artistName: "TellUrStori",
            description: "Full ownership of this electronic masterpiece",
            imageURL: nil,
            licenseType: .fullOwnership,
            price: 2.5,
            maxSupply: 100,
            totalMinted: 12,
            playsPerInstance: nil,
            durationInDays: nil,
            isTransferable: true,
            createdAt: Date().addingTimeInterval(-86400 * 2),
            creatorAddress: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
        ),
        AvailableLicenseInstance(
            id: "ali-2",
            instanceId: "2",
            masterId: "2",
            title: "Midnight Groove",
            artistName: "NightOwl",
            description: "Stream anywhere, anytime",
            imageURL: nil,
            licenseType: .streaming,
            price: 0.1,
            maxSupply: nil,
            totalMinted: 245,
            playsPerInstance: nil,
            durationInDays: nil,
            isTransferable: false,
            createdAt: Date().addingTimeInterval(-86400 * 5),
            creatorAddress: "0x1234567890abcdef1234567890abcdef12345678"
        ),
        AvailableLicenseInstance(
            id: "ali-3",
            instanceId: "3",
            masterId: "3",
            title: "Sunset Drive",
            artistName: "Coastal",
            description: "Experience 10 perfect plays",
            imageURL: nil,
            licenseType: .limitedPlay,
            price: 0.25,
            maxSupply: 500,
            totalMinted: 89,
            playsPerInstance: 10,
            durationInDays: nil,
            isTransferable: false,
            createdAt: Date().addingTimeInterval(-86400 * 1),
            creatorAddress: "0xabcdef1234567890abcdef1234567890abcdef12"
        ),
        AvailableLicenseInstance(
            id: "ali-4",
            instanceId: "4",
            masterId: "4",
            title: "Urban Beats",
            artistName: "CitySound",
            description: "30 days of unlimited listening",
            imageURL: nil,
            licenseType: .timeLimited,
            price: 0.5,
            maxSupply: 200,
            totalMinted: 45,
            playsPerInstance: nil,
            durationInDays: 30,
            isTransferable: false,
            createdAt: Date().addingTimeInterval(-86400 * 3),
            creatorAddress: "0x9876543210fedcba9876543210fedcba98765432"
        ),
        AvailableLicenseInstance(
            id: "ali-5",
            instanceId: "5",
            masterId: "5",
            title: "Film Score Suite",
            artistName: "Orchestra Pro",
            description: "Full commercial rights for your projects",
            imageURL: nil,
            licenseType: .commercialLicense,
            price: 25.0,
            maxSupply: 10,
            totalMinted: 3,
            playsPerInstance: nil,
            durationInDays: nil,
            isTransferable: true,
            createdAt: Date().addingTimeInterval(-86400 * 7),
            creatorAddress: "0xfedcba9876543210fedcba9876543210fedcba98"
        )
    ]
}

// MARK: - License Sort Option

enum LicenseSortOption: String, CaseIterable {
    case newest = "Newest"
    case priceLowToHigh = "Price: Low to High"
    case priceHighToLow = "Price: High to Low"
    case mostPopular = "Most Popular"
    
    var icon: String {
        switch self {
        case .newest: return "clock"
        case .priceLowToHigh: return "arrow.up"
        case .priceHighToLow: return "arrow.down"
        case .mostPopular: return "flame"
        }
    }
}

// MARK: - License Instance Card

struct LicenseInstanceCard: View {
    let instance: AvailableLicenseInstance
    let isPlaying: Bool
    let onTap: () -> Void
    let onPlayPreview: (() -> Void)?
    
    @State private var isHovering: Bool = false
    @State private var isPlayButtonHovering: Bool = false
    
    init(instance: AvailableLicenseInstance, isPlaying: Bool = false, onPlayPreview: (() -> Void)? = nil, onTap: @escaping () -> Void) {
        self.instance = instance
        self.isPlaying = isPlaying
        self.onPlayPreview = onPlayPreview
        self.onTap = onTap
    }
    
    var body: some View {
        cardContent
            .contentShape(Rectangle())
            .onTapGesture {
                // Only trigger tap if not hovering over play button
                if !isPlayButtonHovering {
                    onTap()
                }
            }
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
    
    private var cardContent: some View {
        VStack(spacing: 0) {
            // Cover
            ZStack {
                // IPFS Image or Gradient Cover
                if let imageURL = instance.resolvedImageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            gradientCover
                        @unknown default:
                            gradientCover
                        }
                    }
                } else {
                    gradientCover
                }
                
                // Overlays
                VStack {
                    HStack {
                        // Owner badge (top left)
                        if instance.isOwnedByCurrentUser {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 9))
                                Text("You own this")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.green))
                            .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        // License Badge (top right)
                        HStack(spacing: 4) {
                            Image(systemName: instance.licenseType.systemIcon)
                                .font(.system(size: 9))
                            Text(instance.licenseType.title)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .foregroundColor(.white)
                    }
                    .padding(8)
                    
                    Spacer()
                    
                    // Play button (center, on hover or playing)
                    if (isHovering || isPlaying) && instance.previewAudioURI != nil {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        .onHover { hovering in
                            isPlayButtonHovering = hovering
                        }
                        .onTapGesture {
                            onPlayPreview?()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            // Info
            VStack(alignment: .leading, spacing: 8) {
                Text(instance.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                Text(instance.artistName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Price and Availability
                HStack {
                    Text("\(instance.price, specifier: "%.2f") TUS")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    Text(instance.availabilityText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                // License Details
                if instance.licenseType == .limitedPlay, let plays = instance.playsPerInstance {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 10))
                        Text("\(plays) plays")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                }
                
                if instance.licenseType == .timeLimited, let days = instance.durationInDays {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text("\(days) days")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                }
                
                // Buy Button or Ownership indicator
                if instance.isOwnedByCurrentUser {
                    // User owns this Digital Master
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text("You own this")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(8)
                } else {
                    // Buy button (visual only - whole card is clickable)
                    HStack {
                        Image(systemName: "cart.badge.plus")
                        Text("Buy Now")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: instance.licenseType.gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.controlBackgroundColor))
                .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 12 : 6, y: isHovering ? 6 : 3)
        )
    }
    
    private var gradientCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: instance.licenseType.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: instance.licenseType.systemIcon)
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.25))
        }
    }
}

// MARK: - Purchase License Sheet (Placeholder)

struct PurchaseLicenseSheet: View {
    let instance: AvailableLicenseInstance
    let onPurchaseComplete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    private let walletManager = WalletManager.shared
    @State private var isPurchasing: Bool = false
    @State private var purchaseComplete: Bool = false
    @State private var errorMessage: String?
    @State private var transactionHash: String?
    @State private var totalPricePaid: String?
    
    // Digital Master details (for STEMs)
    @State private var digitalMaster: DigitalMasterItem?
    @State private var isLoadingMaster: Bool = true
    
    // Audio playback for preview
    @State private var audioPlayer: AVPlayer?
    @State private var isPlayingPreview: Bool = false
    @State private var isLoadingAudio: Bool = false
    
    // Image lightbox
    @State private var showingImageLightbox: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            if purchaseComplete {
                successView
            } else {
                purchaseFormView
                purchaseButtonSection
            }
        }
        .frame(width: 550, height: 750)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            loadDigitalMaster()
        }
        .onDisappear {
            stopPlayback()
        }
    }
    
    // MARK: - Load Digital Master
    
    private func loadDigitalMaster() {
        isLoadingMaster = true
        
        Task {
            do {
                let master = try await DigitalMasterService.shared.fetchDigitalMasterById(tokenId: instance.masterId)
                await MainActor.run {
                    digitalMaster = master
                    isLoadingMaster = false
                }
            } catch {
                await MainActor.run {
                    isLoadingMaster = false
                }
            }
        }
    }
    
    // MARK: - Audio Playback
    
    /// Get the preview audio URI - prioritize masterAudioURI from digital master
    private var previewAudioURI: String? {
        digitalMaster?.masterAudioURI ?? instance.previewAudioURI
    }
    
    private func togglePreviewPlayback() {
        // If currently playing, stop
        if isPlayingPreview {
            stopPlayback()
            return
        }
        
        guard let audioURI = previewAudioURI else { return }
        
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
        isPlayingPreview = true
        
        // Create player and play
        let playerItem = AVPlayerItem(url: url)
        audioPlayer = AVPlayer(playerItem: playerItem)
        
        // Observe when playback ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            stopPlayback()
        }
        
        audioPlayer?.play()
        isLoadingAudio = false
    }
    
    private func stopPlayback() {
        audioPlayer?.pause()
        audioPlayer = nil
        isPlayingPreview = false
        isLoadingAudio = false
    }
    
    // MARK: - Purchase Form View
    
    private var purchaseFormView: some View {
        ScrollView {
            VStack(spacing: 24) {
                licenseInfoSection
                
                Divider()
                
                // STEMs Section - show tracks from the Digital Master
                stemsSection
                
                Divider()
                
                whatYouGetSection
                
                Divider()
                
                priceBreakdownSection
                
                warningsSection
            }
            .padding(24)
        }
    }
    
    // MARK: - STEMs Section
    
    private var stemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STEMs")
                    .font(.headline)
                
                if let master = digitalMaster {
                    Text("(\(master.stems.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isLoadingMaster {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            if isLoadingMaster {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading tracks...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let master = digitalMaster, !master.stems.isEmpty {
                VStack(spacing: 6) {
                    ForEach(master.stems) { stem in
                        stemRow(stem)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No tracks available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                )
            }
        }
    }
    
    private func stemRow(_ stem: MasterStemInfo) -> some View {
        HStack(spacing: 12) {
            // Icon based on type
            ZStack {
                Circle()
                    .fill(stem.isMIDI ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                    .frame(width: 32, height: 32)
                
                Image(systemName: stem.isMIDI ? "pianokeys" : "waveform")
                    .font(.system(size: 12))
                    .foregroundColor(stem.isMIDI ? .blue : .green)
            }
            
            // Name and duration
            VStack(alignment: .leading, spacing: 2) {
                Text(stem.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                Text(formatStemDuration(stem.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Type badge
            if stem.isMIDI {
                HStack(spacing: 4) {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 9))
                    Text("MIDI")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.1))
                )
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                    Text("AUDIO")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.1))
                )
            }
            
            // MIDI download indicator
            if stem.midiURI != nil {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .help("MIDI file available for download")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }
    
    private func formatStemDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    // MARK: - Image Lightbox
    
    private var imageLightboxOverlay: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingImageLightbox = false
                    }
                }
            
            VStack(spacing: 20) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                if let imageURL = instance.resolvedImageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 450, maxHeight: 450)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.5), radius: 20)
                        case .failure:
                            largeGradientCover
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        @unknown default:
                            largeGradientCover
                        }
                    }
                } else {
                    largeGradientCover
                }
                
                // Title
                VStack(spacing: 4) {
                    Text(instance.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("by \(instance.artistName)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
            }
        }
        .transition(.opacity)
    }
    
    private var largeGradientCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: instance.licenseType.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 300, height: 300)
            
            Image(systemName: instance.licenseType.systemIcon)
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.8))
        }
        .shadow(color: .black.opacity(0.5), radius: 20)
    }
    
    // MARK: - License Info Section
    
    private var licenseInfoSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Cover image - clickable for lightbox
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingImageLightbox = true
                    }
                } label: {
                    ZStack {
                        if let imageURL = instance.resolvedImageURL {
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                default:
                                    gradientCover
                                }
                            }
                        } else {
                            gradientCover
                        }
                        
                        // Hover indicator
                        Color.black.opacity(0.001) // Invisible but tappable
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .help("Click to view larger image")
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(instance.title)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("by \(instance.artistName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: instance.licenseType.systemIcon)
                            .font(.caption)
                        Text(instance.licenseType.title)
                            .font(.caption)
                    }
                    .foregroundColor(instance.licenseType.gradientColors.first ?? .gray)
                }
                
                Spacer()
                
                // Preview play button
                if previewAudioURI != nil {
                    Button {
                        togglePreviewPlayback()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: isPlayingPreview
                                            ? [Color.red.opacity(0.8), Color.red]
                                            : instance.licenseType.gradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                            
                            if isLoadingAudio {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.white)
                            } else {
                                Image(systemName: isPlayingPreview ? "stop.fill" : "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                            }
                        }
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help(isPlayingPreview ? "Stop preview" : "Play preview")
                }
            }
            
            // Owner badge
            if instance.isOwnedByCurrentUser {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("You own this Digital Master")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.1))
                )
            }
        }
    }
    
    private var gradientCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: instance.licenseType.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: instance.licenseType.systemIcon)
                .font(.title)
                .foregroundColor(.white)
        }
    }
    
    // MARK: - What You Get Section
    
    private var whatYouGetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you'll get:")
                .font(.headline)
            
            let accessControl = LicenseAccessControl(licenseType: instance.licenseType)
            ForEach(accessControl.rightsDescription, id: \.self) { right in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(right)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Price Breakdown Section
    
    private var priceBreakdownSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("You Pay")
                    .fontWeight(.bold)
                Spacer()
                Text(String(format: "%.3f TUS", instance.price))
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            
            Divider()
            
            Text("How it's distributed:")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                Text("Creator receives (99%)")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.4f TUS", instance.price * 0.99))
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
            
            HStack {
                Text("Platform fee (1%)")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.4f TUS", instance.price * 0.01))
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
    }
    
    // MARK: - Warnings Section
    
    @ViewBuilder
    private var warningsSection: some View {
        if let error = errorMessage {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                )
        }
        
        if !walletManager.isConnected {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Connect your wallet to make purchases")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
            )
        }
    }
    
    // MARK: - Purchase Button Section
    
    private var purchaseButtonSection: some View {
        VStack(spacing: 12) {
            // Show message if user owns the digital master
            if instance.isOwnedByCurrentUser {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("You already own this Digital Master")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("As the creator, you don't need to purchase a license")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                )
            } else {
                Button {
                    purchaseLicense()
                } label: {
                    HStack {
                        if isPurchasing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "cart.badge.plus")
                        }
                        Text(isPurchasing ? "Processing..." : "Complete Purchase")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: instance.licenseType.gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing || !walletManager.isConnected)
                .opacity(walletManager.isConnected ? 1.0 : 0.5)
                
                if !walletManager.isConnected {
                    Button {
                        NotificationCenter.default.post(name: .showWalletConnection, object: nil)
                    } label: {
                        HStack {
                            Image(systemName: "wallet.pass")
                            Text("Connect Wallet")
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Button {
                dismiss()
            } label: {
                Text(instance.isOwnedByCurrentUser ? "Close" : "Cancel")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Text("Purchase License")
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
        .padding()
    }
    
    // MARK: - Success View
    
    private var successView: some View {
        ZStack {
            // Confetti overlay
            ConfettiView()
            
            VStack(spacing: 20) {
                // Animated checkmark
                successCheckmark
                
                Text("Purchase Complete!")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("\(instance.title) has been added to your library")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Transaction details
                if let txHash = transactionHash {
                    transactionDetailsView(txHash: txHash)
                }
                
                Button {
                    HapticFeedback.success()
                    // Navigate to My Purchases tab
                    NotificationCenter.default.post(name: .showMyPurchases, object: nil)
                    onPurchaseComplete()
                    dismiss()
                } label: {
                    Text("View in My Purchases")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            HapticFeedback.success()
        }
    }
    
    // MARK: - Success Checkmark
    
    @State private var checkmarkScale: CGFloat = 0.5
    @State private var checkmarkOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    
    private var successCheckmark: some View {
        ZStack {
            // Pulse ring
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 100, height: 100)
                .scaleEffect(pulseScale)
            
            // Main circle
            Circle()
                .fill(Color.green)
                .frame(width: 70, height: 70)
            
            // Checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
        }
        .scaleEffect(checkmarkScale)
        .opacity(checkmarkOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.3
            }
        }
    }
    
    // MARK: - Transaction Details View
    
    private func transactionDetailsView(txHash: String) -> some View {
        let truncatedHash = String(txHash.prefix(10)) + "..." + String(txHash.suffix(8))
        let priceText = totalPricePaid ?? "0"
        
        return VStack(spacing: 8) {
            HStack {
                Text("Transaction")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(truncatedHash)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(txHash, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            
            HStack {
                Text("Amount Paid")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(priceText) TUS")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.1))
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Purchase Action
    
    private func purchaseLicense() {
        // Use WalletService for wallet state check
        guard WalletService.shared.hasWallet, WalletService.shared.isUnlocked else {
            errorMessage = "Please unlock your wallet first"
            return
        }
        
        isPurchasing = true
        errorMessage = nil
        
        Task {
            do {
                // Use direct wallet signing via LicensePurchaseService
                let response = try await LicensePurchaseService.shared.purchaseLicenseInstance(
                    instanceId: instance.instanceId,
                    quantity: 1,
                    pricePerUnit: instance.price
                )
                
                await MainActor.run {
                    isPurchasing = false
                    transactionHash = response.transactionHash
                    totalPricePaid = response.totalPrice
                    purchaseComplete = true
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

