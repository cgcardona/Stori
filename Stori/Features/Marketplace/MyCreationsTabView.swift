//
//  MyCreationsTabView.swift
//  Stori
//
//  Tab view for Digital Masters you created (ERC-721)
//

import SwiftUI

/// Tab view showing Digital Masters the user has minted
struct MyCreationsTabView: View {
    private let walletService = WalletService.shared
    
    @State private var masters: [DigitalMasterItem] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var selectedMaster: DigitalMasterItem?
    @State private var searchText: String = ""
    @State private var selectedFilter: MasterFilter = .all
    
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
        
        // Sort by newest first
        result = result.sorted { $0.createdAt > $1.createdAt }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !walletService.hasWallet {
                notConnectedView
            } else if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if masters.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .onAppear {
            loadMasters()
        }
        .sheet(item: $selectedMaster) { master in
            DigitalMasterDetailView(master: master)
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 16) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search creations...", text: $searchText)
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
                
                // Stats
                HStack(spacing: 16) {
                    statBadge(value: "\(masters.count)", label: "Creations", color: .purple)
                    statBadge(value: "\(masters.reduce(0) { $0 + $1.licenseCount })", label: "Licenses", color: .blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            // Grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 16)
                ], spacing: 16) {
                    ForEach(filteredMasters) { master in
                        DigitalMasterCard(master: master) {
                            selectedMaster = master
                        }
                    }
                }
                .padding(20)
            }
            
            // Footer
            HStack {
                Text("\(filteredMasters.count) of \(masters.count) creations")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
    
    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
    
    // MARK: - State Views
    
    private var notConnectedView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "wallet.pass")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 8) {
                Text("Wallet Not Connected")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Connect your wallet to view your creations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your creations...")
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
                    .frame(width: 100, height: 100)
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 8) {
                Text("Error Loading Creations")
                    .font(.title3)
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
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "cube.box")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Creations Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Tokenize your first project to create a Digital Master")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Data Loading
    
    private func loadMasters() {
        isLoading = true
        errorMessage = nil
        
        guard walletService.hasWallet, let walletAddress = walletService.address else {
            isLoading = false
            return
        }
        
        Task {
            do {
                let fetchedMasters = try await DigitalMasterService.shared.fetchDigitalMastersByOwner(
                    address: walletAddress
                )
                
                await MainActor.run {
                    masters = fetchedMasters
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}
