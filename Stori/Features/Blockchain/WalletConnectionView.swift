//
//  WalletConnectionView.swift
//  Stori
//
//  Created by TellUrStori on 12/8/25.
//

import SwiftUI

/// Modal view for connecting/disconnecting wallet
struct WalletConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    private let walletManager = WalletManager.shared
    
    /// Optional BlockchainClient to sync wallet state with
    var blockchainClient: BlockchainClient?
    
    // MARK: - Local State
    @State private var addressInput: String = ""
    @State private var isValidating: Bool = false
    @State private var validationError: String?
    @State private var showingDisconnectConfirm: Bool = false
    @State private var animateGradient: Bool = false
    @State private var showCopied: Bool = false
    @FocusState private var isAddressFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Gradient header
            gradientHeader
            
            // Content
            if walletManager.isConnected {
                connectedContent
            } else {
                connectContent
            }
        }
        .frame(width: 520, height: walletManager.isConnected ? 520 : 540)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
            if !walletManager.isConnected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isAddressFocused = true
                }
            }
        }
        .alert("Disconnect Wallet", isPresented: $showingDisconnectConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                walletManager.disconnect(blockchainClient: blockchainClient)
            }
        } message: {
            Text("Are you sure you want to disconnect your wallet? You'll need to reconnect to view your Digital Masters.")
        }
    }
    
    // MARK: - Gradient Header
    
    private var gradientHeader: some View {
        LinearGradient(
            colors: [
                walletManager.isConnected ? Color.green.opacity(0.8) : Color.blue.opacity(0.8),
                walletManager.isConnected ? Color.teal.opacity(0.6) : Color.purple.opacity(0.6),
                walletManager.isConnected ? Color.cyan.opacity(0.4) : Color.pink.opacity(0.4)
            ],
            startPoint: animateGradient ? .topLeading : .bottomTrailing,
            endPoint: animateGradient ? .bottomTrailing : .topLeading
        )
        .frame(height: 140)
        .overlay(
            VStack(spacing: 12) {
                // Icon with glow
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 70, height: 70)
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 90, height: 90)
                    
                    if walletManager.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                
                Text(walletManager.isConnected ? "Wallet Connected" : "Connect Wallet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
    
    // MARK: - Connected Content
    
    private var connectedContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                // Address field
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                        Text("Wallet Address")
                            .font(.system(size: 14, weight: .medium))
                    }
                    
                    HStack(spacing: 12) {
                        Text(walletManager.walletAddress)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Button {
                            copyToClipboard(walletManager.walletAddress)
                            withAnimation(.spring(response: 0.3)) {
                                showCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showCopied = false }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12))
                                if showCopied {
                                    Text("Copied!")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .foregroundColor(showCopied ? .green : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(showCopied ? Color.green.opacity(0.1) : Color(.controlBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                
                // Balance field
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "bitcoinsign.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("Balance")
                            .font(.system(size: 14, weight: .medium))
                    }
                    
                    HStack {
                        if walletManager.isLoadingBalance {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading...")
                                .foregroundColor(.secondary)
                        } else {
                            Text(walletManager.balance)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            
                            Text("TUS")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.orange, .pink],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                        }
                        
                        Spacer()
                        
                        Button {
                            Task {
                                await walletManager.refreshBalance()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(walletManager.isLoadingBalance)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                
                // Network info
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "network")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                        Text("Network")
                            .font(.system(size: 14, weight: .medium))
                    }
                    
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Stori L1")
                                .font(.system(size: 14))
                        }
                        Spacer()
                        Text("Chain ID: 507")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor).opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            
            Spacer()
            
            // Buttons
            HStack(spacing: 16) {
                Button {
                    showingDisconnectConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.portrait.and.arrow.forward")
                        Text("Disconnect")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Done")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.teal],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
    }
    
    // MARK: - Connect Content
    
    private var connectContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text("How it works")
                            .font(.system(size: 14, weight: .medium))
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        instructionRow(number: "1", text: "Enter your TellUrStori wallet address", color: .blue)
                        instructionRow(number: "2", text: "View your Digital Masters and licenses", color: .purple)
                        instructionRow(number: "3", text: "Gas fees sponsored by TellUrStori ✨", color: .pink)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor).opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                
                // Address input
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("Wallet Address")
                            .font(.system(size: 14, weight: .medium))
                    }
                    
                    HStack(spacing: 12) {
                        TextField("0x...", text: $addressInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .monospaced))
                            .focused($isAddressFocused)
                            .onSubmit {
                                connectWallet()
                            }
                            .onChange(of: addressInput) { _, _ in
                                validationError = nil
                            }
                        
                        Button {
                            if let clipboard = NSPasteboard.general.string(forType: .string) {
                                addressInput = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Paste from clipboard")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        validationError != nil
                                            ? Color.red.opacity(0.5)
                                            : addressInput.isEmpty
                                                ? Color.gray.opacity(0.2)
                                                : Color.orange.opacity(0.5),
                                        lineWidth: 1
                                    )
                            )
                    )
                    
                    if let error = validationError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            Text(error)
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            
            Spacer()
            
            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button {
                    connectWallet()
                } label: {
                    HStack(spacing: 8) {
                        if isValidating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "link.circle.fill")
                        }
                        Text(isValidating ? "Connecting..." : "Connect Wallet")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: addressInput.isEmpty
                                ? [.gray.opacity(0.5), .gray.opacity(0.4)]
                                : [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(addressInput.isEmpty || isValidating)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
    }
    
    // MARK: - Helper Views
    
    private func instructionRow(number: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(color))
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func connectWallet() {
        isValidating = true
        validationError = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isValidating = false
            
            let success = walletManager.connect(address: addressInput, blockchainClient: blockchainClient)
            
            if success {
                dismiss()
            } else {
                validationError = walletManager.errorMessage ?? "Invalid address"
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
