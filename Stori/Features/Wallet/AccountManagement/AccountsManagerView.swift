//
//  AccountsManagerView.swift
//  Stori
//
//  Multi-account management UI
//

import SwiftUI

struct AccountsManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accountManager = AccountManager.shared
    private let walletService = WalletService.shared
    @State private var showingAddAccount = false
    @State private var showingEditAccount: DerivedAccount?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accounts")
                        .font(.title2.bold())
                    Text("Manage your derived wallet accounts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Accounts list
            ScrollView {
                VStack(spacing: 12) {
                    if accountManager.accounts.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(accountManager.accounts.enumerated()), id: \.element.id) { index, account in
                            AccountRow(
                                account: account,
                                isSelected: index == accountManager.selectedAccountIndex,
                                onSelect: { selectAccount(at: index) },
                                onEdit: { showingEditAccount = account }
                            )
                        }
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Actions
            HStack {
                Button(action: refreshAllBalances) {
                    HStack(spacing: 6) {
                        if accountManager.isLoadingBalances {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh Balances")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(accountManager.isLoadingBalances || accountManager.accounts.isEmpty)
                
                Spacer()
                
                if accountManager.accounts.isEmpty {
                    Button(action: generateInitialAccounts) {
                        Label("Generate Accounts", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 600, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: $showingEditAccount) { account in
            EditAccountSheet(account: account)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No Accounts Yet")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Generate accounts from your wallet's seed phrase")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button(action: generateInitialAccounts) {
                Label("Generate 5 Accounts", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    private func selectAccount(at index: Int) {
        accountManager.selectAccount(at: index)
        accountManager.markAccountAsUsed(at: index)
        // The UI will update automatically due to @Observable
    }
    
    private func generateInitialAccounts() {
        guard let hdWallet = walletService.wallet as? HDWallet else {
            return
        }
        
        do {
            try accountManager.generateAccounts(from: hdWallet, count: 5)
            Task {
                await accountManager.refreshBalances(network: walletService.selectedNetwork)
            }
        } catch {
        }
    }
    
    private func refreshAllBalances() {
        Task {
            await accountManager.refreshBalances(network: walletService.selectedNetwork)
        }
    }
}

// MARK: - Account Row

struct AccountRow: View {
    let account: DerivedAccount
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Selection indicator
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                    .frame(width: 44, height: 44)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)
                } else {
                    Text("\(account.index + 1)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            
            // Account info
            VStack(alignment: .leading, spacing: 4) {
                Text(account.label)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(account.shortAddress)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Text(account.derivationPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            
            Spacer()
            
            // Balance
            VStack(alignment: .trailing, spacing: 4) {
                Text(account.formattedBalance)
                    .font(.system(size: 14, weight: .bold))
                
                if let lastUsed = account.lastUsed {
                    Text("Last used \(formatRelativeTime(lastUsed))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            // Actions on hover
            if isHovered && !isSelected {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .help("Edit Label")
                    
                    Button(action: copyAddress) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .help("Copy Address")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : (isHovered ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.04)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .onTapGesture {
            if !isSelected {
                onSelect()
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(account.address, forType: .string)
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Edit Account Sheet

struct EditAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let account: DerivedAccount
    @State private var label: String
    @State private var accountManager = AccountManager.shared
    
    init(account: DerivedAccount) {
        self.account = account
        _label = State(initialValue: account.label)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Edit Account")
                    .font(.title2.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Label")
                        .font(.headline)
                    TextField("Account label", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Address")
                        .font(.headline)
                    Text(account.address)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Derivation Path")
                        .font(.headline)
                    Text(account.derivationPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    accountManager.updateLabel(for: account.id, newLabel: label)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450, height: 350)
    }
}

// MARK: - Account Switcher (Compact)

struct AccountSwitcher: View {
    @State private var accountManager = AccountManager.shared
    @State private var showingManager = false
    
    var body: some View {
        Button(action: { showingManager = true }) {
            HStack(spacing: 8) {
                if let account = accountManager.selectedAccount {
                    Text(account.label)
                        .font(.system(size: 12, weight: .medium))
                    
                    Text(account.shortAddress)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("Account 1")
                        .font(.system(size: 12, weight: .medium))
                }
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch Account")
        .accessibilityHint("Opens account manager to switch between wallet accounts")
        .accessibilityValue(accountManager.selectedAccount?.label ?? "Account 1")
        .sheet(isPresented: $showingManager) {
            AccountsManagerView()
        }
    }
}
