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
    
    var body: some View {
        NavigationView {
            Form {
                Section("STEM Type") {
                    Picker("STEM Type", selection: $filters.stemType) {
                        Text("All Types").tag(STEMType?.none)
                        ForEach(STEMType.allCases, id: \.self) { type in
                            Text("\(type.emoji) \(type.displayName)").tag(STEMType?.some(type))
                        }
                    }
                }
                
                Section("Price Range") {
                    HStack {
                        TextField("Min Price", value: $filters.minPrice, format: .number)
                        Text("to")
                        TextField("Max Price", value: $filters.maxPrice, format: .number)
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        filters = MarketplaceFilters()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct WalletConnectionView: View {
    @ObservedObject var blockchainClient: BlockchainClient
    @Environment(\.dismiss) private var dismiss
    @State private var walletAddress: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Connect Your Wallet")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter your wallet address to connect to the marketplace")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                TextField("Wallet Address (0x...)", text: $walletAddress)
                    .textFieldStyle(.roundedBorder)
                    .monospaced()
                
                Button("Connect Wallet") {
                    blockchainClient.connectWallet(address: walletAddress)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(walletAddress.isEmpty)
                
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
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
