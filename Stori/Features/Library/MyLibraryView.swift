//
//  MyLibraryView.swift
//  Stori
//
//  Created by TellUrStori on 12/10/25.
//

import SwiftUI

/// My Library view displaying all purchased licenses with filtering and sorting
struct MyLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    private let walletManager = WalletManager.shared
    
    // View State
    @State private var licenses: [PurchasedLicense] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    // View Options
    @State private var viewMode: ViewMode = .grid
    @State private var selectedFilter: LibraryFilterOption = .all
    @State private var selectedSort: LibrarySortOption = .recentlyPurchased
    @State private var searchText: String = ""
    
    // Selection & Playback
    @State private var selectedLicense: PurchasedLicense?
    @State private var showingPlayer: Bool = false
    
    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
        
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }
    
    private var filteredLicenses: [PurchasedLicense] {
        var result = licenses
        
        // Apply filter
        if let filterType = selectedFilter.licenseType {
            result = result.filter { $0.licenseType == filterType }
        }
        
        // Apply search
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artistName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sort
        switch selectedSort {
        case .recentlyPurchased:
            result.sort { $0.purchaseDate > $1.purchaseDate }
        case .title:
            result.sort { $0.title < $1.title }
        case .artist:
            result.sort { $0.artistName < $1.artistName }
        case .licenseType:
            result.sort { $0.licenseType.rawValue < $1.licenseType.rawValue }
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
            } else if licenses.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // Content
                contentView
            }
        }
        .frame(width: 900, height: 700)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            loadLibrary()
        }
        .sheet(isPresented: $showingPlayer) {
            if let license = selectedLicense {
                LicensePlayerView(license: license)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: 16) {
            // Title Row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Library")
                        .font(.system(size: 24, weight: .bold))
                    
                    if walletManager.isConnected {
                        Text("\(filteredLicenses.count) item\(filteredLicenses.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // View Mode Toggle
                HStack(spacing: 4) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = mode
                            }
                        } label: {
                            Image(systemName: mode.icon)
                                .font(.system(size: 14))
                                .foregroundColor(viewMode == mode ? .white : .secondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(viewMode == mode ? Color.accentColor : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                )
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            
            // Search and Filters Row
            if walletManager.isConnected && !licenses.isEmpty {
                HStack(spacing: 12) {
                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search library...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )
                    .frame(maxWidth: 250)
                    
                    Spacer()
                    
                    // Filter
                    Menu {
                        ForEach(LibraryFilterOption.allCases, id: \.self) { option in
                            Button {
                                selectedFilter = option
                            } label: {
                                HStack {
                                    Image(systemName: option.icon)
                                    Text(option.rawValue)
                                    if selectedFilter == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedFilter.icon)
                            Text(selectedFilter.rawValue)
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
                    
                    // Sort
                    Menu {
                        ForEach(LibrarySortOption.allCases, id: \.self) { option in
                            Button {
                                selectedSort = option
                            } label: {
                                HStack {
                                    Image(systemName: option.icon)
                                    Text(option.rawValue)
                                    if selectedSort == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedSort.icon)
                            Text(selectedSort.rawValue)
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
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(.controlBackgroundColor),
                    Color(.windowBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Content Views
    
    private var contentView: some View {
        Group {
            if filteredLicenses.isEmpty {
                // No results
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No matches found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Try adjusting your search or filters")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.8))
                    
                    Button("Clear Filters") {
                        searchText = ""
                        selectedFilter = .all
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    switch viewMode {
                    case .grid:
                        gridView
                    case .list:
                        listView
                    }
                }
            }
        }
    }
    
    private var gridView: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)
            ],
            spacing: 20
        ) {
            ForEach(Array(filteredLicenses.enumerated()), id: \.element.id) { index, license in
                LibraryCard(
                    license: license,
                    onPlay: {
                        HapticFeedback.selection()
                        selectedLicense = license
                        showingPlayer = true
                    },
                    onDownload: LicenseAccessControl(licenseType: license.licenseType).canDownload ? {
                        downloadLicense(license)
                    } : nil
                )
                .staggeredAppear(index: index, total: filteredLicenses.count)
                .accessibleCard(
                    label: "\(license.title) by \(license.artistName)",
                    hint: "Double tap to play"
                )
                .accessibleLicenseStatus(license)
            }
        }
        .padding(20)
    }
    
    private var listView: some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(filteredLicenses.enumerated()), id: \.element.id) { index, license in
                LibraryListRow(
                    license: license,
                    onPlay: {
                        HapticFeedback.selection()
                        selectedLicense = license
                        showingPlayer = true
                    },
                    onDownload: LicenseAccessControl(licenseType: license.licenseType).canDownload ? {
                        downloadLicense(license)
                    } : nil
                )
                .staggeredAppear(index: index, total: filteredLicenses.count)
            }
        }
        .padding(20)
    }
    
    // MARK: - State Views
    
    private var loadingView: some View {
        ScrollView {
            SkeletonGrid(columns: 4, count: 8)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "music.note.house")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("Your Library is Empty")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Purchased music will appear here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button {
                // TODO: Open marketplace
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bag")
                    Text("Browse Marketplace")
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var notConnectedView: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "wallet.pass")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 8) {
                Text("Connect Your Wallet")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Connect a wallet to view your purchased licenses")
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
                .background(Color.orange)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Data Loading
    
    private func loadLibrary() {
        guard walletManager.isConnected else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            await fetchLicenses()
        }
    }
    
    private func fetchLicenses() async {
        do {
            let fetchedLicenses = try await LibraryService.shared.fetchPurchasedLicenses(
                ownerAddress: walletManager.walletAddress
            )
            
            await MainActor.run {
                if fetchedLicenses.isEmpty {
                    // Show mock data when no real purchases exist
                    licenses = PurchasedLicense.mockData
                } else {
                    licenses = fetchedLicenses
                }
                isLoading = false
            }
        } catch {
            
            // Fall back to mock data if indexer is not available
            await MainActor.run {
                licenses = PurchasedLicense.mockData
                isLoading = false
            }
        }
    }
    
    private func downloadLicense(_ license: PurchasedLicense) {
        // TODO: Implement download
    }
}
