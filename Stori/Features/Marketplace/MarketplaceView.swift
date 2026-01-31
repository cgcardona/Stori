//
//  MarketplaceView.swift
//  Stori
//
//  🎵 Stori - STEM Marketplace Interface
//
//  Browse, search, and trade STEM NFTs with real-time blockchain data,
//  advanced filtering, and integrated audio preview capabilities.
//

import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins

struct MarketplaceView: View {
    @State private var blockchainClient = BlockchainClient()
    private let walletService = WalletService.shared
    @State private var selectedTab: MarketplaceTab = .browse
    @State private var searchText: String = ""
    @State private var selectedFilters: MarketplaceFilters = MarketplaceFilters()
    @State private var showingFilters: Bool = false
    @State private var showingWalletConnection: Bool = false
    
    // Audio preview
    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentlyPlayingSTEM: STEMToken?
    @State private var isPlaying: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            marketplaceHeader
            
            // Tab bar
            marketplaceTabBar
            
            // Content
            TabView(selection: $selectedTab) {
                // Browse License Instances
                BrowseLicensesView()
                .tag(MarketplaceTab.browse)
                
                // My Creations (Digital Masters you minted)
                MyCreationsTabView()
                .tag(MarketplaceTab.myCreations)
                
                // My Purchases (Licenses you bought)
                MyPurchasesTabView()
                .tag(MarketplaceTab.myPurchases)
            }
            .tabViewStyle(DefaultTabViewStyle())
        }
        .sheet(isPresented: $showingFilters) {
            MarketplaceFiltersView(filters: $selectedFilters)
        }
        .sheet(isPresented: $showingWalletConnection) {
            WalletConnectionView(blockchainClient: blockchainClient)
        }
        .onAppear {
            Task {
                await blockchainClient.checkConnections()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMyPurchases)) { _ in
            selectedTab = .myPurchases
        }
    }
    
    private var marketplaceHeader: some View {
        VStack(spacing: 12) {
            HStack {
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("🎵 Stori Marketplace")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let networkInfo = blockchainClient.networkInfo {
                        Text("\(networkInfo.totalSTEMs) STEMs • \(networkInfo.activeListings) Active Listings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Connection status and wallet
                HStack(spacing: 12) {
                    // Connection indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(blockchainClient.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text(blockchainClient.connectionStatus.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Wallet connection - uses WalletService for actual wallet state
                    Button(action: {
                        // Navigate to wallet tab to unlock/manage wallet
                        NotificationCenter.default.post(name: .openWalletTab, object: nil)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: walletService.hasWallet && walletService.isUnlocked ? "wallet.pass.fill" : "wallet.pass")
                            
                            if walletService.hasWallet && walletService.isUnlocked, let address = walletService.address {
                                Text("\(address.prefix(6))...\(address.suffix(4))")
                                    .monospaced()
                            } else if walletService.hasWallet {
                                Text("Unlock Wallet")
                            } else {
                                Text("Connect Wallet")
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(walletService.isUnlocked ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                        .foregroundColor(walletService.isUnlocked ? .green : .blue)
                        .cornerRadius(8)
                    }
                }
            }
            
            // Search and filters (only for browse tab)
            if selectedTab == .browse {
                HStack {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search STEMs...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Filters button
                    Button(action: {
                        showingFilters = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("Filters")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedFilters.hasActiveFilters ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .foregroundColor(selectedFilters.hasActiveFilters ? .blue : .primary)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separatorColor)),
            alignment: .bottom
        )
    }
    
    private var marketplaceTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MarketplaceTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 16))
                        
                        Text(tab.title)
                            .font(.caption)
                    }
                    .foregroundColor(selectedTab == tab ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(Color(.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separatorColor)),
            alignment: .bottom
        )
    }
    
    // MARK: - Audio Preview
    
    private func playSTEM(_ stem: STEMToken) {
        // If the same stem is already playing, pause it
        if currentlyPlayingSTEM?.id == stem.id && isPlaying {
            audioPlayer?.stop()
            isPlaying = false
            currentlyPlayingSTEM = nil
            return
        }
        
        // Stop any current playback
        audioPlayer?.stop()
        isPlaying = false
        
        guard let audioCID = stem.audioCID else {
            return
        }
        
        
        // Use local IPFS gateway
        let ipfsURL = "http://127.0.0.1:8080/ipfs/\(audioCID)"
        guard let audioURL = URL(string: ipfsURL) else {
            return
        }
        
        
        // Load and play audio from IPFS
        Task {
            do {
                // Download audio data from IPFS
                let (data, response) = try await URLSession.shared.data(from: audioURL)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    return
                }
                
                
                // Create temporary file to play audio
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("ipfs_audio_\(audioCID).wav")
                TempFileManager.track(tempFile)
                try data.write(to: tempFile)
                
                // Play audio using AVFoundation
                await MainActor.run {
                    do {
                        audioPlayer = try AVAudioPlayer(contentsOf: tempFile)
                        audioPlayer?.prepareToPlay()
                        audioPlayer?.play()
                        
        currentlyPlayingSTEM = stem
        isPlaying = true
        
                        
                        // Set up completion handler
                        if let duration = audioPlayer?.duration {
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                if self.currentlyPlayingSTEM?.id == stem.id {
                                    self.isPlaying = false
                                    self.currentlyPlayingSTEM = nil
                                }
                            }
                        }
                    } catch {
                    }
                }
            } catch {
            }
        }
    }
}

// MARK: - Marketplace Tabs

enum MarketplaceTab: String, CaseIterable {
    case browse = "browse"
    case myCreations = "myCreations"
    case myPurchases = "myPurchases"
    
    var title: String {
        switch self {
        case .browse: return "Browse"
        case .myCreations: return "My Creations"
        case .myPurchases: return "My Purchases"
        }
    }
    
    var iconName: String {
        switch self {
        case .browse: return "music.note.list"
        case .myCreations: return "cube.box.fill"
        case .myPurchases: return "bag.fill"
        }
    }
}

// MARK: - Browse STEMs View

struct BrowseSTEMsView: View {
    var blockchainClient: BlockchainClient
    @Binding var searchText: String
    @Binding var filters: MarketplaceFilters
    @Binding var currentlyPlayingSTEM: STEMToken?
    @Binding var isPlaying: Bool
    @Binding var audioPlayer: AVAudioPlayer?
    let onPlaySTEM: (STEMToken) -> Void
    
    @State private var selectedSTEM: STEMToken?
    
    // Beautiful placeholder data for Browse tab
    private let placeholderListings: [MarketplaceListing] = [
        MarketplaceListing(
            id: "listing_1",
            listingId: "listing_1",
            seller: "0x1234567890abcdef1234567890abcdef12345678",
            stem: STEMToken(
                id: "stem_1",
                tokenId: "1",
                name: "🔥 Epic Bass Drop",
                description: "Massive bass drop perfect for EDM tracks",
                creator: "0x1234567890abcdef1234567890abcdef12345678",
                stemType: .bass,
                duration: 45,
                bpm: 128,
                key: "Am",
                genre: "Electronic",
                totalSupply: "100",
                floorPrice: "2500000000000000000",
                lastSalePrice: "2200000000000000000",
                totalVolume: "5000000000000000000",
                createdAt: Date().addingTimeInterval(-86400 * 30),
                audioCID: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
                imageCID: "QmImageCID1"
            ),
            amount: "5",
            pricePerToken: "2500000000000000000", // 2.5 TUS
            totalPrice: "12500000000000000000", // 12.5 TUS
            expiration: Date().addingTimeInterval(86400 * 7), // 1 week
            createdAt: Date().addingTimeInterval(-86400 * 2)
        ),
        MarketplaceListing(
            id: "listing_2",
            listingId: "listing_2",
            seller: "0x9876543210fedcba9876543210fedcba98765432",
            stem: STEMToken(
                id: "stem_2",
                tokenId: "2",
                name: "✨ Synthwave Melody",
                description: "Nostalgic 80s synthwave lead melody",
                creator: "0x9876543210fedcba9876543210fedcba98765432",
                stemType: .melody,
                duration: 32,
                bpm: 110,
                key: "C#m",
                genre: "Synthwave",
                totalSupply: "50",
                floorPrice: "1800000000000000000",
                lastSalePrice: "1600000000000000000",
                totalVolume: "3600000000000000000",
                createdAt: Date().addingTimeInterval(-86400 * 20),
                audioCID: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
                imageCID: "QmImageCID2"
            ),
            amount: "3",
            pricePerToken: "1800000000000000000", // 1.8 TUS
            totalPrice: "5400000000000000000", // 5.4 TUS
            expiration: Date().addingTimeInterval(86400 * 5), // 5 days
            createdAt: Date().addingTimeInterval(-86400 * 1)
        ),
        MarketplaceListing(
            id: "listing_3",
            listingId: "listing_3",
            seller: "0xabcdef1234567890abcdef1234567890abcdef12",
            stem: STEMToken(
                id: "stem_3",
                tokenId: "3",
                name: "🎵 Lo-Fi Hip Hop Beat",
                description: "Chill lo-fi drums with vinyl crackle",
                creator: "0xabcdef1234567890abcdef1234567890abcdef12",
                stemType: .drums,
                duration: 60,
                bpm: 85,
                key: "F",
                genre: "Hip Hop",
                totalSupply: "200",
                floorPrice: "750000000000000000",
                lastSalePrice: "700000000000000000",
                totalVolume: "7500000000000000000",
                createdAt: Date().addingTimeInterval(-86400 * 15),
                audioCID: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
                imageCID: "QmImageCID3"
            ),
            amount: "10",
            pricePerToken: "750000000000000000", // 0.75 TUS
            totalPrice: "7500000000000000000", // 7.5 TUS
            expiration: nil,
            createdAt: Date().addingTimeInterval(-86400 * 3)
        ),
        MarketplaceListing(
            id: "listing_4",
            listingId: "listing_4",
            seller: "0x5555666677778888999900001111222233334444",
            stem: STEMToken(
                id: "stem_4",
                tokenId: "4",
                name: "🌊 Ambient Soundscape",
                description: "Ethereal ambient pad with reverb",
                creator: "0x5555666677778888999900001111222233334444",
                stemType: .harmony,
                duration: 120,
                bpm: 72,
                key: "Dm",
                genre: "Ambient",
                totalSupply: "25",
                floorPrice: "3200000000000000000",
                lastSalePrice: "3000000000000000000",
                totalVolume: "6400000000000000000",
                createdAt: Date().addingTimeInterval(-86400 * 10),
                audioCID: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
                imageCID: "QmImageCID4"
            ),
            amount: "2",
            pricePerToken: "3200000000000000000", // 3.2 TUS
            totalPrice: "6400000000000000000", // 6.4 TUS
            expiration: Date().addingTimeInterval(86400 * 3), // 3 days
            createdAt: Date().addingTimeInterval(-86400 * 1)
        ),
        MarketplaceListing(
            id: "listing_5",
            listingId: "listing_5",
            seller: "0xaaaaaabbbbbbccccccddddddeeeeeeffffffffff",
            stem: STEMToken(
                id: "stem_5",
                tokenId: "5",
                name: "🥁 Trap Drums",
                description: "Hard-hitting trap drum pattern with 808s",
                creator: "0xaaaaaabbbbbbccccccddddddeeeeeeffffffffff",
                stemType: .drums,
                duration: 30,
                bpm: 140,
                key: "G",
                genre: "Trap",
                totalSupply: "75",
                floorPrice: "1200000000000000000",
                lastSalePrice: "1100000000000000000",
                totalVolume: "9600000000000000000",
                createdAt: Date().addingTimeInterval(-86400 * 5),
                audioCID: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
                imageCID: "QmImageCID5"
            ),
            amount: "8",
            pricePerToken: "1200000000000000000", // 1.2 TUS
            totalPrice: "9600000000000000000", // 9.6 TUS
            expiration: Date().addingTimeInterval(86400 * 10), // 10 days
            createdAt: Date().addingTimeInterval(-86400 * 2)
        ),
        MarketplaceListing(
            id: "listing_6",
            listingId: "listing_6",
            seller: "0x1111222233334444555566667777888899990000",
            stem: STEMToken(
                id: "stem_6",
                tokenId: "6",
                name: "🎸 Rock Guitar Riff",
                description: "Powerful distorted guitar riff in drop D",
                creator: "0x1111222233334444555566667777888899990000",
                stemType: .melody,
                duration: 25,
                bpm: 120,
                key: "D",
                genre: "Rock",
                totalSupply: "40",
                floorPrice: "2100000000000000000",
                lastSalePrice: "2000000000000000000",
                totalVolume: "8400000000000000000",
                createdAt: Date().addingTimeInterval(-86400 * 7),
                audioCID: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
                imageCID: "QmImageCID6"
            ),
            amount: "4",
            pricePerToken: "2100000000000000000", // 2.1 TUS
            totalPrice: "8400000000000000000", // 8.4 TUS
            expiration: Date().addingTimeInterval(86400 * 14), // 2 weeks
            createdAt: Date().addingTimeInterval(-86400 * 1)
        )
    ]
    
    var filteredListings: [MarketplaceListing] {
        // Use placeholder data if no blockchain data available
        var listings = blockchainClient.marketplaceListings.isEmpty ? placeholderListings : blockchainClient.marketplaceListings
        
        // Apply search filter
        if !searchText.isEmpty {
            listings = listings.filter { listing in
                listing.stem.name.localizedCaseInsensitiveContains(searchText) ||
                listing.stem.description.localizedCaseInsensitiveContains(searchText) ||
                listing.stem.genre?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        // Apply filters
        if let stemType = filters.stemType {
            listings = listings.filter { $0.stem.stemType == stemType }
        }
        
        if let genre = filters.genre, !genre.isEmpty {
            listings = listings.filter { $0.stem.genre == genre }
        }
        
        if let minPrice = filters.minPrice {
            listings = listings.filter {
                (Double($0.pricePerToken) ?? 0) >= minPrice
            }
        }
        
        if let maxPrice = filters.maxPrice {
            listings = listings.filter {
                (Double($0.pricePerToken) ?? Double.greatestFiniteMagnitude) <= maxPrice
            }
        }
        
        return listings
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
            ], spacing: 16) {
                ForEach(filteredListings, id: \.id) { listing in
                    STEMListingCard(
                        listing: listing,
                        isPlaying: currentlyPlayingSTEM?.id == listing.stem.id && isPlaying,
                        onPlay: { onPlaySTEM(listing.stem) },
                        onTap: {
                            selectedSTEM = listing.stem
                        }
                    )
                }
            }
            .padding()
        }
        .refreshable {
            await blockchainClient.refreshData()
        }
        .onChange(of: selectedSTEM) { oldValue, newValue in
            // Stop audio playback when opening modal detail view
            if newValue != nil && isPlaying {
                audioPlayer?.stop()
                isPlaying = false
                currentlyPlayingSTEM = nil
            }
        }
        .sheet(item: $selectedSTEM) { stem in
            STEMDetailView(stem: stem, blockchainClient: blockchainClient)
        }
        .overlay {
            if filteredListings.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No STEMs Found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Try adjusting your search or filters")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - STEM Listing Card

struct STEMListingCard: View {
    let listing: MarketplaceListing
    let isPlaying: Bool
    let onPlay: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Phase 8: Album artwork image section
            if let imageCID = listing.stem.imageCID, !imageCID.isEmpty {
                ZStack(alignment: .bottomTrailing) {
                    // Placeholder for IPFS image (would load from ipfs://imageCID in production)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .purple.opacity(0.6), .pink.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 160)
                        .cornerRadius(8)
                        .overlay(
                            Group {
                                if let imageCID = listing.stem.imageCID, !imageCID.isEmpty {
                                    // Load actual image from IPFS
                                    AsyncImage(url: URL(string: "http://127.0.0.1:8080/ipfs/\(imageCID)")) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(height: 160)
                                                .clipped()
                                        case .failure:
                                            // Fallback if image fails to load
                            VStack {
                                Image(systemName: "photo.artframe")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.8))
                                Text("Album Artwork")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                        case .empty:
                                            // Show loading indicator
                                            ProgressView()
                                                .tint(.white)
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                } else {
                                    // No image CID - show placeholder
                                    VStack {
                                        Image(systemName: "photo.artframe")
                                            .font(.system(size: 48))
                                            .foregroundColor(.white.opacity(0.8))
                                        Text("Album Artwork")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                            }
                        )
                    
                    // IPFS badge
                    HStack(spacing: 4) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 10))
                        Text("IPFS")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(8)
                }
            }
            
            // Header with play button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.stem.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    HStack {
                        Text(listing.stem.stemType.emoji)
                        Text(listing.stem.stemType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let genre = listing.stem.genre {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(genre)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
            }
            
            // STEM details
            HStack {
                if listing.stem.duration > 0 {
                    Label("\(formatDuration(Double(listing.stem.duration)))", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if listing.stem.bpm > 0 {
                    Label("\(listing.stem.bpm) BPM", systemImage: "metronome")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let key = listing.stem.key {
                    Label(key, systemImage: "music.note")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Pricing and seller info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Price per Token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(formatPrice(listing.pricePerToken)) TUS")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(listing.amount) tokens")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                
                HStack {
                    Text("Seller: \(listing.seller.prefix(6))...\(listing.seller.suffix(4))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospaced()
                    
                    Spacer()
                    
                    if let expiration = listing.expiration {
                        Text("Expires: \(formatDate(expiration))")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .onTapGesture {
            onTap()
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let totalSeconds = Int(round(duration))  // Round instead of truncate
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatPrice(_ price: String) -> String {
        if let priceValue = Double(price) {
            // Remove trailing zeros: 1.2000 → 1.2, 0.7500 → 0.75
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 4
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: priceValue)) ?? price
        }
        return price
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - My STEMs View

struct MySTEMsView: View {
    var blockchainClient: BlockchainClient
    @Binding var currentlyPlayingSTEM: STEMToken?
    @Binding var isPlaying: Bool
    let onPlaySTEM: (STEMToken) -> Void
    
    // Placeholder user STEMs data
    private let placeholderUserSTEMs: [STEMToken] = [
        STEMToken(
            id: "my_stem_1",
            tokenId: "101",
            name: "🎹 My Piano Melody",
            description: "Beautiful piano composition I created",
            creator: "0x1234567890abcdef1234567890abcdef12345678", // User's address
            stemType: .melody,
            duration: 180,
            bpm: 90,
            key: "C",
            genre: "Classical",
            totalSupply: "10",
            floorPrice: "1500000000000000000",
            lastSalePrice: "1400000000000000000",
            totalVolume: "15000000000000000000",
            createdAt: Date().addingTimeInterval(-86400 * 7),
            audioCID: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
            imageCID: "QmMyImageCID1"
        ),
        STEMToken(
            id: "my_stem_2",
            tokenId: "102",
            name: "🎤 Vocal Harmony",
            description: "Layered vocal harmonies in A minor",
            creator: "0x1234567890abcdef1234567890abcdef12345678",
            stemType: .vocals,
            duration: 90,
            bpm: 100,
            key: "Am",
            genre: "Pop",
            totalSupply: "5",
            floorPrice: "2000000000000000000",
            lastSalePrice: "1900000000000000000",
            totalVolume: "10000000000000000000",
            createdAt: Date().addingTimeInterval(-86400 * 14),
            audioCID: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
            imageCID: "QmMyImageCID2"
        ),
        STEMToken(
            id: "my_stem_3",
            tokenId: "103",
            name: "🎛️ Synth Pad",
            description: "Warm analog synth pad with filter sweep",
            creator: "0x1234567890abcdef1234567890abcdef12345678",
            stemType: .harmony,
            duration: 240,
            bpm: 120,
            key: "Em",
            genre: "Electronic",
            totalSupply: "20",
            floorPrice: "1000000000000000000",
            lastSalePrice: "950000000000000000",
            totalVolume: "20000000000000000000",
            createdAt: Date().addingTimeInterval(-86400 * 21),
            audioCID: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
            imageCID: "QmMyImageCID3"
        )
    ]
    
    private var displaySTEMs: [STEMToken] {
        return blockchainClient.userSTEMs.isEmpty ? placeholderUserSTEMs : blockchainClient.userSTEMs
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
            ], spacing: 16) {
                ForEach(displaySTEMs, id: \.id) { stem in
                    MySTEMCard(
                        stem: stem,
                        isPlaying: currentlyPlayingSTEM?.id == stem.id && isPlaying,
                        onPlay: { onPlaySTEM(stem) }
                    )
                }
            }
            .padding()
        }
        .refreshable {
            await blockchainClient.refreshData()
        }
        .overlay {
            if displaySTEMs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.house")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No STEMs Yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if blockchainClient.currentWallet == nil {
                        Text("Connect your wallet to view your STEMs")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Create your first STEM by generating AI music!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - My STEM Card

struct MySTEMCard: View {
    let stem: STEMToken
    let isPlaying: Bool
    let onPlay: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Phase 8: Album artwork image section
            if let imageCID = stem.imageCID, !imageCID.isEmpty {
                ZStack(alignment: .bottomTrailing) {
                    // Placeholder for IPFS image (would load from ipfs://imageCID in production)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .purple.opacity(0.6), .pink.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 140)
                        .cornerRadius(8)
                        .overlay(
                            Group {
                                if let imageCID = stem.imageCID, !imageCID.isEmpty {
                                    // Load actual image from IPFS
                                    AsyncImage(url: URL(string: "http://127.0.0.1:8080/ipfs/\(imageCID)")) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(height: 140)
                                                .clipped()
                                        case .failure:
                                            // Fallback if image fails to load
                            VStack {
                                Image(systemName: "photo.artframe")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.8))
                                Text("Album Artwork")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                        case .empty:
                                            // Show loading indicator
                                            ProgressView()
                                                .tint(.white)
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                } else {
                                    // No image CID - show placeholder
                                    VStack {
                                        Image(systemName: "photo.artframe")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white.opacity(0.8))
                                        Text("Album Artwork")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                            }
                        )
                    
                    // IPFS badge
                    HStack(spacing: 4) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 10))
                        Text("IPFS")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(8)
                }
            }
            
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stem.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    HStack {
                        Text(stem.stemType.emoji)
                        Text(stem.stemType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
            }
            
            // Stats
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Supply")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(stem.totalSupply)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                if let floorPrice = stem.floorPrice {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Floor Price")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(formatPrice(floorPrice)) TUS")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Create Listing") {
                    // TODO: Implement listing creation
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("View Details") {
                    // TODO: Implement detail view
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }
    
    private func formatPrice(_ price: String) -> String {
        if let priceValue = Double(price) {
            // Remove trailing zeros: 1.2000 → 1.2, 0.7500 → 0.75
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 4
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: priceValue)) ?? price
        }
        return price
    }
}

// MARK: - Activity View

struct ActivityView: View {
    var blockchainClient: BlockchainClient
    
    // Placeholder activity data
    private let placeholderActivities: [ActivityItem] = [
        ActivityItem(
            id: "1",
            type: .purchase,
            stemName: "Epic Bass Drop",
            amount: "2.5 TUS",
            timestamp: Date().addingTimeInterval(-300), // 5 minutes ago
            fromAddress: "0x1234...5678",
            toAddress: "0x9876...5432",
            transactionHash: "0xabcd...efgh"
        ),
        ActivityItem(
            id: "2",
            type: .sale,
            stemName: "Synthwave Melody",
            amount: "1.8 TUS",
            timestamp: Date().addingTimeInterval(-1800), // 30 minutes ago
            fromAddress: "0x5555...6666",
            toAddress: "0x7777...8888",
            transactionHash: "0x1111...2222"
        ),
        ActivityItem(
            id: "3",
            type: .mint,
            stemName: "Lo-Fi Hip Hop Beat",
            amount: "0.1 TUS",
            timestamp: Date().addingTimeInterval(-3600), // 1 hour ago
            fromAddress: nil,
            toAddress: "0x9999...0000",
            transactionHash: "0x3333...4444"
        ),
        ActivityItem(
            id: "4",
            type: .listing,
            stemName: "Ambient Soundscape",
            amount: "3.2 TUS",
            timestamp: Date().addingTimeInterval(-7200), // 2 hours ago
            fromAddress: "0xaaaa...bbbb",
            toAddress: nil,
            transactionHash: "0x5555...6666"
        ),
        ActivityItem(
            id: "5",
            type: .offer,
            stemName: "Trap Drums",
            amount: "0.9 TUS",
            timestamp: Date().addingTimeInterval(-10800), // 3 hours ago
            fromAddress: "0xcccc...dddd",
            toAddress: "0xeeee...ffff",
            transactionHash: "0x7777...8888"
        )
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Activity Summary Cards
                HStack(spacing: 16) {
                    ActivitySummaryCard(
                        title: "Today's Volume",
                        value: "12.4 TUS",
                        change: "+8.2%",
                        isPositive: true,
                        icon: "chart.line.uptrend.xyaxis"
                    )
                    
                    ActivitySummaryCard(
                        title: "Transactions",
                        value: "47",
                        change: "+12",
                        isPositive: true,
                        icon: "arrow.left.arrow.right"
                    )
                    
                    ActivitySummaryCard(
                        title: "Active Listings",
                        value: "23",
                        change: "-2",
                        isPositive: false,
                        icon: "list.bullet"
                    )
                }
                .padding(.horizontal)
                
                // Activity Feed
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recent Activity")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Button("View All") {
                            // Action to view all activity
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                    
                    LazyVStack(spacing: 8) {
                        ForEach(blockchainClient.recentActivity) { activity in
                            RealActivityCard(activity: activity)
                        }
                        
                        // Show placeholder if no real activity yet
                        if blockchainClient.recentActivity.isEmpty {
                            ForEach(placeholderActivities) { activity in
                                EnhancedActivityCard(activity: activity)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await blockchainClient.refreshData()
        }
    }
}

// MARK: - Real Activity Card

struct RealActivityCard: View {
    let activity: BlockchainActivity
    
    var body: some View {
        HStack(spacing: 12) {
            // Activity Type Icon
            Circle()
                .fill(activity.type.color.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(activity.type.emoji)
                        .font(.title3)
                )
            
            // Activity Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.type.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(activity.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Token #\(activity.tokenId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(activity.address.prefix(10) + "..." + activity.address.suffix(4))
                    .font(.caption)
                    .foregroundColor(.blue)
                    .monospaced()
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Activity Supporting Types

struct ActivityItem: Identifiable {
    let id: String
    let type: MarketplaceActivityType
    let stemName: String
    let amount: String
    let timestamp: Date
    let fromAddress: String?
    let toAddress: String?
    let transactionHash: String
}

enum MarketplaceActivityType {
    case purchase, sale, mint, listing, offer
    
    var emoji: String {
        switch self {
        case .purchase: return "🛒"
        case .sale: return "💰"
        case .mint: return "✨"
        case .listing: return "📋"
        case .offer: return "🤝"
        }
    }
    
    var displayName: String {
        switch self {
        case .purchase: return "Purchase"
        case .sale: return "Sale"
        case .mint: return "Mint"
        case .listing: return "Listed"
        case .offer: return "Offer"
        }
    }
    
    var color: Color {
        switch self {
        case .purchase: return .blue
        case .sale: return .green
        case .mint: return .purple
        case .listing: return .orange
        case .offer: return .yellow
        }
    }
}

// MARK: - Activity Summary Card

struct ActivitySummaryCard: View {
    let title: String
    let value: String
    let change: String
    let isPositive: Bool
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                
                Spacer()
                
                HStack(spacing: 2) {
                    Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                        .font(.caption)
                    Text(change)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(isPositive ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Enhanced Activity Card

struct EnhancedActivityCard: View {
    let activity: ActivityItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Activity type icon
            ZStack {
                Circle()
                    .fill(activity.type.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Text(activity.type.emoji)
                    .font(.title3)
            }
            
            // Activity details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.type.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(activity.amount)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                
                Text(activity.stemName)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                HStack {
                    Text(formatRelativeTime(activity.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    let hash = String(activity.transactionHash.prefix(8)) + "..."
                    Text(hash)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospaced()
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ActivityCard: View {
    let activity: BlockchainActivity
    
    var body: some View {
        HStack(spacing: 12) {
            Text(activity.type.emoji)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.type.displayName)
                    .font(.headline)
                
                Text("Token ID: \(activity.tokenId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(activity.address.prefix(6))...\(activity.address.suffix(4))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospaced()
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatDate(activity.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Block \(activity.blockNumber)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Analytics View

struct AnalyticsView: View {
    var blockchainClient: BlockchainClient
    
    private func formatVolume(_ volume: String) -> String {
        guard let volumeDouble = Double(volume) else { return "0" }
        let tusVolume = volumeDouble / 1e18 // Convert from wei to TUS
        return String(format: "%.1f", tusVolume)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Market Overview Cards
                VStack(alignment: .leading, spacing: 16) {
                    Text("📊 Market Overview")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        EnhancedStatCard(
                            title: "Total Volume",
                            value: formatVolume(blockchainClient.networkInfo?.totalVolume ?? "0"),
                            subtitle: "TUS",
                            change: "+12.5%",
                            isPositive: true,
                            icon: "chart.bar.fill"
                        )
                        EnhancedStatCard(
                            title: "Total STEMs",
                            value: "\(blockchainClient.networkInfo?.totalSTEMs ?? 0)",
                            subtitle: "tokens",
                            change: "+8",
                            isPositive: true,
                            icon: "music.note"
                        )
                        EnhancedStatCard(
                            title: "Active Listings",
                            value: "\(blockchainClient.networkInfo?.activeListings ?? 0)",
                            subtitle: "listings",
                            change: "-3",
                            isPositive: false,
                            icon: "list.bullet"
                        )
                        EnhancedStatCard(
                            title: "Creators",
                            value: "\(blockchainClient.networkInfo?.totalCreators ?? 0)",
                            subtitle: "artists",
                            change: "+5",
                            isPositive: true,
                            icon: "person.3.fill"
                        )
                    }
                }
                
                // Price Chart
                VStack(alignment: .leading, spacing: 16) {
                    Text("💎 Floor Price Trend")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Floor")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("2.4 TUS")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up")
                                        .font(.caption)
                                    Text("+15.2%")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.green)
                                
                                Text("24h change")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Simple chart representation
                        SimpleChartView()
                            .frame(height: 120)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                }
                
                // Top Genres
                VStack(alignment: .leading, spacing: 16) {
                    Text("🎵 Popular Genres")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack(spacing: 12) {
                        GenreStatsRow(genre: "Electronic", percentage: 35, volume: "296.5 TUS")
                        GenreStatsRow(genre: "Hip Hop", percentage: 28, volume: "237.2 TUS")
                        GenreStatsRow(genre: "Pop", percentage: 18, volume: "152.5 TUS")
                        GenreStatsRow(genre: "Rock", percentage: 12, volume: "101.7 TUS")
                        GenreStatsRow(genre: "Ambient", percentage: 7, volume: "59.3 TUS")
                    }
                }
                
                // Recent Sales
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("🔥 Recent High Sales")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Button("View All") {
                            // Action to view all sales
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    
                    VStack(spacing: 8) {
                        HighSaleRow(stemName: "Epic Bass Drop", price: "12.5 TUS", time: "2h ago")
                        HighSaleRow(stemName: "Synthwave Melody", price: "8.9 TUS", time: "5h ago")
                        HighSaleRow(stemName: "Trap Drums", price: "7.2 TUS", time: "1d ago")
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await blockchainClient.refreshData()
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Enhanced Analytics Components

struct EnhancedStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let change: String
    let isPositive: Bool
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                
                Spacer()
                
                HStack(spacing: 2) {
                    Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                        .font(.caption)
                    Text(change)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(isPositive ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SimpleChartView: View {
    private let dataPoints: [Double] = [2.1, 2.3, 2.0, 2.4, 2.6, 2.2, 2.8, 2.4, 2.9, 2.4]
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let stepX = width / CGFloat(dataPoints.count - 1)
                
                let minY = dataPoints.min() ?? 0
                let maxY = dataPoints.max() ?? 1
                let range = maxY - minY
                
                for (index, point) in dataPoints.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = height - (CGFloat(point - minY) / CGFloat(range)) * height
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
            
            // Add gradient fill
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let stepX = width / CGFloat(dataPoints.count - 1)
                
                let minY = dataPoints.min() ?? 0
                let maxY = dataPoints.max() ?? 1
                let range = maxY - minY
                
                path.move(to: CGPoint(x: 0, y: height))
                
                for (index, point) in dataPoints.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = height - (CGFloat(point - minY) / CGFloat(range)) * height
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                path.addLine(to: CGPoint(x: geometry.size.width, y: height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.3), .purple.opacity(0.1), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

struct GenreStatsRow: View {
    let genre: String
    let percentage: Int
    let volume: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(genreEmoji(for: genre))
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(genre)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(percentage)%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                
                HStack {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)
                                .cornerRadius(2)
                            
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * CGFloat(percentage) / 100, height: 4)
                                .cornerRadius(2)
                        }
                    }
                    .frame(height: 4)
                    
                    Text(volume)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func genreEmoji(for genre: String) -> String {
        switch genre.lowercased() {
        case "electronic": return "🎛️"
        case "hip hop": return "🎤"
        case "pop": return "🎵"
        case "rock": return "🎸"
        case "ambient": return "🌊"
        default: return "🎵"
        }
    }
}

struct HighSaleRow: View {
    let stemName: String
    let price: String
    let time: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Text("💰")
                    .font(.caption)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(stemName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(price)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.green)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Supporting Types

struct MarketplaceFilters {
    var stemType: STEMType?
    var genre: String?
    var minPrice: Double?
    var maxPrice: Double?
    var minDuration: Int?
    var maxDuration: Int?
    var sortBy: SortOption = .newest
    
    var hasActiveFilters: Bool {
        return stemType != nil || genre != nil || minPrice != nil || maxPrice != nil || minDuration != nil || maxDuration != nil
    }
    
    enum SortOption: String, CaseIterable {
        case newest = "newest"
        case oldest = "oldest"
        case priceLow = "priceLow"
        case priceHigh = "priceHigh"
        case popular = "popular"
        
        var displayName: String {
            switch self {
            case .newest: return "Newest First"
            case .oldest: return "Oldest First"
            case .priceLow: return "Price: Low to High"
            case .priceHigh: return "Price: High to Low"
            case .popular: return "Most Popular"
            }
        }
    }
}

// MARK: - Placeholder Views

struct MarketplaceFiltersView: View {
    @Binding var filters: MarketplaceFilters
    @Environment(\.dismiss) private var dismiss
    @State private var animateGradient: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.3),
                    Color.purple.opacity(0.3),
                    Color.pink.opacity(0.3)
                ]),
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .frame(height: 120)
            .overlay(
                VStack(spacing: 8) {
                    // Filter icon with glow effect
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .blur(radius: 10)
                        
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    
                    // Title with gradient text
                    Text("Filter STEMs")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    animateGradient = true
                }
            }
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // STEM Type Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "music.note.list")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            Text("STEM Type")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                        }
                        
                        // Custom picker with beautiful styling
                        VStack(spacing: 12) {
                            Menu {
                                Button("All Types") {
                                    filters.stemType = nil
                                }
                                
                                ForEach(STEMType.allCases, id: \.self) { type in
                                    Button("\(type.emoji) \(type.displayName)") {
                                        filters.stemType = type
                                    }
                                }
                            } label: {
                                HStack {
                                    if let stemType = filters.stemType {
                                        Text("\(stemType.emoji) \(stemType.displayName)")
                                    } else {
                                        Text("All Types")
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                        )
                                )
                                .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Price Range Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "dollarsign.circle")
                                .foregroundColor(.green)
                                .font(.title3)
                            
                            Text("Price Range")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                        }
                        
                        HStack(spacing: 16) {
                            // Min Price
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Min Price")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Image(systemName: "dollarsign")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    
                                    TextField("0", value: $filters.minPrice, format: .number)
                                        .textFieldStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            
                            // "to" separator with styling
                            VStack {
                                Spacer()
                                Text("to")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 8)
                            }
                            
                            // Max Price
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Max Price")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Image(systemName: "dollarsign")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    
                                    TextField("∞", value: $filters.maxPrice, format: .number)
                                        .textFieldStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Active Filters Summary
                    if filters.hasActiveFilters {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                
                                Text("Active Filters")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                if let stemType = filters.stemType {
                                    HStack {
                                        Text("Type:")
                                            .foregroundColor(.secondary)
                                        Text("\(stemType.emoji) \(stemType.displayName)")
                                            .fontWeight(.medium)
                                        Spacer()
                                    }
                                }
                                
                                if let minPrice = filters.minPrice, minPrice > 0 {
                                    HStack {
                                        Text("Min Price:")
                                            .foregroundColor(.secondary)
                                        Text("$\(minPrice, specifier: "%.2f")")
                                            .fontWeight(.medium)
                                        Spacer()
                                    }
                                }
                                
                                if let maxPrice = filters.maxPrice, maxPrice > 0 {
                                    HStack {
                                        Text("Max Price:")
                                            .foregroundColor(.secondary)
                                        Text("$\(maxPrice, specifier: "%.2f")")
                                            .fontWeight(.medium)
                                        Spacer()
                                    }
                                }
                            }
                            .font(.caption)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.top, 20)
            }
            
            // Action buttons
            HStack(spacing: 16) {
                // Reset button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        filters = MarketplaceFilters()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Done button
                Button(action: {
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Done")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .background(Color(.windowBackgroundColor))
        }
        .frame(width: 500, height: 600)
    }
}

// WalletConnectionView moved to Features/Blockchain/WalletConnectionView.swift

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospaced()
        }
    }
}

struct STEMDetailView: View {
    let stem: STEMToken
    var blockchainClient: BlockchainClient
    @Environment(\.dismiss) private var dismiss
    
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var selectedQuantity = 1
    @State private var showingPurchaseConfirmation = false
    
    // Purchase QR Code Payment State
    @State private var isGeneratingPayment = false
    @State private var paymentAddress: String?
    @State private var paymentAmount: String?
    @State private var paymentQRCode: NSImage?
    @State private var paymentRequestId: String?
    @State private var isPollingPayment = false
    @State private var isPurchasing = false
    @State private var purchaseComplete = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var listing: MarketplaceListing? {
        blockchainClient.marketplaceListings.first { $0.stem.id == stem.id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header Bar
            HStack {
                Text(stem.name)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(.separatorColor)),
                alignment: .bottom
            )
            
            // Main Content
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - Hero Section with Album Artwork
                    heroSection
                        .frame(maxWidth: .infinity)
                    
                    // MARK: - Main Content
                    VStack(alignment: .leading, spacing: 24) {
                        // Audio Controls
                        audioControlsSection
                        
                        Divider()
                        
                        // Metadata
                        metadataSection
                        
                        Divider()
                        
                        // Creator Info
                        creatorSection
                        
                        Divider()
                        
                        // Token Economics
                        tokenEconomicsSection
                        
                        // Purchase Section (if listed)
                        if let listing = listing {
                            Divider()
                            purchaseSection(listing: listing)
                        }
                        
                        Divider()
                        
                        // Technical Details
                        technicalDetailsSection
                    }
                    .padding(24)
                }
            }
            .background(Color(.windowBackgroundColor))
        }
        .frame(width: 800, height: 900)
        .background(Color(.windowBackgroundColor))
        .overlay {
            if paymentQRCode != nil {
                purchasePaymentView
            }
        }
        .overlay {
            if purchaseComplete {
                purchaseSuccessView
            }
        }
        .onDisappear {
            // Stop audio playback when modal is dismissed
            audioPlayer?.stop()
            isPlaying = false
        }
    }
    
    // MARK: - Purchase Payment View
    
    private var purchasePaymentView: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            
            // Payment modal
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Purchase Payment Required")
                        .font(.system(size: 24, weight: .bold))
                    
                    Text("Scan QR code or send payment to the address below")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // QR Code
                if let qrCode = paymentQRCode {
                    Image(nsImage: qrCode)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                }
                
                // Payment details
                VStack(spacing: 16) {
                    // Payment address
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Payment Address")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(paymentAddress ?? "")
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Button {
                                copyToClipboard(paymentAddress ?? "")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                }
                .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Payment amount
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Amount")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(paymentAmount ?? "")
                                .font(.system(.body, design: .monospaced))
                            
                            Button {
                                copyToClipboard(paymentAmount ?? "")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .frame(width: 400)
                
                // Status
                if isPollingPayment {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Waiting for payment confirmation...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                if isPurchasing {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Completing purchase...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Cancel button
                if !isPollingPayment && !isPurchasing {
                    Button("Cancel") {
                        paymentQRCode = nil
                        paymentAddress = nil
                        paymentAmount = nil
                        paymentRequestId = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(32)
            .background(Color(.windowBackgroundColor))
            .cornerRadius(16)
            .shadow(radius: 20)
            .frame(width: 500)
        }
    }
    
    // MARK: - Purchase Success View
    
    private var purchaseSuccessView: some View {
        ZStack {
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                Text("Purchase Complete!")
                    .font(.title.bold())
                
                Text("You now own \(selectedQuantity) token\(selectedQuantity > 1 ? "s" : "") of \(stem.name)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                    Button("Done") {
                    purchaseComplete = false
                        dismiss()
                    }
                .buttonStyle(.borderedProminent)
            }
            .padding(40)
            .background(Color(.windowBackgroundColor))
            .cornerRadius(16)
            .shadow(radius: 20)
            .frame(width: 400)
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.3),
                    Color.purple.opacity(0.3),
                    Color.pink.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(maxWidth: .infinity)
            .frame(height: 350)
            
            VStack(spacing: 16) {
                // Album Artwork
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    if let imageCID = stem.imageCID, !imageCID.isEmpty {
                        // Load actual image from IPFS
                        AsyncImage(url: URL(string: "http://127.0.0.1:8080/ipfs/\(imageCID)")) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 220, height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                            case .failure:
                                // Fallback if image fails to load
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.artframe")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white.opacity(0.9))
                                    Text("Album Artwork")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            case .empty:
                                // Show loading indicator
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(1.5)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.9))
                            Text((stem.genre ?? "STEM").uppercased())
                                .font(.caption.bold())
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    // Play button overlay
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 70, height: 70)
                        .overlay {
                            Button {
                                if isPlaying {
                                    // Stop playback
                                    audioPlayer?.stop()
                                    isPlaying = false
                                } else {
                                    // Start playback
                                    playAudio()
                                }
                            } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                }
                
                // Title and Creator
                VStack(spacing: 8) {
                    Text(stem.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .font(.caption)
                        Text(formatAddress(stem.creator))
                            .font(.subheadline)
                    }
                    .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }
    
    // MARK: - Audio Controls
    
    private var audioControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text("Audio Preview")
                    .font(.title3.bold())
            }
            
            HStack(spacing: 16) {
                Button {
                    if isPlaying {
                        // Stop playback
                        audioPlayer?.stop()
                        isPlaying = false
                    } else {
                        // Start playback
                        playAudio()
                    }
                } label: {
                    HStack {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                        Text(isPlaying ? "Pause" : "Play Preview")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                if let audioCID = stem.audioCID, !audioCID.isEmpty {
                    Button {
                        // Download action
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.title2)
                            Text("Download")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                        .frame(width: 100)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Metadata
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text("Details")
                    .font(.title3.bold())
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                MetadataCard(icon: "music.quarternote.3", title: "Genre", value: stem.genre ?? "Not specified")
                MetadataCard(icon: "metronome", title: "BPM", value: stem.bpm > 0 ? "\(stem.bpm)" : "—")
                MetadataCard(icon: "clock", title: "Duration", value: formatDuration(stem.duration))
                MetadataCard(icon: "music.note.list", title: "Key", value: stem.key ?? "Not specified")
            }
        }
    }
    
    // MARK: - Creator Section
    
    private var creatorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.circle")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text("Creator")
                    .font(.title3.bold())
            }
            
            HStack(spacing: 12) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .overlay {
                        Text(stem.creator.prefix(2).uppercased())
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatAddress(stem.creator))
                        .font(.headline)
                    Text("Creator Address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    // View creator profile
                } label: {
                    Text("View Profile")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Token Economics
    
    private var tokenEconomicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text("Token Economics")
                    .font(.title3.bold())
            }
            
            HStack(spacing: 16) {
                TokenStatCard(
                    icon: "number",
                    title: "Token ID",
                    value: "#\(stem.tokenId)",
                    color: .blue
                )
                
                TokenStatCard(
                    icon: "square.stack.3d.up",
                    title: "Total Supply",
                    value: "\(stem.totalSupply)",
                    color: .purple
                )
                
                if let listing = listing {
                    TokenStatCard(
                        icon: "bag",
                        title: "Available",
                        value: listing.amount,
                        color: .green
                    )
                }
            }
        }
    }
    
    // MARK: - Purchase Section
    
    private func purchaseSection(listing: MarketplaceListing) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cart")
                    .font(.title3)
                    .foregroundColor(.green)
                Text("Purchase")
                    .font(.title3.bold())
            }
            
            VStack(spacing: 16) {
                // Price and availability
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Price per Token")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(listing.pricePerToken)
                                .font(.system(size: 32, weight: .bold))
                            Text("TUS")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(listing.amount) tokens")
                            .font(.title3.bold())
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(12)
                
                // Quantity selector
                HStack {
                    Text("Quantity:")
                        .font(.headline)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button {
                            if selectedQuantity > 1 {
                                selectedQuantity -= 1
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(selectedQuantity > 1 ? .blue : .gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(selectedQuantity <= 1)
                        
                        Text("\(selectedQuantity)")
                            .font(.title2.bold())
                            .frame(minWidth: 50)
                        
                        Button {
                            if let availableInt = Int(listing.amount), selectedQuantity < availableInt {
                                selectedQuantity += 1
                            }
                        } label: {
                            let availableInt = Int(listing.amount) ?? 0
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(selectedQuantity < availableInt ? .blue : .gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(selectedQuantity >= (Int(listing.amount) ?? 0))
                    }
                }
                
                // Total price
                if let priceDouble = Double(listing.pricePerToken) {
                    HStack {
                        Text("Total Price:")
                            .font(.headline)
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.4f", priceDouble * Double(selectedQuantity)))
                                .font(.title2.bold())
                            Text("TUS")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Purchase button
                Button {
                    generatePurchasePayment(listing: listing)
                } label: {
                    HStack {
                        Image(systemName: "cart.fill")
                        Text("Purchase \(selectedQuantity) Token\(selectedQuantity > 1 ? "s" : "")")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Expiry info
                if let expiration = listing.expiration {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.orange)
                        Text("Listing expires: \(expiration.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.green.opacity(0.3), lineWidth: 2)
            )
        }
    }
    
    // MARK: - Technical Details
    
    private var technicalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gearshape.2")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text("Technical Details")
                    .font(.title3.bold())
            }
            
            VStack(alignment: .leading, spacing: 8) {
                TechnicalDetailRow(label: "Contract Address", value: formatAddress("0xContract"))
                TechnicalDetailRow(label: "Token Standard", value: "ERC-1155")
                TechnicalDetailRow(label: "Blockchain", value: "Avalanche L1")
                if let audioCID = stem.audioCID, !audioCID.isEmpty {
                    TechnicalDetailRow(label: "Audio IPFS", value: String(audioCID.prefix(20)) + "...")
                }
                if let imageCID = stem.imageCID, !imageCID.isEmpty {
                    TechnicalDetailRow(label: "Image IPFS", value: String(imageCID.prefix(20)) + "...")
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        if seconds == 0 { return "—" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    // MARK: - Audio Playback
    
    private func playAudio() {
        
        guard let audioCID = stem.audioCID, !audioCID.isEmpty else {
            return
        }
        
        
        // Use local IPFS gateway
        let ipfsURL = "http://127.0.0.1:8080/ipfs/\(audioCID)"
        guard let audioURL = URL(string: ipfsURL) else {
            return
        }
        
        
        // Load and play audio from IPFS
        Task {
            do {
                // Download audio data from IPFS
                let (data, response) = try await URLSession.shared.data(from: audioURL)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    return
                }
                
                
                // Create temporary file to play audio
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("ipfs_audio_modal_\(audioCID).wav")
                TempFileManager.track(tempFile)
                try data.write(to: tempFile)
                
                // Play audio using AVFoundation
                await MainActor.run {
                    do {
                        audioPlayer = try AVAudioPlayer(contentsOf: tempFile)
                        audioPlayer?.prepareToPlay()
                        audioPlayer?.play()
                        
                        isPlaying = true
                        
                        
                        // Set up completion handler
                        if let duration = audioPlayer?.duration {
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                if self.isPlaying {
                                    self.isPlaying = false
                                }
                            }
                        }
                    } catch {
                    }
                }
            } catch {
            }
        }
    }
    
    // MARK: - Purchase Payment Functions
    
    private func generatePurchasePayment(listing: MarketplaceListing) {
        isGeneratingPayment = true
        
        Task {
            await MainActor.run {
                // Generate unique request ID (EIP-681 compliant)
                let requestId = UUID().uuidString
                paymentRequestId = requestId
                
                // Seller receives the payment
                paymentAddress = listing.seller
                
                // Calculate total payment amount
                guard let pricePerToken = Double(listing.pricePerToken) else {
                    errorMessage = "Invalid price"
                    showError = true
                    isGeneratingPayment = false
                    return
                }
                
                let totalPrice = pricePerToken * Double(selectedQuantity)
                paymentAmount = String(format: "%.4f TUS", totalPrice)
                
                // Convert to wei (1 TUS = 10^18 wei)
                let totalPriceWei = Int(totalPrice * 1e18)
                let amountInWei = String(totalPriceWei)
                
                // Encode request ID as hex for transaction data (EIP-681)
                let requestIdData = Data(requestId.utf8)
                let requestIdHex = "0x" + requestIdData.map { String(format: "%02x", $0) }.joined()
                
                // Generate EIP-681 compliant Ethereum URI
                // Format: ethereum:<address>@<chainId>?value=<amount>&data=<requestId>
                let chainId = "18" // sandbox04 L1 chain ID
                let qrData = "ethereum:\(listing.seller)@\(chainId)?value=\(amountInWei)&data=\(requestIdHex)"
                
                paymentQRCode = generateQRCode(from: qrData)
                isGeneratingPayment = false
                
                
                // Start polling for payment
                startPollingPurchasePayment()
            }
        }
    }
    
    private func startPollingPurchasePayment() {
        isPollingPayment = true
        
        Task {
            await pollForPurchasePaymentConfirmation()
        }
    }
    
    private func pollForPurchasePaymentConfirmation() async {
        guard let requestId = paymentRequestId,
              let seller = paymentAddress else {
            return
        }
        
        
        // Poll every 2 seconds for up to 5 minutes
        let maxAttempts = 150
        var attempts = 0
        
        while attempts < maxAttempts && isPollingPayment {
            attempts += 1
            
            // Check if payment was received
            let paymentReceived = await checkForPurchasePayment(requestId: requestId, seller: seller)
            
            if paymentReceived {
                await MainActor.run {
                    isPollingPayment = false
                    completePurchase()
                }
                return
            }
            
            // Wait 2 seconds before next check
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        // Timeout
        await MainActor.run {
            isPollingPayment = false
            errorMessage = "Payment confirmation timeout. Please check your transaction."
            showError = true
        }
    }
    
    private func checkForPurchasePayment(requestId: String, seller: String) async -> Bool {
        // Query blockchain for transaction with matching request ID
        
        do {
            // Use BlockchainClient to query recent transactions
            // In a real implementation, this would query the RPC endpoint for recent blocks
            // and check each transaction to see if it matches our criteria:
            // 1. Recipient (to) = seller address
            // 2. Transaction data contains the request ID
            
            // For Phase 3.9, we'll simulate detection after checking payment-history.json
            // In production, this would be replaced with actual blockchain queries
            
            // Simulate blockchain query delay
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Check if the transaction exists in the blockchain
            // This is where you would call:
            // let hasPayment = await blockchainClient.checkTransactionByRequestId(requestId: requestId, seller: seller)
            
            // For now, check if enough time has passed (simulate detection)
            // In production, replace this with actual transaction lookup
            let hasPayment = await checkPaymentHistoryFile(requestId: requestId)
            
            if hasPayment {
            }
            
            return hasPayment
            
        } catch {
            return false
        }
    }
    
    private func checkPaymentHistoryFile(requestId: String) async -> Bool {
        // Temporary helper: Check if payment exists in payment-history.json
        // This simulates blockchain detection for Phase 3.9
        // In production, this would be replaced with actual blockchain RPC calls
        
        // Use absolute path to payment-history.json in the workspace
        let paymentHistoryPath = "/Users/gabriel/dev/tellurstori/MacOS/Stori/blockchain/payment-history.json"
        let fileURL = URL(fileURLWithPath: paymentHistoryPath)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: paymentHistoryPath) else {
            return false
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                
                // Check if any payment has this request ID
                let hasPayment = json.contains { payment in
                    if let paymentRequestId = payment["requestId"] as? String {
                        let matches = paymentRequestId == requestId
                        if matches {
                        }
                        return matches
                    }
                    return false
                }
                
                if !hasPayment {
                }
                
                return hasPayment
            }
        } catch {
        }
        
        return false
    }
    
    private func completePurchase() {
        isPurchasing = true
        
        Task {
            do {
                // Call marketplace contract to complete purchase
                guard let listing = listing else {
                    throw NSError(domain: "Purchase", code: 1, userInfo: [NSLocalizedDescriptionKey: "No listing found"])
                }
                
                
                // TODO: Call blockchainClient.purchaseTokens()
                // This would call the STEMMarketplace.purchaseTokens() function
                
                // Simulate successful purchase
                try await Task.sleep(nanoseconds: 2_000_000_000)
                
                await MainActor.run {
                    isPurchasing = false
                    paymentQRCode = nil
                    purchaseComplete = true
                    
                    
                    // Refresh marketplace data
                    Task {
                        await blockchainClient.refreshData()
                    }
                }
                
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    errorMessage = "Purchase failed: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // Scale up the QR code
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Supporting Views

struct MetadataCard: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct TokenStatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline.bold())
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct TechnicalDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospaced())
                .foregroundColor(.primary)
        }
    }
}
