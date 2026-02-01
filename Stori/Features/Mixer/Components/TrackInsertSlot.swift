//
//  TrackInsertSlot.swift
//  Stori
//
//  Insert effect slot component for track channel strips
//

import SwiftUI

// MARK: - Track Insert Slot
struct TrackInsertSlot: View {
    let slotIndex: Int
    let pluginInstance: PluginInstance?  // Live AU plugin (if loaded)
    let trackId: UUID  // The track containing this slot
    let sidechainSource: SidechainSource
    let availableTracks: [AudioTrack]
    let availableBuses: [MixerBus]
    let onAddPlugin: (PluginDescriptor) -> Void  // For AU plugins
    let onToggleBypass: () -> Void
    let onRemoveEffect: () -> Void
    let onOpenEditor: () -> Void
    let onSetSidechain: (SidechainSource) -> Void
    
    @State private var showingPluginBrowser = false
    @State private var showingSidechainPicker = false
    @State private var isHovered = false
    
    // Initializer for plugin slots
    init(
        slotIndex: Int,
        pluginInstance: PluginInstance?,
        trackId: UUID,
        sidechainSource: SidechainSource,
        availableTracks: [AudioTrack],
        availableBuses: [MixerBus],
        onAddPlugin: @escaping (PluginDescriptor) -> Void,
        onToggleBypass: @escaping () -> Void,
        onRemoveEffect: @escaping () -> Void,
        onOpenEditor: @escaping () -> Void,
        onSetSidechain: @escaping (SidechainSource) -> Void
    ) {
        self.slotIndex = slotIndex
        self.pluginInstance = pluginInstance
        self.trackId = trackId
        self.sidechainSource = sidechainSource
        self.availableTracks = availableTracks
        self.availableBuses = availableBuses
        self.onAddPlugin = onAddPlugin
        self.onToggleBypass = onToggleBypass
        self.onRemoveEffect = onRemoveEffect
        self.onOpenEditor = onOpenEditor
        self.onSetSidechain = onSetSidechain
    }
    
    var body: some View {
        Button(action: {
            if pluginInstance == nil {
                showingPluginBrowser = true
            } else {
                onOpenEditor()
            }
        }) {
            HStack(spacing: 2) {
                if let pluginInstance = pluginInstance {
                    // AU Plugin assigned
                    pluginDisplayView(pluginInstance)
                } else {
                    // Empty slot
                    emptySlotView
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .background(slotBackground)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPluginBrowser) {
            PluginBrowserView(
                onPluginSelected: { plugin in
                    onAddPlugin(plugin)
                    showingPluginBrowser = false
                },
                filterToCategory: .effect
            )
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if let pluginInstance = pluginInstance {
                Button(action: onToggleBypass) {
                    let isBypassed = pluginInstance.isBypassed
                    Label(
                        isBypassed ? "Enable" : "Bypass",
                        systemImage: isBypassed ? "power.circle" : "power.circle.fill"
                    )
                }
                
                Button(action: onOpenEditor) {
                    Label("Edit Effect", systemImage: "slider.horizontal.3")
                }
                
                // Sidechain option for plugins that support it
                if pluginInstance.supportsSidechain {
                    Divider()
                    
                    Button(action: { showingSidechainPicker = true }) {
                        Label(
                            sidechainSource.isEnabled ? "Change Sidechain..." : "Set Sidechain...",
                            systemImage: "link"
                        )
                    }
                    
                    if sidechainSource.isEnabled {
                        Button(action: { onSetSidechain(.none) }) {
                            Label("Remove Sidechain", systemImage: "link.badge.plus")
                        }
                    }
                }
                
                Divider()
                
                Button(role: .destructive, action: onRemoveEffect) {
                    Label("Remove Effect", systemImage: "trash")
                }
            } else {
                Button(action: { showingPluginBrowser = true }) {
                    Label("Browse AU Plugins...", systemImage: "puzzlepiece.extension")
                }
            }
        }
    }
    
    // MARK: - Plugin Display
    private func pluginDisplayView(_ instance: PluginInstance) -> some View {
        HStack(spacing: 3) {
            // Bypass indicator
            Circle()
                .fill(instance.isBypassed ? Color.gray : Color.blue)
                .frame(width: 4, height: 4)
            
            // Plugin name
            Text(instance.descriptor.name)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(instance.isBypassed ? .secondary : .primary)
            
            Spacer()
            
            // Sidechain button (if supported)
            if instance.supportsSidechain {
                Button(action: { showingSidechainPicker = true }) {
                    Image(systemName: sidechainSource.isEnabled ? "link.circle.fill" : "link")
                        .font(.system(size: 8))
                        .foregroundColor(sidechainSource.isEnabled ? .orange : .secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(sidechainSource.isEnabled ? 
                      "Sidechain: \(sidechainSource.displayName(tracks: availableTracks, buses: availableBuses))" : 
                      "Set sidechain source")
                .popover(isPresented: $showingSidechainPicker, arrowEdge: .trailing) {
                    SidechainPickerView(
                        currentSource: sidechainSource,
                        availableTracks: availableTracks,
                        availableBuses: availableBuses,
                        currentTrackId: trackId,
                        onSelect: { source in
                            onSetSidechain(source)
                            showingSidechainPicker = false
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Empty Slot
    private var emptySlotView: some View {
        Text("---")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity)
    }
    
    // MARK: - Slot Background
    private var slotBackground: some View {
        let hasContent = pluginInstance != nil
        
        return RoundedRectangle(cornerRadius: 2)
            .fill(hasContent ? Color.blue.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(
                        isHovered ? Color.accentColor.opacity(0.5) : MixerColors.slotBorder,
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - Inserts Section
struct InsertsSection: View {
    let trackId: UUID
    let pluginChain: PluginChain?  // Live plugin chain from AudioEngine
    let sidechainSources: [Int: SidechainSource]  // Slot index -> sidechain source
    let availableTracks: [AudioTrack]
    let availableBuses: [MixerBus]
    let onAddPlugin: (Int, PluginDescriptor) -> Void  // For AU plugins
    let onToggleBypass: (Int) -> Void
    let onRemoveEffect: (Int) -> Void
    let onOpenEditor: (Int) -> Void
    let onSetSidechain: (Int, SidechainSource) -> Void
    
    @State private var isExpanded = true
    
    private let maxSlots = 8
    
    var body: some View {
        VStack(spacing: 2) {
            // Section Header
            Button(action: { 
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    
                    Text("INSERTS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(MixerColors.sectionHeader)
                    
                    Spacer()
                    
                    // Active plugin count
                    let activeCount = countActivePlugins()
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor)
                            .cornerRadius(3)
                    }
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(0..<maxSlots, id: \.self) { index in
                        TrackInsertSlot(
                            slotIndex: index,
                            pluginInstance: pluginChain?.slots[index],
                            trackId: trackId,
                            sidechainSource: sidechainSources[index] ?? .none,
                            availableTracks: availableTracks,
                            availableBuses: availableBuses,
                            onAddPlugin: { descriptor in
                                onAddPlugin(index, descriptor)
                            },
                            onToggleBypass: {
                                onToggleBypass(index)
                            },
                            onRemoveEffect: {
                                onRemoveEffect(index)
                            },
                            onOpenEditor: {
                                onOpenEditor(index)
                            },
                            onSetSidechain: { source in
                                onSetSidechain(index, source)
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MixerColors.slotBackground)
        )
    }
    
    private func countActivePlugins() -> Int {
        // Count non-bypassed plugins in the chain
        return pluginChain?.activePlugins.filter { !$0.isBypassed }.count ?? 0
    }
}

// MARK: - Bus Insert Slot
struct BusInsertSlot: View {
    let slotIndex: Int
    let pluginInstance: PluginInstance?
    let busId: UUID
    let availableTracks: [AudioTrack]
    let availableBuses: [MixerBus]
    let onAddPlugin: (PluginDescriptor) -> Void
    let onToggleBypass: () -> Void
    let onRemoveEffect: () -> Void
    let onOpenEditor: () -> Void
    
    @State private var showingPluginBrowser = false
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            if pluginInstance == nil {
                showingPluginBrowser = true
            } else {
                onOpenEditor()
            }
        }) {
            HStack(spacing: 2) {
                if let pluginInstance = pluginInstance {
                    pluginDisplayView(pluginInstance)
                } else {
                    emptySlotView
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .background(slotBackground)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPluginBrowser) {
            PluginBrowserView(
                onPluginSelected: { plugin in
                    onAddPlugin(plugin)
                    showingPluginBrowser = false
                },
                filterToCategory: .effect
            )
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if let pluginInstance = pluginInstance {
                Button(action: onToggleBypass) {
                    let isBypassed = pluginInstance.isBypassed
                    Label(
                        isBypassed ? "Enable" : "Bypass",
                        systemImage: isBypassed ? "power.circle" : "power.circle.fill"
                    )
                }
                
                Button(action: onOpenEditor) {
                    Label("Edit Effect", systemImage: "slider.horizontal.3")
                }
                
                Divider()
                
                Button(role: .destructive, action: onRemoveEffect) {
                    Label("Remove Effect", systemImage: "trash")
                }
            } else {
                Button(action: { showingPluginBrowser = true }) {
                    Label("Browse AU Plugins...", systemImage: "puzzlepiece.extension")
                }
            }
        }
    }
    
    private func pluginDisplayView(_ instance: PluginInstance) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(instance.isBypassed ? Color.gray : Color.blue)
                .frame(width: 4, height: 4)
            
            Text(instance.descriptor.name)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(instance.isBypassed ? .secondary : .primary)
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
    
    private var emptySlotView: some View {
        Text("---")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity)
    }
    
    private var slotBackground: some View {
        let hasContent = pluginInstance != nil
        
        return RoundedRectangle(cornerRadius: 2)
            .fill(hasContent ? Color.blue.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(
                        isHovered ? Color.accentColor.opacity(0.5) : MixerColors.slotBorder,
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - Bus Inserts Section
struct BusInsertsSection: View {
    let busId: UUID
    let pluginChain: PluginChain?
    let availableTracks: [AudioTrack]
    let availableBuses: [MixerBus]
    let onAddPlugin: (Int, PluginDescriptor) -> Void
    let onToggleBypass: (Int) -> Void
    let onRemoveEffect: (Int) -> Void
    let onOpenEditor: (Int) -> Void
    
    @State private var isExpanded = true
    
    private let maxSlots = 8
    
    var body: some View {
        VStack(spacing: 2) {
            // Section Header
            Button(action: { 
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    
                    Text("INSERTS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(MixerColors.sectionHeader)
                    
                    Spacer()
                    
                    let activeCount = countActivePlugins()
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor)
                            .cornerRadius(3)
                    }
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(0..<maxSlots, id: \.self) { index in
                        BusInsertSlot(
                            slotIndex: index,
                            pluginInstance: pluginChain?.slots[index],
                            busId: busId,
                            availableTracks: availableTracks,
                            availableBuses: availableBuses,
                            onAddPlugin: { descriptor in
                                onAddPlugin(index, descriptor)
                            },
                            onToggleBypass: {
                                onToggleBypass(index)
                            },
                            onRemoveEffect: {
                                onRemoveEffect(index)
                            },
                            onOpenEditor: {
                                onOpenEditor(index)
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MixerColors.slotBackground)
        )
    }
    
    private func countActivePlugins() -> Int {
        return pluginChain?.activePlugins.filter { !$0.isBypassed }.count ?? 0
    }
}
