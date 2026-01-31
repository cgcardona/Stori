//
//  WalletStatusView.swift
//  Stori
//
//  Created by TellUrStori on 12/8/25.
//

import SwiftUI

/// Compact wallet status indicator for use in headers/toolbars
/// Shows connection status and allows quick access to wallet management
struct WalletStatusView: View {
    private let walletManager = WalletManager.shared
    @State private var showingWalletSheet = false
    
    var body: some View {
        Button {
            showingWalletSheet = true
        } label: {
            HStack(spacing: 8) {
                // Connection indicator
                Circle()
                    .fill(walletManager.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                if walletManager.isConnected {
                    // Show short address when connected
                    Text(walletManager.shortAddress)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                } else {
                    // Show connect prompt
                    Text("Connect Wallet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                walletManager.isConnected 
                                    ? Color.green.opacity(0.3) 
                                    : Color.orange.opacity(0.3),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .help(walletManager.isConnected 
              ? "Connected: \(walletManager.walletAddress)" 
              : "Click to connect wallet")
        .sheet(isPresented: $showingWalletSheet) {
            WalletConnectionView()
        }
    }
}

/// Larger wallet status card for use in sidebars/settings
struct WalletStatusCard: View {
    private let walletManager = WalletManager.shared
    @State private var showingWalletSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "wallet.pass.fill")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Wallet")
                    .font(.headline)
                
                Spacer()
                
                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(walletManager.isConnected ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(walletManager.isConnected ? "Connected" : "Not Connected")
                        .font(.caption)
                        .foregroundColor(walletManager.isConnected ? .green : .secondary)
                }
            }
            
            if walletManager.isConnected {
                // Address
                VStack(alignment: .leading, spacing: 4) {
                    Text("Address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(walletManager.shortAddress)
                        .font(.system(.body, design: .monospaced))
                }
                
                // Balance
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            if walletManager.isLoadingBalance {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Text(walletManager.balance)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("TUS")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        Task {
                            await walletManager.refreshBalance()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(walletManager.isLoadingBalance)
                }
                
                Divider()
                
                // Actions
                HStack(spacing: 12) {
                    Button {
                        showingWalletSheet = true
                    } label: {
                        Text("Manage")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(walletManager.walletAddress, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            } else {
                // Not connected state
                VStack(spacing: 12) {
                    Text("Connect your wallet to view your Digital Masters and create license instances.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        showingWalletSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("Connect Wallet")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
        )
        .sheet(isPresented: $showingWalletSheet) {
            WalletConnectionView()
        }
    }
}
