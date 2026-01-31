//
//  WalletView.swift
//  Stori
//
//  Main wallet tab view - shows setup or dashboard based on wallet state
//

import SwiftUI
import BigInt
import CoreImage
import AppKit

struct WalletView: View {
    private let walletService = WalletService.shared
    @State private var setupMode: WalletSetupMode?
    @State private var showingUnlock = false
    
    var body: some View {
        Group {
            if walletService.isUnlocked {
                WalletDashboardView()
            } else if walletService.hasWallet {
                WalletLockedView(showingUnlock: $showingUnlock)
            } else {
                WalletWelcomeView(setupMode: $setupMode)
            }
        }
        .sheet(item: $setupMode) { mode in
            WalletSetupView(initialMode: mode)
        }
        .sheet(isPresented: $showingUnlock) {
            WalletUnlockView()
        }
    }
}

// MARK: - Welcome View (No Wallet)

struct WalletWelcomeView: View {
    @Binding var setupMode: WalletSetupMode?
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    // Hero section
                    VStack(spacing: 8) {
                        // Icon
                        Image(systemName: "wallet.bifold")
                            .font(.system(size: 56))
                            .foregroundStyle(.linearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        
                        Text("Stori Wallet")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.linearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                        
                        Text("Secure. Powerful. Self-Custodial.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 12)
                    
                    Spacer()
                        .frame(height: 10)
                    
                    // Feature grid - 3 columns
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 10) {
                        WalletFeatureCard(
                            icon: "lock.shield.fill",
                            iconColor: .green,
                            title: "Secure Storage",
                            description: "Keys stored in macOS Keychain with biometric protection"
                        )
                        
                        WalletFeatureCard(
                            icon: "key.fill",
                            iconColor: .blue,
                            title: "BIP-32/39/44 HD Wallet",
                            description: "Industry-standard hierarchical deterministic wallet"
                        )
                        
                        WalletFeatureCard(
                            icon: "signature",
                            iconColor: .purple,
                            title: "Local Signing",
                            description: "Sign transactions without exposing private keys"
                        )
                        
                        WalletFeatureCard(
                            icon: "photo.stack.fill",
                            iconColor: .orange,
                            title: "Music NFT Portfolio",
                            description: "View and manage your STEM NFT collection"
                        )
                        
                        WalletFeatureCard(
                            icon: "bitcoinsign.circle.fill",
                            iconColor: .yellow,
                            title: "TUS Token Balance",
                            description: "Track your TUS tokens on Stori L1"
                        )
                        
                        WalletFeatureCard(
                            icon: "doc.text.fill",
                            iconColor: .cyan,
                            title: "24-Word Recovery",
                            description: "Secure backup with mnemonic phrase"
                        )
                        
                        WalletFeatureCard(
                            icon: "bolt.fill",
                            iconColor: .pink,
                            title: "Fast L1 Transactions",
                            description: "Near-instant transfers on Avalanche"
                        )
                        
                        WalletFeatureCard(
                            icon: "qrcode",
                            iconColor: .indigo,
                            title: "EIP-681 Payments",
                            description: "Standard QR code payments"
                        )
                        
                        WalletFeatureCard(
                            icon: "clock.arrow.circlepath",
                            iconColor: .teal,
                            title: "Transaction History",
                            description: "Complete on-chain transaction records"
                        )
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                        .frame(height: 12)
                    
                    // CTA Section - 3 buttons aligned with columns
                    HStack(spacing: 12) {
                        // Create New Button
                        Button(action: {
                            setupMode = .create
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                Text("Create New")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(color: .blue.opacity(0.4), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        
                        // Import Mnemonic Button
                        Button(action: {
                            setupMode = .importMnemonic
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 22))
                                Text("Import Mnemonic")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.controlBackgroundColor).opacity(0.8))
                            .foregroundColor(.primary)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Import Private Key Button
                        Button(action: {
                            setupMode = .importPrivateKey
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 22))
                                Text("Import Private Key")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.controlBackgroundColor).opacity(0.8))
                            .foregroundColor(.primary)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                        .frame(height: 12)
                }
                .frame(width: geometry.size.width)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Wallet Feature Card Component

struct WalletFeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 10) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
            }
            
            // Content
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.controlBackgroundColor).opacity(isHovered ? 1 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(iconColor.opacity(0.2), lineWidth: 1.5)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}


// MARK: - Locked View

struct WalletLockedView: View {
    @Binding var showingUnlock: Bool
    private let walletService = WalletService.shared
    @State private var showingResetConfirmation = false
    @State private var resetError: String?
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    // Hero section
                    VStack(spacing: 8) {
                        // Lock icon with gradient
                        Image(systemName: "lock.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.linearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        
                        Text("Wallet Locked")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.linearGradient(
                                colors: [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                        
                        Text("Unlock to access your tokens and NFTs")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 12)
                    
                    Spacer()
                        .frame(height: 10)
                    
                    // Feature grid - 3 columns (same as WalletWelcomeView)
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 10) {
                        WalletFeatureCard(
                            icon: "lock.shield.fill",
                            iconColor: .green,
                            title: "Secure Storage",
                            description: "Keys stored in macOS Keychain with biometric protection"
                        )
                        
                        WalletFeatureCard(
                            icon: "key.fill",
                            iconColor: .blue,
                            title: "BIP-32/39/44 HD Wallet",
                            description: "Industry-standard hierarchical deterministic wallet"
                        )
                        
                        WalletFeatureCard(
                            icon: "signature",
                            iconColor: .purple,
                            title: "Local Signing",
                            description: "Sign transactions without exposing private keys"
                        )
                        
                        WalletFeatureCard(
                            icon: "photo.stack.fill",
                            iconColor: .orange,
                            title: "Music NFT Portfolio",
                            description: "View and manage your STEM NFT collection"
                        )
                        
                        WalletFeatureCard(
                            icon: "bitcoinsign.circle.fill",
                            iconColor: .yellow,
                            title: "TUS Token Balance",
                            description: "Track your TUS tokens on Stori L1"
                        )
                        
                        WalletFeatureCard(
                            icon: "doc.text.fill",
                            iconColor: .cyan,
                            title: "24-Word Recovery",
                            description: "Secure backup with mnemonic phrase"
                        )
                        
                        WalletFeatureCard(
                            icon: "bolt.fill",
                            iconColor: .pink,
                            title: "Fast L1 Transactions",
                            description: "Near-instant transfers on Avalanche"
                        )
                        
                        WalletFeatureCard(
                            icon: "qrcode",
                            iconColor: .indigo,
                            title: "EIP-681 Payments",
                            description: "Standard QR code payments"
                        )
                        
                        WalletFeatureCard(
                            icon: "clock.arrow.circlepath",
                            iconColor: .teal,
                            title: "Transaction History",
                            description: "Complete on-chain transaction records"
                        )
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                        .frame(height: 12)
                    
                    // Error message if any
                    if let error = resetError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal, 40)
                    }
                    
                    // CTA Section - Unlock and Reset buttons
                    HStack(spacing: 12) {
                        // Unlock Wallet Button (Primary)
                        Button(action: { showingUnlock = true }) {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 18))
                                Text("Unlock Wallet")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(color: .blue.opacity(0.4), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        
                        // Reset Wallet Button (Destructive)
                        Button(action: { showingResetConfirmation = true }) {
                            HStack(spacing: 10) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 16))
                                Text("Reset Wallet")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.controlBackgroundColor).opacity(0.8))
                            .foregroundColor(.red)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.red.opacity(0.3), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                        .frame(height: 12)
                }
                .frame(width: geometry.size.width)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Reset Wallet?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetWallet()
            }
        } message: {
            Text("This will permanently delete your wallet from this device. Make sure you have your recovery phrase backed up, or you will lose access to your funds forever.")
        }
    }
    
    private func resetWallet() {
        do {
            try walletService.deleteWallet()
            resetError = nil
        } catch {
            resetError = error.localizedDescription
        }
    }
}

// MARK: - Unlock View

struct WalletUnlockView: View {
    @Environment(\.dismiss) private var dismiss
    private let walletService = WalletService.shared
    @State private var password = ""
    @State private var isUnlocking = false
    @State private var errorMessage: String?
    @State private var showingResetConfirmation = false
    
    // Development mode: allow empty password
    #if DEBUG
    private let passwordRequired = false
    #else
    private let passwordRequired = true
    #endif
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                
                Text("Unlock Wallet")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            // Password field
            VStack(spacing: 8) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .onSubmit { unlock() }
                
                #if DEBUG
                Text("Dev Mode: Password is optional")
                    .font(.caption)
                    .foregroundColor(.orange)
                #endif
            }
            
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                }
                .foregroundColor(.red)
                .font(.caption)
            }
            
            // Action buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button(isUnlocking ? "Unlocking..." : "Unlock") {
                    unlock()
                }
                .keyboardShortcut(.return)
                .disabled(isUnlocking)
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Reset option
            Button(action: { showingResetConfirmation = true }) {
                Label("Reset Wallet", systemImage: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .frame(width: 400)
        .alert("Reset Wallet?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetWallet()
            }
        } message: {
            Text("This will permanently delete your wallet. Make sure you have your recovery phrase backed up!")
        }
    }
    
    private func unlock() {
        isUnlocking = true
        errorMessage = nil
        
        Task {
            do {
                // In DEBUG mode, try with empty password first, then with entered password
                #if DEBUG
                if password.isEmpty {
                    // Try to unlock with a default dev password
                    try await walletService.unlockDev()
                } else {
                    try await walletService.unlock(password: password)
                }
                #else
                try await walletService.unlock(password: password)
                #endif
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Incorrect password"
                    isUnlocking = false
                }
            }
        }
    }
    
    private func resetWallet() {
        do {
            try walletService.deleteWallet()
            // Clear any error state
            errorMessage = nil
            password = ""
            // Dismiss the sheet - WalletView will now show welcome screen
            dismiss()
        } catch {
            errorMessage = "Failed to reset: \(error.localizedDescription)"
        }
    }
}

// MARK: - Dashboard View

struct WalletDashboardView: View {
    private let walletService = WalletService.shared
    private let nftService = NFTService.shared
    @Bindable private var txHistoryService = TransactionHistoryService.shared
    @State private var selectedTab: NFTTab = .stems
    @State private var isBalanceVisible = true
    @State private var copiedAddress = false
    @State private var showSendModal = false
    @State private var showReceiveModal = false
    @State private var showRoyaltyDashboard = false
    @State private var showAccountsManager = false
    @State private var showAddressBook = false
    @State private var showTokenApprovals = false
    @State private var showExportOptions = false
    
    enum NFTTab: String, CaseIterable {
        case stems = "STEMs"
        case digitalMasters = "Digital Masters"
    }
    
    // Premium gradient colors
    private let primaryGradient = LinearGradient(
        colors: [hexColor("6366F1"), hexColor("8B5CF6"), hexColor("A855F7")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private let cardGradient = LinearGradient(
        colors: [hexColor("1E1E2E"), hexColor("2D2D3F")],
        startPoint: .top,
        endPoint: .bottom
    )
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    // Main content column (70%)
                    VStack(spacing: 20) {
                        // Portfolio Overview
                        portfolioOverviewCard
                        
                        // Quick Actions Grid
                        quickActionsGrid
                        
                        // Assets & Holdings
                        assetsSection
                        
                        // NFT Collection
                        nftSection
                        
                        // Transaction History
                        transactionHistorySection
                    }
                    .frame(width: geometry.size.width * 0.68)
                    
                    // Sidebar column (30%)
                    VStack(spacing: 20) {
                        // Network Status Card
                        networkStatusCard
                        
                        // Wallet Info Card
                        walletInfoCard
                        
                        // Security Features Card
                        securityFeaturesCard
                        
                        // Quick Stats Card
                        quickStatsCard
                    }
                    .frame(width: geometry.size.width * 0.29)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await walletService.refreshBalance()
            if let address = walletService.address {
                await nftService.fetchNFTs(for: address)
                await txHistoryService.fetchTransactions(for: address)
            }
        }
        .sheet(isPresented: $showSendModal) {
            SendTUSModal(isPresented: $showSendModal)
                .frame(minWidth: 480, minHeight: 500)
        }
        .sheet(isPresented: $showReceiveModal) {
            ReceiveModal(isPresented: $showReceiveModal, address: walletService.address ?? "")
                .frame(minWidth: 400, minHeight: 450)
        }
        .sheet(isPresented: $showRoyaltyDashboard) {
            RoyaltyDashboardView()
        }
        .sheet(isPresented: $showAccountsManager) {
            AccountsManagerView()
        }
        .sheet(isPresented: $showAddressBook) {
            AddressBookSheet { _ in
                // Handle address selection if needed
            }
        }
        .sheet(isPresented: $showTokenApprovals) {
            TokenApprovalsView()
        }
    }
    
    // MARK: - Portfolio Overview Card
    
    private var portfolioOverviewCard: some View {
        VStack(spacing: 0) {
            // Main card content with gradient background
            VStack(spacing: 18) {
                // Header row
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Portfolio Value")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        HStack(spacing: 8) {
                            if walletService.isLoadingBalance {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                BreathingText(
                                    isBalanceVisible ? walletService.formattedBalance : "••••••",
                                    font: .system(size: 40, weight: .bold, design: .rounded),
                                    color: .white
                                )
                                .contentTransition(.numericText())
                                .balanceGlow(isUpdating: walletService.isLoadingBalance)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Visibility toggle
                    Button(action: { withAnimation(.spring(response: 0.3)) { isBalanceVisible.toggle() } }) {
                        Image(systemName: isBalanceVisible ? "eye" : "eye.slash")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(10)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isBalanceVisible ? "Hide balance" : "Show balance")
                    .accessibilityHint("Toggles wallet balance visibility")
                }
                
                // Portfolio stats grid
                HStack(spacing: 12) {
                    PortfolioStatCard(
                        icon: "arrow.up.right",
                        label: "TUS Tokens",
                        value: isBalanceVisible ? walletService.formattedBalance.replacingOccurrences(of: " TUS", with: "") : "••••",
                        trend: nil
                    )
                    
                    PortfolioStatCard(
                        icon: "photo.stack",
                        label: "NFTs Owned",
                        value: "\(nftService.portfolio.stems.count + nftService.portfolio.digitalMasters.count)",
                        trend: nil
                    )
                    
                    PortfolioStatCard(
                        icon: "waveform",
                        label: "STEM NFTs",
                        value: "\(nftService.portfolio.stems.count)",
                        trend: nil
                    )
                    
                    PortfolioStatCard(
                        icon: "doc.richtext",
                        label: "Masters",
                        value: "\(nftService.portfolio.digitalMasters.count)",
                        trend: nil
                    )
                }
                
                // Address bar
                HStack(spacing: 12) {
                    Image(systemName: "wallet.pass")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text(formatAddress(walletService.address ?? ""))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.95))
                    
                    Spacer()
                    
                    Button(action: copyAddress) {
                        HStack(spacing: 4) {
                            Image(systemName: copiedAddress ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            Text(copiedAddress ? "Copied!" : "Copy")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.black.opacity(0.2))
                .cornerRadius(10)
            }
            .padding(20)
            .background(
                ZStack {
                    primaryGradient
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                }
                .portfolioShimmer()  // Subtle animated shimmer
            )
            .cornerRadius(16)
            .portfolioPulseGlow()  // Pulsing shadow glow
            
            // SECURITY: Dev key warning removed - no hardcoded keys in codebase
        }
    }
    
    // MARK: - Quick Actions Grid
    
    private var quickActionsGrid: some View {
        VStack(spacing: 12) {
            // Row 1: Primary actions
            HStack(spacing: 12) {
                QuickActionCard(
                    icon: "arrow.up.right",
                    title: "Send",
                    subtitle: "Transfer TUS",
                    color: hexColor("3B82F6")
                ) {
                    showSendModal = true
                }
                
                QuickActionCard(
                    icon: "arrow.down.left",
                    title: "Receive",
                    subtitle: "Get address",
                    color: hexColor("10B981")
                ) {
                    showReceiveModal = true
                }
                
                QuickActionCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Royalties",
                    subtitle: "View earnings",
                    color: hexColor("F59E0B")
                ) {
                    showRoyaltyDashboard = true
                }
                
                QuickActionCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Refresh",
                    subtitle: "Sync balance",
                    color: hexColor( "8B5CF6")
                ) {
                    Task { await walletService.refreshBalance() }
                }
            }
            
            // Row 2: Secondary actions
            HStack(spacing: 12) {
                QuickActionCard(
                    icon: "person.3.fill",
                    title: "Accounts",
                    subtitle: "Manage accounts",
                    color: hexColor("6366F1")
                ) {
                    showAccountsManager = true
                }
                
                QuickActionCard(
                    icon: "book.fill",
                    title: "Contacts",
                    subtitle: "Address book",
                    color: hexColor("EC4899")
                ) {
                    showAddressBook = true
                }
                
                QuickActionCard(
                    icon: "checkmark.shield.fill",
                    title: "Approvals",
                    subtitle: "Token security",
                    color: hexColor("F59E0B")
                ) {
                    showTokenApprovals = true
                }
                
                QuickActionCard(
                    icon: "lock.fill",
                    title: "Lock",
                    subtitle: "Secure wallet",
                    color: hexColor( "EF4444")
                ) {
                    walletService.lock()
                }
            }
        }
    }
    
    private func formatAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return "\(address.prefix(10))•••\(address.suffix(6))"
    }
    
    private func copyAddress() {
        if let address = walletService.address {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address, forType: .string)
            
            withAnimation(.spring(response: 0.3)) {
                copiedAddress = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.spring(response: 0.3)) {
                    copiedAddress = false
                }
            }
        }
    }
    
    // MARK: - Transaction History Section
    
    private var transactionHistorySection: some View {
        PremiumSectionCard(
            title: "Activity",
            icon: "clock.arrow.circlepath",
            iconColor: hexColor( "F59E0B"),
            isLoading: txHistoryService.isLoading,
            onRefresh: refreshTransactions
        ) {
            VStack(spacing: 16) {
                // Filters
                PremiumFilterBar(filter: $txHistoryService.filter)
                
                // Transaction list
                if let error = txHistoryService.error {
                    PremiumErrorView(
                        icon: "exclamationmark.triangle",
                        title: "Unable to Load Activity",
                        message: error,
                        color: .orange
                    )
                } else if txHistoryService.filteredTransactions.isEmpty && !txHistoryService.isLoading {
                    PremiumEmptyView(
                        icon: "clock.badge.questionmark",
                        title: "No Activity Yet",
                        message: "Your transactions will appear here once you start using your wallet"
                    )
                } else {
                    PremiumTransactionList(
                        transactions: txHistoryService.filteredTransactions,
                        currentAddress: walletService.address ?? ""
                    )
                }
            }
        }
    }
    
    private func refreshTransactions() {
        Task {
            if let address = walletService.address {
                await txHistoryService.fetchTransactions(for: address)
            }
        }
    }
    
    private var nftSection: some View {
        PremiumSectionCard(
            title: "Your Collection",
            icon: "square.stack.3d.up",
            iconColor: hexColor( "8B5CF6"),
            isLoading: nftService.portfolio.isLoading,
            onRefresh: refreshNFTs
        ) {
            VStack(spacing: 16) {
                // Premium tab picker
                HStack(spacing: 4) {
                    ForEach(NFTTab.allCases, id: \.self) { tab in
                        PremiumTabButton(
                            title: tab.rawValue,
                            icon: tab == .stems ? "waveform" : "doc.richtext",
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedTab = tab
                            }
                        }
                    }
                }
                .padding(4)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(12)
                
                // NFT content
                if let error = nftService.portfolio.error {
                    PremiumErrorView(
                        icon: "wifi.slash",
                        title: "Connection Error",
                        message: "Unable to fetch NFTs. Check your network connection.",
                        color: .orange
                    )
                } else if nftService.portfolio.isEmpty && !nftService.portfolio.isLoading {
                    PremiumEmptyView(
                        icon: selectedTab == .stems ? "waveform.badge.plus" : "doc.badge.plus",
                        title: "No \(selectedTab.rawValue) Yet",
                        message: selectedTab == .stems
                            ? "Create and mint STEMs from your DAW projects"
                            : "Tokenize your projects to create Digital Masters"
                    )
                } else {
                    switch selectedTab {
                    case .stems:
                        PremiumSTEMGrid(stems: nftService.portfolio.stems)
                    case .digitalMasters:
                        PremiumMasterList(masters: nftService.portfolio.digitalMasters)
                    }
                }
            }
        }
    }
    
    private func refreshNFTs() {
        Task {
            if let address = walletService.address {
                await nftService.fetchNFTs(for: address)
            }
        }
    }
    
    // MARK: - Assets Section
    
    private var assetsSection: some View {
        PremiumSectionCard(
            title: "Assets",
            icon: "bitcoinsign.circle",
            iconColor: hexColor("F59E0B"),
            isLoading: false,
            onRefresh: { Task { await walletService.refreshBalance() } }
        ) {
            VStack(spacing: 12) {
                AssetRow(
                    icon: "t.circle.fill",
                    name: "TellUrStori Token",
                    symbol: "TUS",
                    balance: walletService.formattedBalance,
                    value: isBalanceVisible ? walletService.formattedBalance : "••••",
                    change: nil,
                    color: .purple,
                    isVisible: isBalanceVisible
                )
            }
        }
    }
    
    // MARK: - Sidebar Cards
    
    private var networkStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "network")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    Text("Network")
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
            }
            
            VStack(spacing: 12) {
                WalletInfoRow(label: "Network", value: walletService.selectedNetwork.displayName)
                
                // Network status with pulse animation
                HStack {
                    Text("Status")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    NetworkStatusPulse(status: .connected)
                }
                
                WalletInfoRow(label: "Chain ID", value: "\(walletService.selectedNetwork.chainId)")
                
                // Network switcher
                Menu {
                    ForEach(BlockchainNetwork.allCases) { network in
                        Button(action: {
                            Task { await walletService.switchNetwork(network) }
                        }) {
                            HStack {
                                Text(network.displayName)
                                if network == walletService.selectedNetwork {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Switch Network")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var walletInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    Text("Wallet Info")
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
            }
            
            VStack(spacing: 12) {
                WalletInfoRow(label: "Type", value: "HD Wallet")
                WalletInfoRow(label: "Standard", value: "BIP-32/39/44")
                WalletInfoRow(label: "Address", value: walletService.shortAddress ?? "N/A")
                
                Button(action: {
                    if let address = walletService.address {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(address, forType: .string)
                        withAnimation { copiedAddress = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { copiedAddress = false }
                        }
                    }
                }) {
                    HStack {
                        Text(copiedAddress ? "Address Copied!" : "Copy Full Address")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Image(systemName: copiedAddress ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(copiedAddress ? .green : .accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background((copiedAddress ? Color.green : Color.accentColor).opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Account switcher (if HD wallet)
                if walletService.wallet is HDWallet {
                    Divider()
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        AccountSwitcher()
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var securityFeaturesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "lock.shield")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    Text("Security")
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
            }
            
            VStack(spacing: 10) {
                SecurityFeatureRow(icon: "checkmark.shield.fill", label: "Keychain Storage", status: true)
                SecurityFeatureRow(icon: "faceid", label: "Biometric Auth", status: true)
                SecurityFeatureRow(icon: "lock.rotation", label: "Auto-Lock", status: true)
                SecurityFeatureRow(icon: "signature", label: "Local Signing", status: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var quickStatsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "chart.bar")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.purple)
                    }
                    Text("Quick Stats")
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
            }
            
            VStack(spacing: 10) {
                StatRow(label: "Total Transactions", value: "\(txHistoryService.filteredTransactions.count)")
                StatRow(label: "Total NFTs", value: "\(nftService.portfolio.stems.count + nftService.portfolio.digitalMasters.count)")
                StatRow(label: "STEM NFTs", value: "\(nftService.portfolio.stems.count)")
                StatRow(label: "Digital Masters", value: "\(nftService.portfolio.digitalMasters.count)")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
}

// MARK: - Premium Components

/// Portfolio stat card for overview
struct PortfolioStatCard: View {
    let icon: String
    let label: String
    let value: String
    let trend: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            if let trend = trend {
                Text(trend)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(trend.hasPrefix("+") ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }
}

/// Asset row for token holdings
struct AssetRow: View {
    let icon: String
    let name: String
    let symbol: String
    let balance: String
    let value: String
    let change: String?
    let color: Color
    let isVisible: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                Text(symbol)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 3) {
                Text(isVisible ? balance : "••••")
                    .font(.system(size: 14, weight: .semibold))
                if let change = change {
                    Text(change)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(change.hasPrefix("+") ? .green : .red)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}

/// Info row for sidebar cards
struct WalletInfoRow: View {
    let label: String
    let value: String
    var color: Color?
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color ?? .primary)
        }
    }
}

/// Security feature row with status indicator
struct SecurityFeatureRow: View {
    let icon: String
    let label: String
    let status: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(status ? .green : .secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.primary)
            
            Spacer()
            
            Circle()
                .fill(status ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
        }
    }
}

/// Stat row for quick stats card
struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
        }
    }
}

/// Quick action card with icon, title, and hover effect
struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.controlBackgroundColor).opacity(isHovered ? 1 : 0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(color.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1.5)
                    )
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("\(title): \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Premium section card container
struct PremiumSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let isLoading: Bool
    let onRefresh: () -> Void
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(iconColor)
                    }
                    
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Premium tab button
struct PremiumTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? hexColor( "8B5CF6") : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Premium filter bar for transactions
struct PremiumFilterBar: View {
    @Binding var filter: TxHistoryFilter
    
    var body: some View {
        HStack(spacing: 12) {
            // Type filter
            Menu {
                ForEach(TxHistoryType.allCases) { type in
                    Button(action: { filter.type = type }) {
                        Label(type.rawValue, systemImage: type.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: filter.type.icon)
                        .font(.system(size: 11))
                    Text(filter.type.rawValue)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // Date filter
            Menu {
                ForEach(TxHistoryFilter.DateRange.allCases) { range in
                    Button(action: { filter.dateRange = range }) {
                        Text(range.rawValue)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(filter.dateRange.rawValue)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                TextField("Search", text: $filter.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 120)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

/// Premium error view
struct PremiumErrorView: View {
    let icon: String
    let title: String
    let message: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 64, height: 64)
                
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(color.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
        )
    }
}

/// Premium empty view
struct PremiumEmptyView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 64, height: 64)
                
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
        )
    }
}

/// Premium STEM grid
struct PremiumSTEMGrid: View {
    let stems: [STEMNFT]
    
    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 16)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(stems) { stem in
                PremiumSTEMCard(stem: stem)
            }
        }
    }
}

/// Premium STEM card
struct PremiumSTEMCard: View {
    let stem: STEMNFT
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image area
            ZStack {
                if let imageURL = stem.imageURL() {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            waveformVisual
                        }
                    }
                } else {
                    waveformVisual
                }
                
                // Play overlay on hover
                if isHovered {
                    Color.black.opacity(0.3)
                    
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                        .shadow(radius: 10)
                }
            }
            .frame(height: 140)
            .clipped()
            
            // Info area
            VStack(alignment: .leading, spacing: 10) {
                Text(stem.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                HStack {
                    Label(stem.genre, systemImage: "music.note")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(stem.formattedDuration)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("×\(stem.totalSupply)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(hexColor( "8B5CF6"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(hexColor( "8B5CF6").opacity(0.1))
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Text("#\(stem.tokenId)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
        )
        .holographicShimmer(isHovered: isHovered)  // Holographic effect on hover
        .parallaxTilt(intensity: 0.8)  // Parallax 3D tilt effect
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var waveformVisual: some View {
        ZStack {
            LinearGradient(
                colors: [hexColor( "6366F1").opacity(0.2), hexColor( "8B5CF6").opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Waveform bars
            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 4, height: CGFloat(20 + (i % 5) * 10))
                }
            }
        }
    }
}

/// Premium Digital Master list
struct PremiumMasterList: View {
    let masters: [DigitalMasterNFT]
    
    var body: some View {
        VStack(spacing: 10) {
            ForEach(masters) { master in
                PremiumMasterRow(master: master)
            }
        }
    }
}

/// Premium Digital Master row
struct PremiumMasterRow: View {
    let master: DigitalMasterNFT
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Album art / Icon
            ZStack {
                if let imageURL = master.imageURL() {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            masterPlaceholder
                        @unknown default:
                            masterPlaceholder
                        }
                    }
                } else {
                    masterPlaceholder
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(master.title)
                    .font(.system(size: 14, weight: .semibold))
                
                HStack(spacing: 8) {
                    Label("\(master.owners.count) owner\(master.owners.count == 1 ? "" : "s")", systemImage: "person.2")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Label("\(master.royaltyPercentage)%", systemImage: "percent")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if master.isLocked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text("Locked")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(hexColor( "10B981"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(hexColor( "10B981").opacity(0.1))
                    .cornerRadius(6)
                }
                
                Text("#\(master.tokenId)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(isHovered ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var masterPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [hexColor("8B5CF6"), hexColor("A855F7")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "doc.richtext")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

/// Premium transaction list
struct PremiumTransactionList: View {
    let transactions: [TxHistoryEntry]
    let currentAddress: String
    
    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(transactions) { tx in
                PremiumTransactionRow(transaction: tx, currentAddress: currentAddress)
            }
        }
    }
}

/// Premium transaction row
struct PremiumTransactionRow: View {
    let transaction: TxHistoryEntry
    let currentAddress: String
    @State private var isHovered = false
    @State private var isExpanded = false
    
    private var isSend: Bool {
        transaction.from.lowercased() == currentAddress.lowercased()
    }
    
    private var isPurchase: Bool {
        transaction.type == .purchase
    }
    
    private var counterparty: String {
        isSend ? (transaction.to ?? "Contract") : transaction.from
    }
    
    // Color based on transaction type
    private var transactionColor: Color {
        if isPurchase {
            return hexColor("8B5CF6")  // Purple for purchases
        } else if isSend {
            return hexColor("EF4444")  // Red for sends
        } else {
            return hexColor("10B981")  // Green for receives
        }
    }
    
    // Icon based on transaction type
    private var transactionIcon: String {
        switch transaction.type {
        case .purchase:
            return "cart.fill"
        case .send:
            return "arrow.up.right"
        case .receive:
            return "arrow.down.left"
        case .nftMint:
            return "sparkles"
        case .contractCall:
            return "gearshape.fill"
        case .all:
            return "arrow.left.arrow.right"
        }
    }
    
    // Title based on transaction type
    private var transactionTitle: String {
        switch transaction.type {
        case .purchase:
            return "Purchase"
        case .send:
            return "Sent"
        case .receive:
            return "Received"
        case .nftMint:
            return "Minted"
        case .contractCall:
            return "Contract"
        case .all:
            return "Transaction"
        }
    }
    
    // Subtitle - for purchases show the license info, otherwise show address
    private var transactionSubtitle: String {
        if isPurchase, let tokenAmount = transaction.tokenAmount {
            return tokenAmount
        }
        return truncateAddress(counterparty)
    }
    
    // Border color for quick visual scanning
    private var borderColor: TransactionBorderColor {
        switch transaction.type {
        case .purchase, .nftMint:
            return .nft
        case .send:
            return .send
        case .receive:
            return .receive
        case .contractCall, .all:
            return .contract
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Direction indicator
                ZStack {
                    Circle()
                        .fill(transactionColor.opacity(0.1))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: transactionIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(transactionColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(transactionTitle)
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text(transactionSubtitle)
                        .font(.system(size: 12, design: isPurchase ? .default : .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(isSend || isPurchase ? "-" : "+")\(transaction.formattedValue)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(transactionColor)
                    
                    Text(formatRelativeTime(transaction.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            
            if isExpanded {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 1)
                    
                    VStack(spacing: 10) {
                        TxDetailRow(label: "Hash", value: transaction.truncatedHash, isMonospace: true)
                        TxDetailRow(label: "Block", value: "#\(transaction.blockNumber)")
                        
                        if isPurchase {
                            if let tokenId = transaction.tokenId {
                                TxDetailRow(label: "License ID", value: "#\(tokenId)")
                            }
                        }
                        
                        if let gasCost = transaction.formattedGasCost {
                            TxDetailRow(label: "Fee", value: gasCost)
                        }
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.03))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(isHovered ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .transactionBorder(borderColor)  // Color-coded left border for visual scanning
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(8))...\(address.suffix(4))"
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct TxDetailRow: View {
    let label: String
    let value: String
    var isMonospace: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: isMonospace ? .monospaced : .default))
        }
    }
}

// MARK: - Helper for Hex Colors

/// Creates a Color from a hex string, with fallback to black
private func hexColor(_ hex: String) -> Color {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default: (a, r, g, b) = (255, 0, 0, 0)
    }
    return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
}

// MARK: - Send TUS Modal

struct SendTUSModal: View {
    @Binding var isPresented: Bool
    private let walletService = WalletService.shared
    
    @State private var recipientAddress = ""
    @State private var amount = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var txHash: String?
    @State private var showConfirmation = false
    
    // Gas controls
    @State private var gasMode: GasControls.GasControlMode = .simple
    @State private var gasSpeed: GasSpeed = .standard
    @State private var maxFeePerGas = "50"
    @State private var maxPriorityFee = "2"
    @State private var gasLimit = "21000"
    
    private var isValidAddress: Bool {
        recipientAddress.hasPrefix("0x") && recipientAddress.count == 42
    }
    
    private var parsedAmount: BigUInt? {
        guard let decimalAmount = Double(amount), decimalAmount > 0 else { return nil }
        // Convert to wei (18 decimals)
        let weiString = String(format: "%.0f", decimalAmount * 1e18)
        return BigUInt(weiString)
    }
    
    private var canSend: Bool {
        isValidAddress && parsedAmount != nil && !isSending
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            modalHeader
            
            Divider()
            
            if txHash != nil {
                successView
            } else if showConfirmation {
                confirmationView
            } else {
                inputView
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var modalHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Send TUS")
                    .font(.system(size: 20, weight: .bold))
                
                Text("Transfer tokens to another address")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }
    
    private var inputView: some View {
        VStack(spacing: 24) {
            // Available balance
            HStack {
                Text("Available Balance")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(walletService.formattedBalance)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(16)
            .background(hexColor("8B5CF6").opacity(0.1))
            .cornerRadius(12)
            
            // Recipient address (with validation and address book)
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipient Address")
                    .font(.system(size: 13, weight: .medium))
                
                ValidatedAddressField(address: $recipientAddress) { address in
                    recipientAddress = address
                }
            }
            
            // Amount
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount")
                    .font(.system(size: 13, weight: .medium))
                
                HStack(spacing: 12) {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                    
                    TextField("0.00", text: $amount)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    
                    Text("TUS")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Button(action: setMaxAmount) {
                        Text("MAX")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(hexColor("8B5CF6"))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(12)
            }
            
            // Gas controls
            GasControls(
                mode: $gasMode,
                simpleSpeed: $gasSpeed,
                maxFeePerGas: $maxFeePerGas,
                maxPriorityFee: $maxPriorityFee,
                gasLimit: $gasLimit
            )
            
            if let error = error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(hexColor("EF4444"))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(hexColor("EF4444"))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hexColor("EF4444").opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("Continue") {
                    withAnimation(.spring(response: 0.3)) {
                        showConfirmation = true
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSend)
            }
        }
        .padding(24)
    }
    
    private var confirmationView: some View {
        VStack(spacing: 24) {
            // Summary card
            VStack(spacing: 16) {
                // Amount
                VStack(spacing: 4) {
                    Text("You're sending")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text("\(amount) TUS")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(hexColor("8B5CF6"))
                }
                
                Image(systemName: "arrow.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.secondary)
                
                // Recipient
                VStack(spacing: 4) {
                    Text("To")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text(formatConfirmAddress(recipientAddress))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(hexColor("8B5CF6").opacity(0.3), lineWidth: 1)
                    )
            )
            
            // Transaction simulation
            if let simulation = simulateTransaction() {
                TransactionSimulationView(simulation: simulation)
            }
            
            // Network info
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)
                
                Text("Network: \(walletService.selectedNetwork.displayName)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("~21,000 gas")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(8)
            
            if let error = error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(hexColor("EF4444"))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(hexColor("EF4444"))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hexColor("EF4444").opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Back") {
                    withAnimation(.spring(response: 0.3)) {
                        showConfirmation = false
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isSending)
                
                Button(action: sendTransaction) {
                    HStack(spacing: 8) {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isSending ? "Sending..." : "Confirm & Send")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSending)
            }
        }
        .padding(24)
    }
    
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Success icon
            ZStack {
                Circle()
                    .fill(hexColor("10B981").opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(hexColor("10B981"))
            }
            
            VStack(spacing: 8) {
                Text("Transaction Sent!")
                    .font(.system(size: 24, weight: .bold))
                
                Text("\(amount) TUS sent successfully")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            
            // Transaction hash
            if let hash = txHash {
                VStack(spacing: 8) {
                    Text("Transaction Hash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("\(hash.prefix(10))...\(hash.suffix(8))")
                            .font(.system(size: 13, design: .monospaced))
                        
                        Button(action: { copyToClipboard(hash) }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            
            Spacer()
            
            Button("Done") {
                isPresented = false
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
    }
    
    private func setMaxAmount() {
        let balance = walletService.balance
        // Leave some gas buffer (0.01 TUS)
        let gasBuffer = BigUInt(10000000000000000) // 0.01 TUS
        if balance > gasBuffer {
            let sendable = balance - gasBuffer
            let tusAmount = Double(sendable) / 1e18
            amount = String(format: "%.4f", tusAmount)
        }
    }
    
    private func formatConfirmAddress(_ addr: String) -> String {
        guard addr.count > 20 else { return addr }
        return "\(addr.prefix(14))...\(addr.suffix(10))"
    }
    
    private func sendTransaction() {
        guard let amountWei = parsedAmount else { return }
        
        isSending = true
        error = nil
        
        Task {
            do {
                let hash = try await walletService.sendTUS(to: recipientAddress, amount: amountWei)
                await MainActor.run {
                    txHash = hash
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isSending = false
                }
            }
        }
    }
    
    private func simulateTransaction() -> SimulationResult? {
        guard let amountWei = parsedAmount else { return nil }
        let simulator = TransactionSimulator(walletService: walletService)
        return simulator.simulateTransfer(to: recipientAddress, amount: amountWei)
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Receive Modal

struct ReceiveModal: View {
    @Binding var isPresented: Bool
    let address: String
    
    @State private var copied = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Receive TUS")
                        .font(.system(size: 20, weight: .bold))
                    
                    Text("Share your address to receive tokens")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            
            Divider()
            
            VStack(spacing: 24) {
                // Real QR Code with EIP-681 format
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(width: 220, height: 220)
                        .shadow(color: Color.black.opacity(0.1), radius: 10)
                    
                    if let qrImage = generateQRCode(from: address) {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                    } else {
                        // Fallback if QR generation fails
                        VStack(spacing: 8) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("QR Code Unavailable")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
                
                // Network badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(hexColor("10B981"))
                        .frame(width: 8, height: 8)
                    
                    Text(WalletService.shared.selectedNetwork.displayName)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(20)
                
                // Address
                VStack(spacing: 12) {
                    Text("Your Wallet Address")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text(address)
                        .font(.system(size: 13, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                }
                
                // Copy button
                Button(action: copyAddress) {
                    HStack(spacing: 8) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14))
                        
                        Text(copied ? "Copied!" : "Copy Address")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(hexColor("8B5CF6"))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                // Warning
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only send tokens to this address on \(WalletService.shared.selectedNetwork.displayName)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Sending from other networks will result in permanent loss")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }
            .padding(24)
            
            Spacer()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        
        withAnimation(.spring(response: 0.3)) {
            copied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3)) {
                copied = false
            }
        }
    }
    
    // Simple deterministic pattern based on address
    /// Generate a real QR code from the wallet address using Core Image
    /// Returns an NSImage that can be scanned by any QR code reader
    private func generateQRCode(from address: String) -> NSImage? {
        // Validate address format (must start with 0x and be 42 characters)
        guard address.hasPrefix("0x"), address.count == 42 else {
            return nil
        }
        
        // Encode just the plain address for maximum compatibility
        // This works with ALL EVM-compatible wallets regardless of chain
        // The network context is clearly shown in the UI (network badge + warning text)
        let qrContent = address
        
        // Convert to Data
        guard let data = qrContent.data(using: .utf8) else {
            return nil
        }
        
        // Create QR code using Core Image
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        
        filter.setValue(data, forKey: "inputMessage")
        // Use high error correction for better scanning
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else {
            return nil
        }
        
        // Scale up the QR code for better quality
        let scaleFactor: CGFloat = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        
        // Convert CIImage to NSImage
        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        
        
        return nsImage
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnabled ? hexColor("8B5CF6") : Color.secondary.opacity(0.3))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

