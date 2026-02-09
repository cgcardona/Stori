//
//  RoyaltyDashboardView.swift
//  Stori
//
//  Real-time royalty earnings dashboard for creators
//  Shows earnings from STEM and Master NFT sales
//

import SwiftUI
import BigInt

// MARK: - Royalty Models

struct RoyaltyPayment: Identifiable {
    let id = UUID()
    let timestamp: Date
    let amount: BigUInt
    let source: RoyaltySource
    let assetId: String
    let assetName: String
    let transactionHash: String
    
    enum RoyaltySource {
        case stemSale
        case masterLicense
        case remix
    }
    
    var formattedAmount: String {
        let tusValue = Double(amount) / 1e18
        return String(format: "%.4f TUS", tusValue)
    }
    
    var sourceIcon: String {
        switch source {
        case .stemSale: return "waveform.circle.fill"
        case .masterLicense: return "doc.circle.fill"
        case .remix: return "arrow.triangle.branch.circle.fill"
        }
    }
    
    var sourceColor: Color {
        switch source {
        case .stemSale: return hexColor("8B5CF6")
        case .masterLicense: return hexColor("3B82F6")
        case .remix: return hexColor("10B981")
        }
    }
    
    var sourceLabel: String {
        switch source {
        case .stemSale: return "STEM Sale"
        case .masterLicense: return "Master License"
        case .remix: return "Remix"
        }
    }
}

// MARK: - Royalty Service

@MainActor
@Observable
final class RoyaltyService {
    static let shared = RoyaltyService()
    
    private(set) var totalEarned: BigUInt = 0
    private(set) var stemRoyalties: BigUInt = 0
    private(set) var masterRoyalties: BigUInt = 0
    private(set) var remixRoyalties: BigUInt = 0
    private(set) var recentPayments: [RoyaltyPayment] = []
    private(set) var isLoading = false
    
    private init() {
        // Initialize with mock data for demo
        #if DEBUG
        loadMockData()
        #endif
    }
    
    
    func fetchRoyalties(for address: String) async {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Implement actual blockchain royalty fetching
        // For now, use mock data
        #if DEBUG
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        loadMockData()
        #endif
    }
    
    #if DEBUG
    private func loadMockData() {
        // Mock data for demo
        stemRoyalties = BigUInt("250000000000000000000") ?? 0  // 250 TUS
        masterRoyalties = BigUInt("180000000000000000000") ?? 0  // 180 TUS
        remixRoyalties = BigUInt("75000000000000000000") ?? 0  // 75 TUS
        totalEarned = stemRoyalties + masterRoyalties + remixRoyalties
        
        recentPayments = [
            RoyaltyPayment(
                timestamp: Date().addingTimeInterval(-3600),
                amount: BigUInt("15000000000000000000") ?? 0,
                source: .stemSale,
                assetId: "1",
                assetName: "Midnight Groove Bass",
                transactionHash: "0x123..."
            ),
            RoyaltyPayment(
                timestamp: Date().addingTimeInterval(-7200),
                amount: BigUInt("25000000000000000000") ?? 0,
                source: .masterLicense,
                assetId: "2",
                assetName: "Summer Vibes",
                transactionHash: "0x456..."
            ),
            RoyaltyPayment(
                timestamp: Date().addingTimeInterval(-86400),
                amount: BigUInt("8000000000000000000") ?? 0,
                source: .remix,
                assetId: "3",
                assetName: "Lo-Fi Dreams (Remix)",
                transactionHash: "0x789..."
            )
        ]
    }
    #endif
    
    var formattedTotal: String {
        let tusValue = Double(totalEarned) / 1e18
        return String(format: "%.2f TUS", tusValue)
    }
    
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
}

// MARK: - Royalty Dashboard View

struct RoyaltyDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var royaltyService = RoyaltyService.shared
    private let walletService = WalletService.shared
    @State private var selectedTimeframe: Timeframe = .month
    
    enum Timeframe: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case year = "1 Year"
        case allTime = "All Time"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Royalty Dashboard")
                        .font(.title2.bold())
                    Text("Your creator earnings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: refreshRoyalties) {
                    Image(systemName: royaltyService.isLoading ? "arrow.clockwise" : "arrow.clockwise")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(royaltyService.isLoading ? 360 : 0))
                        .animation(royaltyService.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: royaltyService.isLoading)
                }
                .buttonStyle(.plain)
                .disabled(royaltyService.isLoading)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Hero stat - Total earned
                    totalEarnedCard
                    
                    // Breakdown by source
                    HStack(spacing: 16) {
                        RoyaltySourceCard(
                            title: "STEM Royalties",
                            amount: royaltyService.stemRoyalties,
                            icon: "waveform",
                            color: hexColor("8B5CF6")
                        )
                        
                        RoyaltySourceCard(
                            title: "Master Royalties",
                            amount: royaltyService.masterRoyalties,
                            icon: "doc.richtext",
                            color: hexColor("3B82F6")
                        )
                        
                        RoyaltySourceCard(
                            title: "Remix Royalties",
                            amount: royaltyService.remixRoyalties,
                            icon: "arrow.triangle.branch",
                            color: hexColor("10B981")
                        )
                    }
                    
                    // Recent payments
                    if !royaltyService.recentPayments.isEmpty {
                        recentPaymentsSection
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 800, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            if let address = walletService.address {
                await royaltyService.fetchRoyalties(for: address)
            }
        }
    }
    
    private var totalEarnedCard: some View {
        VStack(spacing: 16) {
            Text("Total Royalties Earned")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(royaltyService.formattedTotal)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [hexColor("10B981"), hexColor("3B82F6")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text("Keep creating amazing music!")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(hexColor("10B981").opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [hexColor("10B981").opacity(0.3), hexColor("3B82F6").opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
        )
    }
    
    private var recentPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Payments")
                .font(.system(size: 16, weight: .bold))
            
            VStack(spacing: 8) {
                ForEach(royaltyService.recentPayments) { payment in
                    RoyaltyPaymentRow(payment: payment)
                }
            }
        }
    }
    
    private func refreshRoyalties() {
        Task {
            if let address = walletService.address {
                await royaltyService.fetchRoyalties(for: address)
            }
        }
    }
}

// MARK: - Royalty Source Card

struct RoyaltySourceCard: View {
    let title: String
    let amount: BigUInt
    let icon: String
    let color: Color
    
    private var formattedAmount: String {
        let tusValue = Double(amount) / 1e18
        return String(format: "%.2f TUS", tusValue)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(formattedAmount)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Royalty Payment Row

struct RoyaltyPaymentRow: View {
    let payment: RoyaltyPayment
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(payment.sourceColor.opacity(0.1))
                    .frame(width: 42, height: 42)
                
                Image(systemName: payment.sourceIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(payment.sourceColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(payment.sourceLabel)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(payment.assetName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Amount and time
            VStack(alignment: .trailing, spacing: 4) {
                Text("+\(payment.formattedAmount)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(hexColor("10B981"))
                
                Text(formatRelativeTime(payment.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(isHovered ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Helper

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
