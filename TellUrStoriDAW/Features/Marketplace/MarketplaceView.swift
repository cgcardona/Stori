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
    
    var filteredListings: [MarketplaceListing] {
        var listings = blockchainClient.marketplaceListings
        
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
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
            ], spacing: 16) {
                ForEach(blockchainClient.userSTEMs, id: \.id) { stem in
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
            if blockchainClient.userSTEMs.isEmpty {
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
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(blockchainClient.recentActivity, id: \.id) { activity in
                    ActivityCard(activity: activity)
                }
            }
            .padding()
        }
        .refreshable {
            await blockchainClient.refreshData()
        }
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let networkInfo = blockchainClient.networkInfo {
                    // Market overview
                    VStack(alignment: .leading, spacing: 16) {
                        Text("📊 Market Overview")
                            .font(.headline)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            StatCard(title: "Total Volume", value: formatPrice(networkInfo.totalVolume), subtitle: "AVAX")
                            StatCard(title: "Total STEMs", value: "\(networkInfo.totalSTEMs)", subtitle: "tokens")
                            StatCard(title: "Active Listings", value: "\(networkInfo.activeListings)", subtitle: "listings")
                            StatCard(title: "Creators", value: "\(networkInfo.totalCreators)", subtitle: "artists")
                        }
                    }
                    
                    // Floor price
                    if let floorPrice = networkInfo.floorPrice {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("💎 Floor Price")
                                .font(.headline)
                            
                            Text("\(formatPrice(floorPrice)) AVAX")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await blockchainClient.refreshData()
        }
    }
    
    private func formatPrice(_ price: String) -> String {
        if let priceValue = Double(price) {
            return String(format: "%.2f", priceValue / 1e18)
        }
        return price
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
