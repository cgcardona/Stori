//
//  MarketplaceView.swift
//  TellUrStoriDAW
//
//  🎵 TellUrStori V2 - STEM Marketplace Interface
//
//  Browse, search, and trade STEM NFTs with real-time blockchain data,
//  advanced filtering, and integrated audio preview capabilities.
//

import SwiftUI
import AVFoundation

struct MarketplaceView: View {
    @StateObject private var blockchainClient = BlockchainClient()
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
                // Browse STEMs
                BrowseSTEMsView(
                    blockchainClient: blockchainClient,
                    searchText: $searchText,
                    filters: $selectedFilters,
                    currentlyPlayingSTEM: $currentlyPlayingSTEM,
                    isPlaying: $isPlaying,
                    onPlaySTEM: playSTEM
                )
                .tag(MarketplaceTab.browse)
                
                // My STEMs
                MySTEMsView(
                    blockchainClient: blockchainClient,
                    currentlyPlayingSTEM: $currentlyPlayingSTEM,
                    isPlaying: $isPlaying,
                    onPlaySTEM: playSTEM
                )
                .tag(MarketplaceTab.myStems)
                
                // Activity
                ActivityView(blockchainClient: blockchainClient)
                .tag(MarketplaceTab.activity)
                
                // Analytics
                AnalyticsView(blockchainClient: blockchainClient)
                .tag(MarketplaceTab.analytics)
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
    }
    
    private var marketplaceHeader: some View {
        VStack(spacing: 12) {
            HStack {
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("🎵 STEM Marketplace")
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
                    
                    // Wallet connection
                    Button(action: {
                        if blockchainClient.currentWallet == nil {
                            showingWalletConnection = true
                        } else {
                            blockchainClient.disconnectWallet()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: blockchainClient.currentWallet != nil ? "wallet.pass.fill" : "wallet.pass")
                            
                            if let wallet = blockchainClient.currentWallet {
                                Text("\(wallet.address.prefix(6))...\(wallet.address.suffix(4))")
                                    .monospaced()
                            } else {
                                Text("Connect Wallet")
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(blockchainClient.currentWallet != nil ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                        .foregroundColor(blockchainClient.currentWallet != nil ? .green : .blue)
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
        // Stop current playback
        audioPlayer?.stop()
        isPlaying = false
        
        guard let audioCID = stem.audioCID else {
            print("No audio CID available for STEM")
            return
        }
        
        // For now, simulate audio playback
        // In a real implementation, this would fetch from IPFS
        currentlyPlayingSTEM = stem
        isPlaying = true
        
        // Simulate playback duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if currentlyPlayingSTEM?.id == stem.id {
                isPlaying = false
                currentlyPlayingSTEM = nil
            }
        }
        
        print("🎵 Playing STEM: \(stem.name) (CID: \(audioCID))")
    }
}

// MARK: - Marketplace Tabs

enum MarketplaceTab: String, CaseIterable {
    case browse = "browse"
    case myStems = "myStems"
    case activity = "activity"
    case analytics = "analytics"
    
    var title: String {
        switch self {
        case .browse: return "Browse"
        case .myStems: return "My STEMs"
        case .activity: return "Activity"
        case .analytics: return "Analytics"
        }
    }
    
    var iconName: String {
        switch self {
        case .browse: return "music.note.list"
        case .myStems: return "person.crop.circle"
        case .activity: return "clock"
        case .analytics: return "chart.bar"
        }
    }
}

// MARK: - Browse STEMs View

struct BrowseSTEMsView: View {
    @ObservedObject var blockchainClient: BlockchainClient
    @Binding var searchText: String
    @Binding var filters: MarketplaceFilters
    @Binding var currentlyPlayingSTEM: STEMToken?
    @Binding var isPlaying: Bool
    let onPlaySTEM: (STEMToken) -> Void
    
    @State private var selectedSTEM: STEMToken?
    @State private var showingSTEMDetail: Bool = false
    
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
            pricePerToken: "2500000000000000000", // 2.5 AVAX
            totalPrice: "12500000000000000000", // 12.5 AVAX
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
            pricePerToken: "1800000000000000000", // 1.8 AVAX
            totalPrice: "5400000000000000000", // 5.4 AVAX
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
            pricePerToken: "750000000000000000", // 0.75 AVAX
            totalPrice: "7500000000000000000", // 7.5 AVAX
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
            pricePerToken: "3200000000000000000", // 3.2 AVAX
            totalPrice: "6400000000000000000", // 6.4 AVAX
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
            pricePerToken: "1200000000000000000", // 1.2 AVAX
            totalPrice: "9600000000000000000", // 9.6 AVAX
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
            pricePerToken: "2100000000000000000", // 2.1 AVAX
            totalPrice: "8400000000000000000", // 8.4 AVAX
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
                            showingSTEMDetail = true
                        }
                    )
                }
            }
            .padding()
        }
        .refreshable {
            await blockchainClient.refreshData()
        }
        .sheet(isPresented: $showingSTEMDetail) {
            if let stem = selectedSTEM {
                STEMDetailView(stem: stem, blockchainClient: blockchainClient)
            }
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
                        
                        Text("\(formatPrice(listing.pricePerToken)) AVAX")
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
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatPrice(_ price: String) -> String {
        if let priceValue = Double(price) {
            return String(format: "%.4f", priceValue / 1e18) // Convert from wei
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
    @ObservedObject var blockchainClient: BlockchainClient
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
                        Text("\(formatPrice(floorPrice)) AVAX")
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
            return String(format: "%.4f", priceValue / 1e18)
        }
        return price
    }
}

// MARK: - Activity View

struct ActivityView: View {
    @ObservedObject var blockchainClient: BlockchainClient
    
    // Placeholder activity data
    private let placeholderActivities: [ActivityItem] = [
        ActivityItem(
            id: "1",
            type: .purchase,
            stemName: "Epic Bass Drop",
            amount: "2.5 AVAX",
            timestamp: Date().addingTimeInterval(-300), // 5 minutes ago
            fromAddress: "0x1234...5678",
            toAddress: "0x9876...5432",
            transactionHash: "0xabcd...efgh"
        ),
        ActivityItem(
            id: "2",
            type: .sale,
            stemName: "Synthwave Melody",
            amount: "1.8 AVAX",
            timestamp: Date().addingTimeInterval(-1800), // 30 minutes ago
            fromAddress: "0x5555...6666",
            toAddress: "0x7777...8888",
            transactionHash: "0x1111...2222"
        ),
        ActivityItem(
            id: "3",
            type: .mint,
            stemName: "Lo-Fi Hip Hop Beat",
            amount: "0.1 AVAX",
            timestamp: Date().addingTimeInterval(-3600), // 1 hour ago
            fromAddress: nil,
            toAddress: "0x9999...0000",
            transactionHash: "0x3333...4444"
        ),
        ActivityItem(
            id: "4",
            type: .listing,
            stemName: "Ambient Soundscape",
            amount: "3.2 AVAX",
            timestamp: Date().addingTimeInterval(-7200), // 2 hours ago
            fromAddress: "0xaaaa...bbbb",
            toAddress: nil,
            transactionHash: "0x5555...6666"
        ),
        ActivityItem(
            id: "5",
            type: .offer,
            stemName: "Trap Drums",
            amount: "0.9 AVAX",
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
                        value: "12.4 AVAX",
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
    @ObservedObject var blockchainClient: BlockchainClient
    
    private func formatVolume(_ volume: String) -> String {
        guard let volumeDouble = Double(volume) else { return "0" }
        let avaxVolume = volumeDouble / 1e18 // Convert from wei to AVAX
        return String(format: "%.1f", avaxVolume)
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
                            subtitle: "AVAX",
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
                                Text("2.4 AVAX")
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
                        GenreStatsRow(genre: "Electronic", percentage: 35, volume: "296.5 AVAX")
                        GenreStatsRow(genre: "Hip Hop", percentage: 28, volume: "237.2 AVAX")
                        GenreStatsRow(genre: "Pop", percentage: 18, volume: "152.5 AVAX")
                        GenreStatsRow(genre: "Rock", percentage: 12, volume: "101.7 AVAX")
                        GenreStatsRow(genre: "Ambient", percentage: 7, volume: "59.3 AVAX")
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
                        HighSaleRow(stemName: "Epic Bass Drop", price: "12.5 AVAX", time: "2h ago")
                        HighSaleRow(stemName: "Synthwave Melody", price: "8.9 AVAX", time: "5h ago")
                        HighSaleRow(stemName: "Trap Drums", price: "7.2 AVAX", time: "1d ago")
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

struct WalletConnectionView: View {
    @ObservedObject var blockchainClient: BlockchainClient
    @Environment(\.dismiss) private var dismiss
    @State private var walletAddress: String = ""
    @State private var isConnecting: Bool = false
    @State private var showingSuccess: Bool = false
    @State private var animateGradient: Bool = false
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.1),
                    Color.purple.opacity(0.1),
                    Color.pink.opacity(0.1)
                ],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animateGradient)
            
            VStack(spacing: 0) {
                // Header with icon and title
                VStack(spacing: 16) {
                    // Wallet icon with glow effect
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(showingSuccess ? 1.2 : 1.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showingSuccess)
                    
                    VStack(spacing: 8) {
                        Text("Connect Your Wallet")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.primary, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Enter your wallet address to access the STEM marketplace and start trading music NFTs")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 40)
                
                // Connection form
                VStack(spacing: 24) {
                    // Wallet address input with enhanced styling
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wallet Address")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            
                            TextField("0x1234567890abcdef...", text: $walletAddress)
                                .textFieldStyle(.plain)
                                .monospaced()
                                .font(.system(size: 14))
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.controlBackgroundColor))
                                .stroke(
                                    walletAddress.isEmpty ? Color.clear : 
                                    isValidAddress ? Color.green.opacity(0.5) : Color.red.opacity(0.5),
                                    lineWidth: 1
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                                .opacity(walletAddress.isEmpty ? 0 : 1)
                        )
                        
                        // Address validation feedback
                        if !walletAddress.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: isValidAddress ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(isValidAddress ? .green : .orange)
                                
                                Text(isValidAddress ? "Valid wallet address" : "Please enter a valid Ethereum address")
                                    .font(.caption)
                                    .foregroundColor(isValidAddress ? .green : .orange)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    
                    // Network info card
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.blue)
                            Text("Network Information")
                                .font(.headline)
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Network", value: "TellUrStori L1")
                            InfoRow(label: "Chain ID", value: "507")
                            InfoRow(label: "Currency", value: "TUS Token")
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.controlBackgroundColor).opacity(0.5))
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    // Connect button with loading state
                    Button(action: connectWallet) {
                        HStack(spacing: 12) {
                            if isConnecting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: showingSuccess ? "checkmark.circle.fill" : "wallet.pass.fill")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            
                            Text(isConnecting ? "Connecting..." : showingSuccess ? "Connected!" : "Connect Wallet")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: showingSuccess ? [.green, .green.opacity(0.8)] : [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        )
                        .foregroundColor(.white)
                        .scaleEffect(isConnecting ? 0.98 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: isConnecting)
                    }
                    .disabled(walletAddress.isEmpty || !isValidAddress || isConnecting)
                    .opacity(walletAddress.isEmpty || !isValidAddress ? 0.6 : 1.0)
                    
                    // Cancel button
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            animateGradient = true
        }
    }
    
    private var isValidAddress: Bool {
        walletAddress.hasPrefix("0x") && walletAddress.count == 42
    }
    
    private func connectWallet() {
        isConnecting = true
        
        // Simulate connection process with animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            blockchainClient.connectWallet(address: walletAddress)
            showingSuccess = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                dismiss()
            }
        }
    }
}

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
    @ObservedObject var blockchainClient: BlockchainClient
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("STEM Detail View")
                        .font(.title)
                    
                    Text("TODO: Implement detailed STEM view with purchase options")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle(stem.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
