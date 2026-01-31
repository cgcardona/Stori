//
//  TransactionSimulation.swift
//  Stori
//
//  Transaction simulation and preview before signing
//  Shows balance changes and warnings
//

import SwiftUI
import BigInt

// MARK: - Simulation Models

struct SimulationResult {
    let balanceAfter: BigUInt
    let balanceChange: BigUInt
    let gasEstimate: BigUInt
    let warnings: [String]
    let nftChanges: [NFTChange]
    let isSuccess: Bool
    
    struct NFTChange: Identifiable {
        let id = UUID()
        let tokenId: String
        let name: String
        let isAdded: Bool
    }
    
    var formattedBalanceAfter: String {
        let tusValue = Double(balanceAfter) / 1e18
        return String(format: "%.4f TUS", tusValue)
    }
    
    var formattedChange: String {
        let tusValue = Double(balanceChange) / 1e18
        return String(format: "%.4f TUS", tusValue)
    }
    
    var formattedGas: String {
        let tusValue = Double(gasEstimate) / 1e18
        return String(format: "%.6f TUS", tusValue)
    }
}

// MARK: - Transaction Simulator

struct TransactionSimulator {
    let walletService: WalletService
    
    /// Simulate a TUS transfer
    func simulateTransfer(to: String, amount: BigUInt) -> SimulationResult {
        var warnings: [String] = []
        let currentBalance = walletService.balance
        
        // Estimate gas (21000 for simple transfer)
        let gasEstimate = BigUInt(21000) * BigUInt(50_000_000_000) // 50 gwei
        let totalCost = amount + gasEstimate
        
        // Check if balance is sufficient
        let isSuccess = currentBalance >= totalCost
        
        if !isSuccess {
            warnings.append("Insufficient balance for transaction + gas")
        }
        
        // Warn if sending >90% of balance
        let percentageSent = (Double(amount) / Double(currentBalance)) * 100
        if percentageSent > 90 {
            warnings.append("Sending >90% of balance - consider keeping some for future gas")
        }
        
        // Check for burn address
        if to.lowercased() == "0x0000000000000000000000000000000000000000" {
            warnings.append("⚠️ WARNING: This is the burn address - tokens will be lost forever!")
        }
        
        // Calculate resulting balance
        let balanceAfter = isSuccess ? (currentBalance - totalCost) : currentBalance
        
        return SimulationResult(
            balanceAfter: balanceAfter,
            balanceChange: amount,
            gasEstimate: gasEstimate,
            warnings: warnings,
            nftChanges: [],
            isSuccess: isSuccess
        )
    }
}

// MARK: - Simulation View

struct TransactionSimulationView: View {
    let simulation: SimulationResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "wand.and.rays")
                    .font(.system(size: 16))
                    .foregroundColor(.purple)
                
                Text("Transaction Preview")
                    .font(.system(size: 14, weight: .semibold))
            }
            
            // Balance changes
            VStack(spacing: 10) {
                BalanceChangeRow(
                    label: "Current Balance",
                    value: WalletService.shared.formattedBalance,
                    color: .primary
                )
                
                BalanceChangeRow(
                    label: "Sending",
                    value: "-\(simulation.formattedChange)",
                    color: hexColor("EF4444")
                )
                
                BalanceChangeRow(
                    label: "Est. Gas Fee",
                    value: "-\(simulation.formattedGas)",
                    color: .secondary
                )
                
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                
                BalanceChangeRow(
                    label: "Balance After",
                    value: simulation.formattedBalanceAfter,
                    color: simulation.isSuccess ? hexColor("10B981") : hexColor("EF4444"),
                    isBold: true
                )
            }
            
            // Warnings
            if !simulation.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(simulation.warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: warning.contains("⚠️") ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(warning.contains("⚠️") ? .red : .orange)
                            
                            Text(warning.replacingOccurrences(of: "⚠️ ", with: ""))
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    simulation.isSuccess ? Color.secondary.opacity(0.15) : hexColor("EF4444").opacity(0.3),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Balance Change Row

struct BalanceChangeRow: View {
    let label: String
    let value: String
    let color: Color
    var isBold: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: isBold ? .semibold : .regular))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: isBold ? .bold : .semibold, design: .rounded))
                .foregroundColor(color)
        }
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
