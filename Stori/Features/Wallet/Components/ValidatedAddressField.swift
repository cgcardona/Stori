//
//  ValidatedAddressField.swift
//  Stori
//
//  Real-time validated Ethereum address field with visual feedback
//

import SwiftUI

struct ValidatedAddressField: View {
    @Binding var address: String
    @State private var validation: AddressValidation = .empty
    @State private var showAddressBook = false
    
    let onSelectAddress: ((String) -> Void)?
    
    init(address: Binding<String>, onSelectAddress: ((String) -> Void)? = nil) {
        self._address = address
        self.onSelectAddress = onSelectAddress
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Address field
                HStack(spacing: 8) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                    
                    TextField("0x...", text: $address)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .textCase(.lowercase)
                        .onChange(of: address) { _, newValue in
                            validation = AddressValidator.validate(newValue)
                        }
                        .accessibilityLabel("Recipient Address")
                        .accessibilityHint("Enter Ethereum address starting with 0x")
                    
                    // Validation indicator
                    validationIndicator
                }
                .padding(14)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(validationBorderColor, lineWidth: 1)
                )
                
                // Address book button
                Button(action: { showAddressBook = true }) {
                    Image(systemName: "book.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Address Book")
                .accessibilityLabel("Open Address Book")
                .accessibilityHint("Choose a saved contact")
            }
            
            // Validation message
            if let message = validationMessage {
                HStack(spacing: 6) {
                    Image(systemName: validationIcon)
                    Text(message)
                        .font(.caption)
                }
                .foregroundColor(validationColor)
            }
            
            // Recent addresses (if available)
            if address.isEmpty && !AddressBook.shared.recentlyUsed.isEmpty {
                RecentAddressesList { selectedAddress in
                    address = selectedAddress
                    onSelectAddress?(selectedAddress)
                }
            }
        }
        .sheet(isPresented: $showAddressBook) {
            AddressBookSheet { selectedAddress in
                address = selectedAddress
                onSelectAddress?(selectedAddress)
                showAddressBook = false
            }
        }
    }
    
    @ViewBuilder
    private var validationIndicator: some View {
        switch validation {
        case .valid(let checksumValid):
            VStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                if !checksumValid {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                }
            }
        case .knownAddress:
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundColor(.blue)
            }
        case .suspicious:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        case .invalid:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .typing, .empty:
            EmptyView()
        }
    }
    
    private var validationBorderColor: Color {
        switch validation {
        case .empty, .typing:
            return .clear
        case .valid:
            return Color(hex: "10B981") ?? .green
        case .knownAddress:
            return Color(hex: "3B82F6") ?? .blue
        case .suspicious:
            return Color(hex: "F59E0B") ?? .orange
        case .invalid:
            return Color(hex: "EF4444") ?? .red
        }
    }
    
    private var validationMessage: String? {
        switch validation {
        case .valid(let checksumValid):
            if checksumValid {
                return "Valid address"
            } else {
                return "Valid address (checksum warning - verify carefully)"
            }
        case .knownAddress(let label):
            return "Known contact: \(label)"
        case .suspicious(let reason):
            return "⚠️ Warning: \(reason)"
        case .invalid(let reason):
            return reason
        case .typing, .empty:
            return nil
        }
    }
    
    private var validationColor: Color {
        switch validation {
        case .valid:
            return .green
        case .knownAddress:
            return .blue
        case .suspicious:
            return .orange
        case .invalid:
            return .red
        case .typing, .empty:
            return .secondary
        }
    }
    
    private var validationIcon: String {
        switch validation {
        case .valid:
            return "checkmark.circle.fill"
        case .knownAddress:
            return "person.crop.circle.badge.checkmark"
        case .suspicious:
            return "exclamationmark.triangle.fill"
        case .invalid:
            return "xmark.circle.fill"
        case .typing, .empty:
            return "info.circle"
        }
    }
}

// MARK: - Recent Addresses List

struct RecentAddressesList: View {
    let onSelect: (String) -> Void
    @State private var addressBook = AddressBook.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            ForEach(addressBook.recentlyUsed) { entry in
                Button(action: { onSelect(entry.address) }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: entry.color) ?? .gray)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(entry.initials)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.label)
                                .font(.caption.bold())
                            Text(entry.truncatedAddress)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
