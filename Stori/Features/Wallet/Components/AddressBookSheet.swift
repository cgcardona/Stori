//
//  AddressBookSheet.swift
//  Stori
//
//  Address book management UI
//

import SwiftUI

struct AddressBookSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var addressBook = AddressBook.shared
    @State private var showingAddContact = false
    @State private var searchText = ""
    
    private var filteredEntries: [AddressBookEntry] {
        if searchText.isEmpty {
            return addressBook.entries
        }
        return addressBook.entries.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            $0.address.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Address Book")
                        .font(.title2.bold())
                    Text("\(addressBook.entries.count) contacts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showingAddContact = true }) {
                    Label("Add Contact", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search contacts", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            // Contacts list
            if filteredEntries.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "person.badge.plus" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(searchText.isEmpty ? "No contacts yet" : "No results found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    if searchText.isEmpty {
                        Text("Add contacts to quickly send TUS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredEntries) { entry in
                            AddressBookRow(entry: entry) {
                                addressBook.markAsUsed(entry)
                                onSelect(entry.address)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 600, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingAddContact) {
            AddContactSheet()
        }
    }
}

// MARK: - Address Book Row

struct AddressBookRow: View {
    let entry: AddressBookEntry
    let onSelect: () -> Void
    @State private var showingEdit = false
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color(hex: entry.color) ?? .gray)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(entry.initials)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                )
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.label)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(entry.truncatedAddress)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Actions (show on hover)
            if isHovered {
                HStack(spacing: 8) {
                    Button(action: { showingEdit = true }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .help("Edit")
                    
                    Button(action: copyAddress) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .help("Copy Address")
                    
                    Button(action: onSelect) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Use Address")
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(isHovered ? 0.08 : 0.04))
        .cornerRadius(12)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditContactSheet(entry: entry)
        }
    }
    
    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.address, forType: .string)
    }
}

// MARK: - Add Contact Sheet

struct AddContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var address = ""
    @State private var selectedColor = "8B5CF6"
    @State private var addressBook = AddressBook.shared
    
    let availableColors = [
        "8B5CF6", // Purple
        "3B82F6", // Blue
        "10B981", // Green
        "F59E0B", // Orange
        "EF4444", // Red
        "EC4899", // Pink
        "14B8A6", // Teal
        "F97316"  // Orange-red
    ]
    
    private var canSave: Bool {
        !label.isEmpty &&
        address.count == 42 &&
        address.hasPrefix("0x")
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Add Contact")
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
                    TextField("e.g., Alice, Bob, Exchange", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Address")
                        .font(.headline)
                    ValidatedAddressField(address: $address)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                        .font(.headline)
                    HStack(spacing: 8) {
                        ForEach(availableColors, id: \.self) { color in
                            Button(action: { selectedColor = color }) {
                                Circle()
                                    .fill(Color(hex: color) ?? .gray)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white, lineWidth: 2)
                                            .opacity(selectedColor == color ? 1 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Add Contact") {
                    addressBook.addEntry(label: label, address: address, color: selectedColor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }
}

// MARK: - Edit Contact Sheet

struct EditContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: AddressBookEntry
    @State private var label: String
    @State private var selectedColor: String
    @State private var addressBook = AddressBook.shared
    @State private var showingDeleteConfirmation = false
    
    let availableColors = [
        "8B5CF6", "3B82F6", "10B981", "F59E0B",
        "EF4444", "EC4899", "14B8A6", "F97316"
    ]
    
    init(entry: AddressBookEntry) {
        self.entry = entry
        _label = State(initialValue: entry.label)
        _selectedColor = State(initialValue: entry.color)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Edit Contact")
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
                    TextField("Label", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Address")
                        .font(.headline)
                    Text(entry.address)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                        .font(.headline)
                    HStack(spacing: 8) {
                        ForEach(availableColors, id: \.self) { color in
                            Button(action: { selectedColor = color }) {
                                Circle()
                                    .fill(Color(hex: color) ?? .gray)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white, lineWidth: 2)
                                            .opacity(selectedColor == color ? 1 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    var updated = entry
                    updated.label = label
                    updated.color = selectedColor
                    addressBook.updateEntry(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500, height: 350)
        .alert("Delete Contact?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                addressBook.deleteEntry(entry)
                dismiss()
            }
        } message: {
            Text("This will permanently delete \(entry.label) from your address book.")
        }
    }
}
