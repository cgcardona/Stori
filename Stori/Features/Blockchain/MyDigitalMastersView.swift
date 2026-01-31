//
//  MyDigitalMastersView.swift
//  Stori
//
//  Created by TellUrStori on 12/9/25.
//

import SwiftUI

// MARK: - Mock Data Models

/// Digital Master model for display
struct DigitalMasterItem: Identifiable {
    let id: String
    let tokenId: String
    let title: String
    let description: String
    let imageURL: URL?
    let masterAudioURI: String?  // Full song mix audio
    let owners: [MasterOwnerInfo]
    let royaltyPercentage: Int
    let stems: [MasterStemInfo]
    let licenseCount: Int
    let totalRevenue: Double
    let createdAt: Date
    let transactionHash: String
}

struct MasterOwnerInfo: Identifiable {
    let id = UUID()
    let address: String
    let sharePercentage: Int
}

struct MasterStemInfo: Identifiable {
    let id = UUID()
    let name: String
    let duration: TimeInterval
    let audioURI: String?   // Bounced audio (WAV)
    let midiURI: String?    // Original MIDI file (for MIDI tracks)
    let isMIDI: Bool        // Whether this stem was originally MIDI
    let imageURI: String?
    
    init(name: String, duration: TimeInterval, audioURI: String? = nil, midiURI: String? = nil, isMIDI: Bool = false, imageURI: String? = nil) {
        self.name = name
        self.duration = duration
        self.audioURI = audioURI
        self.midiURI = midiURI
        self.isMIDI = isMIDI
        self.imageURI = imageURI
    }
}

// Mock data removed - now using real blockchain data via GraphQL

// MARK: - Filter Options

enum MasterFilter: String, CaseIterable {
    case all = "All"
    case hasLicenses = "With Licenses"
    case noLicenses = "No Licenses"
}

enum MasterSort: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case mostRevenue = "Most Revenue"
    case mostLicenses = "Most Licenses"
}

// MARK: - My Digital Masters View

/// "Channel Content" style view for managing Digital Masters
struct MyDigitalMastersView: View {
    @Environment(\.dismiss) private var dismiss
    private let walletManager = WalletManager.shared
    private let walletService = WalletService.shared
    
    @State private var masters: [DigitalMasterItem] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var selectedMaster: DigitalMasterItem?
    @State private var showingMasterDetail: Bool = false
    @State private var searchText: String = ""
    @State private var selectedFilter: MasterFilter = .all
    @State private var selectedSort: MasterSort = .newest
    @State private var animateGradient: Bool = false
    
    private var filteredMasters: [DigitalMasterItem] {
        var result = masters
        
        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { master in
                master.title.localizedCaseInsensitiveContains(searchText) ||
                master.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply category filter
        switch selectedFilter {
        case .all:
            break
        case .hasLicenses:
            result = result.filter { $0.licenseCount > 0 }
        case .noLicenses:
            result = result.filter { $0.licenseCount == 0 }
        }
        
        // Apply sort
        switch selectedSort {
        case .newest:
            result = result.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            result = result.sorted { $0.createdAt < $1.createdAt }
        case .mostRevenue:
            result = result.sorted { $0.totalRevenue > $1.totalRevenue }
        case .mostLicenses:
            result = result.sorted { $0.licenseCount > $1.licenseCount }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            if !walletManager.isConnected {
                // Not connected state
                notConnectedView
            } else if isLoading {
                // Loading state
                loadingView
            } else if let error = errorMessage {
                // Error state
                errorView(error)
            } else if masters.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // Content
                contentView
            }
        }
        .frame(minWidth: 1000, minHeight: 720)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
            loadMasters()
            // Refresh wallet balance
            Task {
                await walletService.refreshBalance()
            }
        }
        .sheet(isPresented: $showingMasterDetail) {
            if let master = selectedMaster {
                DigitalMasterDetailView(master: master)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 16) {
            // Title and wallet info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "cube.box.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("My Digital Masters")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                if walletManager.isConnected {
                    Text(walletManager.shortAddress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospaced()
                }
            }
            
            Spacer()
            
            // Stats
            HStack(spacing: 24) {
                if !masters.isEmpty {
                    statBadge(value: "\(masters.count)", label: "Masters", color: .purple)
                    statBadge(value: "\(masters.reduce(0) { $0 + $1.licenseCount })", label: "Licenses", color: .blue)
                }
                // Show wallet balance
                statBadge(value: walletService.formattedBalance, label: "Balance", color: .orange)
            }
            
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }
    
    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 16) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search masters...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
            .frame(maxWidth: 300)
            
            Spacer()
            
            // Filter
            Picker("", selection: $selectedFilter) {
                ForEach(MasterFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            
            // Sort
            Menu {
                ForEach(MasterSort.allCases, id: \.self) { sort in
                    Button {
                        selectedSort = sort
                    } label: {
                        HStack {
                            Text(sort.rawValue)
                            if selectedSort == sort {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(selectedSort.rawValue)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.windowBackgroundColor).opacity(0.95))
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        VStack(spacing: 0) {
            toolbar
            
            Divider()
            
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 20)
                ], spacing: 20) {
                    ForEach(filteredMasters) { master in
                        DigitalMasterCard(master: master) {
                            selectedMaster = master
                            showingMasterDetail = true
                        }
                    }
                }
                .padding(20)
            }
            
            // Results count
            HStack {
                Text("\(filteredMasters.count) of \(masters.count) masters")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
    
    // MARK: - State Views
    
    private var notConnectedView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "wallet.pass")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 8) {
                Text("Wallet Not Connected")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Connect your wallet to view your Digital Masters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button {
                NotificationCenter.default.post(name: .showWalletConnection, object: nil)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                    Text("Connect Wallet")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading your Digital Masters...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 8) {
                Text("Error Loading Masters")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                loadMasters()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding()
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.1), .blue.opacity(0.1)],
                            startPoint: animateGradient ? .topLeading : .bottomTrailing,
                            endPoint: animateGradient ? .bottomTrailing : .topLeading
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image(systemName: "cube.box")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Digital Masters Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Tokenize your first project to create a Digital Master")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button {
                NotificationCenter.default.post(name: .tokenizeProject, object: nil)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Tokenize Project")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
    
    // MARK: - Data Loading
    
    private func loadMasters() {
        isLoading = true
        errorMessage = nil
        
        guard walletManager.isConnected else {
            isLoading = false
            return
        }
        
        Task {
            await fetchMasters()
        }
    }
    
    private func fetchMasters() async {
        do {
            // Use WalletService for the wallet address
            guard let walletAddress = WalletService.shared.address else {
                await MainActor.run {
                    errorMessage = "No wallet connected"
                    isLoading = false
                }
                return
            }
            
            
            let fetchedMasters = try await DigitalMasterService.shared.fetchDigitalMastersByOwner(
                address: walletAddress
            )
            
            
            await MainActor.run {
                masters = fetchedMasters
                isLoading = false
            }
        } catch {
            
            await MainActor.run {
                errorMessage = "Failed to load Digital Masters: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}
