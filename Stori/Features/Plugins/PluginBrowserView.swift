//
//  PluginBrowserView.swift
//  Stori
//
//  Searchable, filterable browser for discovering and selecting Audio Unit plugins.
//

import SwiftUI

// MARK: - Plugin Browser View

struct PluginBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scanner = PluginScanner()
    @State private var searchText = ""
    @State private var selectedCategory: PluginDescriptor.PluginCategory?
    @State private var selectedManufacturer: String?
    @State private var sortOrder: SortOrder = .name
    @State private var selectedPlugin: PluginDescriptor?
    
    /// Callback when a plugin is selected for insertion
    var onPluginSelected: ((PluginDescriptor) -> Void)?
    
    /// Whether to show only a specific category (e.g., only instruments for MIDI tracks)
    var filterToCategory: PluginDescriptor.PluginCategory?
    
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case manufacturer = "Manufacturer"
        case category = "Category"
    }
    
    var filteredPlugins: [PluginDescriptor] {
        var plugins = scanner.discoveredPlugins
        
        // Apply category filter (either from prop or user selection)
        if let category = filterToCategory ?? selectedCategory {
            plugins = plugins.filter { $0.category == category }
        }
        
        // Apply manufacturer filter
        if let manufacturer = selectedManufacturer {
            plugins = plugins.filter { $0.manufacturer == manufacturer }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            plugins = plugins.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.manufacturer.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sort
        return plugins.sorted { lhs, rhs in
            switch sortOrder {
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .manufacturer:
                return lhs.manufacturer.localizedCaseInsensitiveCompare(rhs.manufacturer) == .orderedAscending
            case .category:
                return lhs.category.rawValue < rhs.category.rawValue
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and filters
            headerBar
            
            Divider()
            
            // Plugin list
            if scanner.isScanning {
                scanningView
            } else if filteredPlugins.isEmpty {
                emptyStateView
            } else {
                pluginList
            }
            
            // Footer with action buttons (only show when callback is provided)
            if onPluginSelected != nil {
                Divider()
                
                HStack {
                    if let selected = selectedPlugin {
                        Text(selected.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Select a plugin to insert")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Insert") {
                        if let plugin = selectedPlugin {
                            onPluginSelected?(plugin)
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedPlugin == nil)
                }
                .padding()
                .background(Color(.windowBackgroundColor))
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .task {
            await scanner.loadCachedPlugins()
            if scanner.discoveredPlugins.isEmpty {
                await scanner.scanForPlugins()
            }
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        VStack(spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search plugins...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)
            
            // Filters row
            HStack {
                // Category filter (only show if not pre-filtered)
                if filterToCategory == nil {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(nil as PluginDescriptor.PluginCategory?)
                        ForEach(PluginDescriptor.PluginCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category as PluginDescriptor.PluginCategory?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 140)
                }
                
                // Manufacturer filter
                Picker("Manufacturer", selection: $selectedManufacturer) {
                    Text("All Manufacturers").tag(nil as String?)
                    ForEach(scanner.manufacturers, id: \.self) { mfr in
                        Text(mfr).tag(mfr as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
                
                Spacer()
                
                // Sort order
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                
                // Rescan button
                Button(action: { Task { await scanner.scanForPlugins() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(scanner.isScanning)
                .help("Rescan for plugins")
            }
            
            // Plugin count
            HStack {
                Text("\(filteredPlugins.count) plugins")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let date = scanner.lastScanDate {
                    Text("Last scan: \(date, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Plugin List
    
    private var pluginList: some View {
        List(filteredPlugins, selection: $selectedPlugin) { plugin in
            PluginRowView(plugin: plugin)
                .tag(plugin)
                .onTapGesture(count: 2) {
                    onPluginSelected?(plugin)
                }
        }
        .listStyle(.inset)
    }
    
    // MARK: - Scanning View
    
    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView(value: scanner.scanProgress) {
                Text("Scanning for Audio Units...")
            }
            .progressViewStyle(.linear)
            .frame(maxWidth: 300)
            
            Text("\(Int(scanner.scanProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            if scanner.discoveredPlugins.isEmpty {
                Text("No Audio Units Found")
                    .font(.headline)
                Text("Install Audio Unit plugins to use them in your projects.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No Matching Plugins")
                    .font(.headline)
                Text("Try adjusting your search or filters.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Clear Filters") {
                    searchText = ""
                    selectedCategory = nil
                    selectedManufacturer = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Plugin Row View

struct PluginRowView: View {
    let plugin: PluginDescriptor
    
    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            categoryIcon
                .frame(width: 32, height: 32)
                .background(categoryColor.opacity(0.15))
                .cornerRadius(6)
            
            // Plugin info
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(plugin.manufacturer)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Category badge
            Text(plugin.category.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(categoryColor.opacity(0.2))
                .foregroundColor(categoryColor)
                .cornerRadius(4)
            
            // Version
            Text("v\(plugin.version)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var categoryIcon: some View {
        Image(systemName: categoryIconName)
            .font(.system(size: 16))
            .foregroundColor(categoryColor)
    }
    
    private var categoryIconName: String {
        switch plugin.category {
        case .effect: return "waveform.badge.plus"
        case .instrument: return "pianokeys"
        case .midiEffect: return "music.note.list"
        case .generator: return "waveform"
        case .unknown: return "questionmark"
        }
    }
    
    private var categoryColor: Color {
        switch plugin.category {
        case .effect: return .blue
        case .instrument: return .purple
        case .midiEffect: return .green
        case .generator: return .orange
        case .unknown: return .gray
        }
    }
}

// MARK: - Plugin Browser Sheet Wrapper

/// Convenience wrapper for presenting the browser as a sheet
struct PluginBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let title: String
    let category: PluginDescriptor.PluginCategory?
    let onSelect: (PluginDescriptor) -> Void
    
    init(title: String = "Select Plugin", category: PluginDescriptor.PluginCategory? = nil, onSelect: @escaping (PluginDescriptor) -> Void) {
        self.title = title
        self.category = category
        self.onSelect = onSelect
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            // Browser
            PluginBrowserView(
                onPluginSelected: { plugin in
                    onSelect(plugin)
                    dismiss()
                },
                filterToCategory: category
            )
        }
        .frame(width: 600, height: 500)
    }
}
