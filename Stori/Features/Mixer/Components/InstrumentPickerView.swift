//
//  InstrumentPickerView.swift
//  Stori
//
//  Unified instrument picker for MIDI tracks.
//  Shows both Audio Unit instruments and GM SoundFont instruments.
//

import SwiftUI

// MARK: - Unified Instrument Picker View

struct UnifiedInstrumentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onAUInstrumentSelected: (PluginDescriptor) -> Void
    let onGMInstrumentSelected: (GMInstrument) -> Void
    /// Current GM program (0–127 or 1000+ for drum kits) if track uses GM; used to pre-select when opening.
    var currentGMProgram: Int? = nil
    /// Current AU plugin name if track uses AU; used to pre-select when opening.
    var currentAUName: String? = nil
    
    @State private var selectedTab: InstrumentTab = .soundFont
    @State private var searchText = ""
    
    // AU Instruments
    @State private var scanner = PluginScanner()
    @State private var selectedPlugin: PluginDescriptor?
    
    // GM Instruments
    @State private var expandedCategories: Set<String> = []
    @State private var selectedGMInstrument: GMInstrument?
    @State private var loadingInstrument: Bool = false
    
    // On-demand asset download (SoundFont from API)
    @State private var remoteSoundfonts: [SoundFontItem] = []
    @State private var assetListLoading = false
    @State private var assetError: String?
    @State private var downloadingSoundfontId: String?
    @State private var downloadingAllInstruments = false
    /// (current, total) when downloading all instruments
    @State private var downloadAllInstrumentsProgress: (Int, Int)?
    /// Download progress percentage (0.0 to 1.0) for individual downloads
    @State private var downloadProgressPercent: Double = 0

    /// Check if SoundFont is available (from Application Support)
    private var hasSoundFont: Bool {
        SoundFontManager.shared.hasSoundFont
    }
    
    enum InstrumentTab: String, CaseIterable {
        case soundFont = "SoundFont"
        case audioUnit = "Audio Unit"
        
        var icon: String {
            switch self {
            case .soundFont: return "pianokeys"
            case .audioUnit: return "puzzlepiece.extension"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Tab selector
            tabSelector
            
            Divider()
            
            // Content
            Group {
                switch selectedTab {
                case .soundFont:
                    soundFontContent
                case .audioUnit:
                    audioUnitContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 320, height: 500)
        .background(Color(.windowBackgroundColor))
        .task {
            await scanner.loadCachedPlugins()
            if scanner.discoveredPlugins.isEmpty {
                await scanner.scanForPlugins()
            }
            initializeSelection()
        }
    }
    
    // MARK: - Selection Initialization
    
    /// Pre-select the current instrument when picker opens.
    private func initializeSelection() {
        if let gmProgram = currentGMProgram,
           let gmInstrument = GMInstrument(rawValue: gmProgram) {
            selectedGMInstrument = gmInstrument
            selectedTab = .soundFont
            expandedCategories.insert(gmInstrument.category.rawValue)
            return
        }
        if let auName = currentAUName {
            selectedPlugin = scanner.discoveredPlugins.first { plugin in
                plugin.name == auName || auName.contains(plugin.name)
            }
            if selectedPlugin != nil {
                selectedTab = .audioUnit
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("Select Instrument")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(InstrumentTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10))
                        Text(tab.rawValue)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab ?
                        Color.accentColor.opacity(0.1) :
                        Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.controlBackgroundColor))
    }
    
    // MARK: - Audio Unit Content
    
    private var audioUnitContent: some View {
        VStack(spacing: 0) {
            // Search
            searchBar
            
            // Plugin list
            if scanner.isScanning {
                scanningView
            } else if filteredAUPlugins.isEmpty {
                emptyAUView
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredAUPlugins) { plugin in
                            auPluginRow(plugin)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private var filteredAUPlugins: [PluginDescriptor] {
        let instruments = scanner.discoveredPlugins.filter { $0.category == .instrument }
        
        if searchText.isEmpty {
            return instruments.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        
        return instruments.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.manufacturer.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func auPluginRow(_ plugin: PluginDescriptor) -> some View {
        Button(action: { selectedPlugin = plugin }) {
            HStack(spacing: 8) {
                // Selection indicator
                Circle()
                    .fill(selectedPlugin?.id == plugin.id ? Color.accentColor : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )
                
                // Plugin info
                VStack(alignment: .leading, spacing: 1) {
                    Text(plugin.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    
                    Text(plugin.manufacturer)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Category badge
                Text("AU")
                    .font(.system(size: 8, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .foregroundColor(.purple)
                    .cornerRadius(3)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                selectedPlugin?.id == plugin.id ?
                Color.accentColor.opacity(0.1) :
                Color.clear
            )
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var scanningView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning Audio Units...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyAUView: some View {
        VStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("No AU Instruments Found")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Rescan") {
                Task { await scanner.scanForPlugins() }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// Fallback SoundFont download when list API fails (known backend id/filename).
    private var soundFontFallbackDownloadButton: some View {
        let soundfontId = "musescore_general"
        let filename = "MuseScore_General.sf2"
        let isInstalled = AssetDownloadService.isSoundFontInstalled(filename: filename)
        let isDownloading = downloadingSoundfontId == soundfontId
        return Group {
            if isInstalled {
                Text("MuseScore General: Installed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if isDownloading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Downloading...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Button("Download MuseScore General (128 GM instruments)") {
                    Task { await downloadSoundFont(SoundFontItem(id: soundfontId, name: "MuseScore General", filename: filename)) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 4)
    }

    /// "Download all instruments" (SoundFonts) button with progress.
    private var downloadAllInstrumentsButton: some View {
        Group {
            if downloadingAllInstruments {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    if let (current, total) = downloadAllInstrumentsProgress, total > 0 {
                        Text("Downloading \(current) of \(total)...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Downloading instruments...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else if remoteSoundfonts.contains(where: { !AssetDownloadService.isSoundFontInstalled(filename: $0.filename) }) {
                Button(action: { Task { await downloadAllSoundfonts() } }) {
                    Label("Download all instruments", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 4)
            }
        }
    }

    private func downloadAllSoundfonts() async {
        downloadingAllInstruments = true
        downloadAllInstrumentsProgress = nil
        defer {
            downloadingAllInstruments = false
            downloadAllInstrumentsProgress = nil
        }
        do {
            try await AssetDownloadService.shared.downloadAllSoundfonts { current, total in
                downloadAllInstrumentsProgress = (current, total)
            }
            SoundFontManager.shared.discoverSoundFonts()
        } catch {
            assetError = error.localizedDescription
        }
    }

    // MARK: - SoundFont Content
    
    private var soundFontContent: some View {
        VStack(spacing: 0) {
            // Search
            searchBar
            
            if !hasSoundFont {
                noSoundFontView
                    .task { await loadRemoteSoundfontsIfNeeded() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 4, pinnedViews: []) {
                        ForEach(GMCategory.allCases) { category in
                            gmCategorySection(category)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private var noSoundFontView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 32)
            
            VStack(spacing: 8) {
                Text("No SoundFont Installed")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Download to access 128 General MIDI instruments")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if assetListLoading && remoteSoundfonts.isEmpty {
                ProgressView()
                    .scaleEffect(0.9)
                    .padding()
            } else if let error = assetError, remoteSoundfonts.isEmpty {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") { Task { await loadRemoteSoundfontsIfNeeded() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if !remoteSoundfonts.isEmpty {
                // Show individual SoundFont items as prominent download cards
                VStack(spacing: 12) {
                    ForEach(remoteSoundfonts) { item in
                        soundFontDownloadCard(item)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else {
                Text("Checking for available SoundFonts...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func soundFontDownloadCard(_ item: SoundFontItem) -> some View {
        let isInstalled = AssetDownloadService.isSoundFontInstalled(filename: item.filename)
        let isDownloading = downloadingSoundfontId == item.id
        
        return Button(action: {
            guard !isInstalled && !isDownloading else { return }
            Task { await downloadSoundFont(item) }
        }) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: "pianokeys")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("128 General MIDI Instruments")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(item.filename)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // State indicator
                    if isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                    } else if isDownloading {
                        VStack(spacing: 4) {
                            ProgressView(value: downloadProgressPercent, total: 1.0)
                                .frame(width: 60)
                            Text("\(Int(downloadProgressPercent * 100))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isInstalled ? Color.green.opacity(0.3) : Color.blue.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isInstalled || isDownloading)
        .accessibilityLabel(isInstalled ? "\(item.name) installed" : "Download \(item.name)")
    }
    
    private func loadRemoteSoundfontsIfNeeded() async {
        SoundFontManager.shared.discoverSoundFonts()
        guard !hasSoundFont else { return }
        assetListLoading = true
        assetError = nil
        defer { assetListLoading = false }
        do {
            remoteSoundfonts = try await AssetDownloadService.shared.listSoundfonts()
        } catch {
            assetError = error.localizedDescription
        }
    }
    
    private func downloadSoundFont(_ item: SoundFontItem) async {
        downloadingSoundfontId = item.id
        downloadProgressPercent = 0
        defer {
            downloadingSoundfontId = nil
            downloadProgressPercent = 0
        }
        do {
            try await AssetDownloadService.shared.downloadSoundFont(
                soundfontId: item.id,
                filename: item.filename,
                progress: { percent in
                    downloadProgressPercent = percent
                }
            )
            SoundFontManager.shared.discoverSoundFonts()
        } catch {
            assetError = error.localizedDescription
        }
    }
    
    private func gmCategorySection(_ category: GMCategory) -> some View {
        let instruments = filteredGMInstruments(for: category)
        guard !instruments.isEmpty else { return AnyView(EmptyView()) }
        
        let isExpanded = expandedCategories.contains(category.rawValue)
        
        return AnyView(
            VStack(spacing: 0) {
                // Category header
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedCategories.remove(category.rawValue)
                        } else {
                            expandedCategories.insert(category.rawValue)
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: category.icon)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        
                        Text(category.rawValue)
                            .font(.system(size: 11, weight: .medium))
                        
                        Spacer()
                        
                        Text("\(instruments.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                // Instruments list
                if isExpanded {
                    VStack(spacing: 1) {
                        ForEach(instruments) { instrument in
                            gmInstrumentRow(instrument)
                        }
                    }
                    .padding(.leading, 20)
                }
            }
        )
    }
    
    private func filteredGMInstruments(for category: GMCategory) -> [GMInstrument] {
        let instruments = category.instruments
        
        if searchText.isEmpty {
            return instruments
        }
        
        return instruments.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func gmInstrumentRow(_ instrument: GMInstrument) -> some View {
        Button(action: { selectedGMInstrument = instrument }) {
            HStack(spacing: 8) {
                // Selection indicator
                Circle()
                    .fill(selectedGMInstrument == instrument ? Color.accentColor : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )
                
                Text(instrument.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                selectedGMInstrument == instrument ?
                Color.accentColor.opacity(0.1) :
                Color.clear
            )
            .cornerRadius(3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Shared Components
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            
            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlColor))
        .cornerRadius(6)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button {
                selectInstrument()
            } label: {
                HStack(spacing: 8) {
                    if loadingInstrument {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading...")
                    } else {
                        Text("Select")
                    }
                }
                .frame(minWidth: 100)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!hasSelection || loadingInstrument)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var hasSelection: Bool {
        switch selectedTab {
        case .audioUnit:
            return selectedPlugin != nil
        case .soundFont:
            return selectedGMInstrument != nil
        }
    }
    
    private func selectInstrument() {
        switch selectedTab {
        case .audioUnit:
            if let plugin = selectedPlugin {
                loadingInstrument = true
                Task {
                    await MainActor.run {
                        onAUInstrumentSelected(plugin)
                        dismiss()
                    }
                }
            }
        case .soundFont:
            if let instrument = selectedGMInstrument {
                loadingInstrument = true
                Task {
                    // Small delay to ensure spinner shows
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    await MainActor.run {
                        onGMInstrumentSelected(instrument)
                        dismiss()
                    }
                }
            }
        }
    }
}
