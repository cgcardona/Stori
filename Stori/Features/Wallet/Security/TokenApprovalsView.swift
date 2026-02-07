//
//  TokenApprovalsView.swift
//  Stori
//
//  View and revoke token approvals (ERC-20 allowances)
//  Critical security feature to prevent unauthorized token spending
//

import SwiftUI
import BigInt

// MARK: - Token Approval Models

struct TokenApproval: Identifiable {
    let id = UUID()
    let tokenAddress: String
    let tokenSymbol: String
    let spenderAddress: String
    var spenderLabel: String?
    let allowance: BigUInt
    let isUnlimited: Bool
    let lastUpdated: Date
    
    var truncatedSpender: String {
        guard spenderAddress.count > 14 else { return spenderAddress }
        return "\(spenderAddress.prefix(8))...\(spenderAddress.suffix(4))"
    }
    
    var formattedAmount: String {
        if isUnlimited {
            return "Unlimited"
        }
        let value = Double(allowance) / 1e18
        return String(format: "%.2f \(tokenSymbol)", value)
    }
    
    var riskLevel: RiskLevel {
        if isUnlimited {
            return .high
        } else if allowance > BigUInt(1000) * BigUInt(1e18) {
            return .medium
        } else {
            return .low
        }
    }
    
    enum RiskLevel {
        case low, medium, high
        
        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .orange
            case .high: return .red
            }
        }
        
        var label: String {
            switch self {
            case .low: return "Low Risk"
            case .medium: return "Medium Risk"
            case .high: return "High Risk"
            }
        }
    }
}

// MARK: - Token Approvals Service

@MainActor
@Observable
final class TokenApprovalsService {
    static let shared = TokenApprovalsService()
    
    private(set) var approvals: [TokenApproval] = []
    private(set) var isLoading = false
    private(set) var error: String?
    
    private init() {
        #if DEBUG
        loadMockData()
        #endif
    }
    
    func fetchApprovals(for address: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        // TODO: Implement actual approval fetching via blockchain indexer
        // For now, use mock data in DEBUG
        #if DEBUG
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        loadMockData()
        #endif
    }
    
    func revokeApproval(_ approval: TokenApproval) async throws {
        // TODO: Implement actual revocation by calling approve(spender, 0)
        // For now, just remove from list
        approvals.removeAll { $0.id == approval.id }
    }
    
    #if DEBUG
    private func loadMockData() {
        approvals = [
            TokenApproval(
                tokenAddress: "0x1234...",
                tokenSymbol: "TUS",
                spenderAddress: "0xabcd1234567890abcd1234567890abcd12345678",
                spenderLabel: "Stori Marketplace",
                allowance: BigUInt(2).power(256) - 1,  // Max uint256
                isUnlimited: true,
                lastUpdated: Date().addingTimeInterval(-86400 * 30)
            ),
            TokenApproval(
                tokenAddress: "0x1234...",
                tokenSymbol: "TUS",
                spenderAddress: "0xdef4567890abcdef4567890abcdef4567890abcd",
                spenderLabel: "Old Marketplace V1",
                allowance: BigUInt(1000) * BigUInt(1e18),
                isUnlimited: false,
                lastUpdated: Date().addingTimeInterval(-86400 * 90)
            )
        ]
    }
    #endif
    
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
}

// MARK: - Token Approvals View

struct TokenApprovalsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var approvalsService = TokenApprovalsService.shared
    private let walletService = WalletService.shared
    @State private var showingRevokeConfirmation: TokenApproval?
    @State private var isRevoking = false
    @State private var localError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Token Approvals")
                        .font(.title2.bold())
                    Text("Contracts authorized to spend your tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: refreshApprovals) {
                    Image(systemName: approvalsService.isLoading ? "arrow.clockwise" : "arrow.clockwise")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(approvalsService.isLoading ? 360 : 0))
                        .animation(approvalsService.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: approvalsService.isLoading)
                }
                .buttonStyle(.plain)
                .disabled(approvalsService.isLoading)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Info banner
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("What are token approvals?")
                        .font(.system(size: 12, weight: .semibold))
                    Text("When you use DApps, they request permission to spend your tokens. Revoke approvals you no longer use to protect your assets.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            // Content
            if approvalsService.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading approvals...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = localError ?? approvalsService.error {
                errorView(error)
            } else if approvalsService.approvals.isEmpty {
                emptyState
            } else {
                approvalsList
            }
        }
        .frame(width: 700, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            if let address = walletService.address {
                await approvalsService.fetchApprovals(for: address)
            }
        }
        .alert(item: $showingRevokeConfirmation) { approval in
            Alert(
                title: Text("Revoke Approval?"),
                message: Text("This will prevent \(approval.spenderLabel ?? "this contract") from spending your \(approval.tokenSymbol). You can always approve again later."),
                primaryButton: .destructive(Text("Revoke")) {
                    revokeApproval(approval)
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private var approvalsList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(approvalsService.approvals) { approval in
                    ApprovalRow(approval: approval) {
                        showingRevokeConfirmation = approval
                    }
                }
            }
            .padding(20)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            
            VStack(spacing: 8) {
                Text("No Active Approvals")
                    .font(.headline)
                
                Text("You haven't approved any contracts to spend your tokens yet. This is good for security!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Failed to Load Approvals")
                    .font(.headline)
                
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Try Again") {
                refreshApprovals()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func refreshApprovals() {
        Task {
            if let address = walletService.address {
                await approvalsService.fetchApprovals(for: address)
            }
        }
    }
    
    private func revokeApproval(_ approval: TokenApproval) {
        isRevoking = true
        Task {
            do {
                try await approvalsService.revokeApproval(approval)
                isRevoking = false
            } catch {
                localError = error.localizedDescription
                isRevoking = false
            }
        }
    }
}

// MARK: - Approval Row

struct ApprovalRow: View {
    let approval: TokenApproval
    let onRevoke: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Risk indicator
            VStack(spacing: 4) {
                Circle()
                    .fill(approval.riskLevel.color)
                    .frame(width: 12, height: 12)
                
                Text(approval.riskLevel.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(approval.riskLevel.color)
            }
            .frame(width: 60)
            
            // Spender info
            VStack(alignment: .leading, spacing: 4) {
                Text(approval.spenderLabel ?? approval.truncatedSpender)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(approval.truncatedSpender)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Allowance
            VStack(alignment: .trailing, spacing: 4) {
                if approval.isUnlimited {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("UNLIMITED")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.red)
                } else {
                    Text(approval.formattedAmount)
                        .font(.system(size: 13, weight: .semibold))
                }
                
                Text("Updated \(formatRelativeTime(approval.lastUpdated))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // Revoke button
            Button("Revoke") {
                onRevoke()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(isHovered ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(approval.riskLevel.color.opacity(0.2), lineWidth: 1)
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
