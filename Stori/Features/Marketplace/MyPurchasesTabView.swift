//
//  MyPurchasesTabView.swift
//  Stori
//
//  Tab view for Licenses you purchased (ERC-1155)
//  Leverages the DRM framework from Library for license enforcement
//

import SwiftUI
import AVFoundation

/// Tab view showing licenses the user has purchased
/// Uses the existing DRM framework (LicenseEnforcer, LibraryCard, LicensePlayerView)
struct MyPurchasesTabView: View {
    private let walletService = WalletService.shared
    
    // Using PurchasedLicense model for DRM integration
    @State private var licenses: [PurchasedLicense] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @State private var selectedFilter: LibraryFilterOption = .all
    @State private var selectedSort: LibrarySortOption = .recentlyPurchased
    @State private var viewMode: ViewMode = .grid
    @State private var selectedLicense: PurchasedLicense?
    
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
            if !walletService.hasWallet {
                notConnectedView
            } else if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if licenses.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .onAppear {
            loadLicenses()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMyPurchases)) { _ in
            // Reload purchases when navigating here after a purchase
            loadLicenses()
        }
        .sheet(item: $selectedLicense) { license in
            LicensePlayerView(license: license)
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
                    TextField("Search licenses...", text: $searchText)
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
                
                // Filter menu
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
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                
                // Sort menu
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
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                
                // View mode toggle
                HStack(spacing: 4) {
                    Button {
                        viewMode = .grid
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundColor(viewMode == .grid ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        viewMode = .list
                    } label: {
                        Image(systemName: "list.bullet")
                            .foregroundColor(viewMode == .list ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.controlBackgroundColor))
                )
                
                // Stats
                HStack(spacing: 12) {
                    statBadge(value: "\(licenses.count)", label: "Licenses", color: .green)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            // Grid/List content
            ScrollView {
                if viewMode == .grid {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)
                    ], spacing: 20) {
                        ForEach(filteredLicenses) { license in
                            LibraryCard(
                                license: license,
                                onPlay: {
                                    selectedLicense = license
                                },
                                onDownload: LicenseAccessControl(licenseType: license.licenseType).canDownload ? {
                                    downloadLicense(license)
                                } : nil
                            )
                        }
                    }
                    .padding(20)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredLicenses) { license in
                            LibraryListRow(
                                license: license,
                                onPlay: {
                                    selectedLicense = license
                                },
                                onDownload: LicenseAccessControl(licenseType: license.licenseType).canDownload ? {
                                    downloadLicense(license)
                                } : nil
                            )
                        }
                    }
                    .padding(20)
                }
            }
            
            // Footer
            HStack {
                Text("\(filteredLicenses.count) of \(licenses.count) licenses")
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
                
                Text("Connect your wallet to view available licenses")
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
            Text("Loading licenses...")
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
                Text("Error Loading Licenses")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                loadLicenses()
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
                            colors: [.green.opacity(0.1), .blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "bag")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Purchases Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Licenses you purchase from the marketplace will appear here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Data Loading
    
    private func loadLicenses() {
        isLoading = true
        errorMessage = nil
        
        guard walletService.hasWallet, let walletAddress = walletService.address else {
            isLoading = false
            return
        }
        
        Task {
            do {
                let fetchedLicenses = try await DigitalMasterService.shared.fetchPurchasesByBuyer(
                    buyerAddress: walletAddress
                )
                
                // Convert LicenseInstanceWithMaster to PurchasedLicense for DRM framework
                let purchasedLicenses = fetchedLicenses.map { instance in
                    instance.toPurchasedLicense()
                }
                
                await MainActor.run {
                    licenses = purchasedLicenses
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load purchases: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func downloadLicense(_ license: PurchasedLicense) {
        // TODO: Implement download using ContentDeliveryService
    }
}
