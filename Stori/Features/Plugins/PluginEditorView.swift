//
//  PluginEditorView.swift
//  Stori
//
//  Hosts Audio Unit plugin custom UIs and provides a generic fallback UI.
//

import SwiftUI
import CoreAudioKit
import AVFoundation

// MARK: - Plugin Editor View

struct PluginEditorView: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Bindable var plugin: PluginInstance
    @State private var viewController: NSViewController?
    @State private var isLoadingUI: Bool = true
    @State private var showGenericUI: Bool = false
    @State private var selectedPreset: AUAudioUnitPreset?
    @State private var showPresetMenu: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar
            
            Divider()
            
            // Plugin UI content
            pluginContent
        }
        .frame(minWidth: 400, minHeight: 300)
        .task {
            await loadPluginUI()
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Plugin info
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.descriptor.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("by \(plugin.descriptor.manufacturer)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Preset selector
            presetMenu
            
            // Bypass toggle
            Toggle(isOn: $plugin.isBypassed) {
                Text("Bypass")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .onChange(of: plugin.isBypassed) { _, newValue in
                plugin.setBypass(newValue)
            }
            
            // UI toggle button
            Button(action: { showGenericUI.toggle() }) {
                Image(systemName: showGenericUI ? "slider.horizontal.3" : "rectangle.on.rectangle")
            }
            .help(showGenericUI ? "Show Custom UI" : "Show Generic Controls")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Preset Menu
    
    private var presetMenu: some View {
        Menu {
            let presets = plugin.getFactoryPresets()
            
            if presets.isEmpty {
                Text("No Factory Presets")
                    .foregroundColor(.secondary)
            } else {
                ForEach(presets, id: \.number) { preset in
                    Button(preset.name) {
                        plugin.selectPreset(preset)
                        selectedPreset = preset
                    }
                }
            }
            
            Divider()
            
            Button("Reset to Default") {
                // Reset by reloading with same sample rate
                Task {
                    let sampleRate = audioEngine.currentSampleRate
                    plugin.unload()
                    try? await plugin.load(sampleRate: sampleRate)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(plugin.currentPresetName)
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(4)
        }
    }
    
    // MARK: - Plugin Content
    
    @ViewBuilder
    private var pluginContent: some View {
        if !plugin.isLoaded {
            notLoadedView
        } else if showGenericUI {
            GenericPluginUIView(plugin: plugin)
        } else if let vc = viewController {
            PluginViewControllerRepresentable(viewController: vc)
        } else if isLoadingUI {
            loadingView
        } else {
            // No custom UI available, show generic
            GenericPluginUIView(plugin: plugin)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading plugin UI...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var notLoadedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Plugin Not Loaded")
                .font(.headline)
            
            if let error = plugin.loadError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Try Loading Again") {
                Task {
                    try? await plugin.load(sampleRate: audioEngine.currentSampleRate)
                    await loadPluginUI()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Load UI
    
    private func loadPluginUI() async {
        guard plugin.isLoaded else {
            isLoadingUI = false
            return
        }
        
        isLoadingUI = true
        viewController = await plugin.requestViewController()
        isLoadingUI = false
        
        // If no custom UI, switch to generic
        if viewController == nil {
            showGenericUI = true
        }
    }
}

// MARK: - NSViewController Wrapper

struct PluginViewControllerRepresentable: NSViewControllerRepresentable {
    let viewController: NSViewController
    
    func makeNSViewController(context: Context) -> NSViewController {
        return viewController
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Generic Plugin UI

struct GenericPluginUIView: View {
    var plugin: PluginInstance
    @State private var searchText = ""
    
    var filteredParameters: [PluginParameter] {
        if searchText.isEmpty {
            return plugin.parameters
        }
        return plugin.parameters.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar for parameters
            if plugin.parameters.count > 10 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search parameters...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                .padding()
                
                Divider()
            }
            
            // Parameter grid
            if filteredParameters.isEmpty {
                emptyState
            } else {
                parameterGrid
            }
        }
    }
    
    private var parameterGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(filteredParameters) { param in
                    ParameterSliderView(
                        parameter: param,
                        onChange: { newValue in
                            plugin.setParameter(address: param.address, value: newValue)
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            if plugin.parameters.isEmpty {
                Text("No Parameters Available")
                    .font(.headline)
                Text("This plugin doesn't expose any parameters.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No Matching Parameters")
                    .font(.headline)
                Button("Clear Search") {
                    searchText = ""
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Parameter Slider View

struct ParameterSliderView: View {
    let parameter: PluginParameter
    let onChange: (AUValue) -> Void
    
    @State private var value: Double
    @State private var isEditing: Bool = false
    
    init(parameter: PluginParameter, onChange: @escaping (AUValue) -> Void) {
        self.parameter = parameter
        self.onChange = onChange
        self._value = State(initialValue: Double(parameter.value))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Parameter name and value
            HStack {
                Text(parameter.name)
                    .font(.caption)
                    .lineLimit(1)
                
                Spacer()
                
                Text(formattedValue)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(isEditing ? .accentColor : .secondary)
            }
            
            // Slider
            Slider(
                value: $value,
                in: Double(parameter.minValue)...Double(parameter.maxValue)
            ) { editing in
                isEditing = editing
                if !editing {
                    onChange(AUValue(value))
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
        .onChange(of: parameter.value) { _, newValue in
            // Sync if changed externally
            if !isEditing {
                value = Double(newValue)
            }
        }
    }
    
    private var formattedValue: String {
        let unit = parameter.unit.isEmpty ? "" : " \(parameter.unit)"
        
        // Format based on range
        let range = parameter.maxValue - parameter.minValue
        if range > 100 {
            return String(format: "%.0f%@", value, unit)
        } else if range > 10 {
            return String(format: "%.1f%@", value, unit)
        } else {
            return String(format: "%.2f%@", value, unit)
        }
    }
}

// MARK: - Plugin Editor Window

/// Opens a plugin editor in a standalone window
class PluginEditorWindow: NSObject {
    private var windowController: NSWindowController?
    
    @MainActor
    static func open(for plugin: PluginInstance, audioEngine: AudioEngine) {
        let editorView = PluginEditorView(plugin: plugin)
            .environment(audioEngine)
        let hostingController = NSHostingController(rootView: editorView)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = "\(plugin.descriptor.name) - \(plugin.descriptor.manufacturer)"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 600, height: 400))
        window.center()
        
        let windowController = NSWindowController(window: window)
        windowController.showWindow(nil)
        
        // Keep window alive
        objc_setAssociatedObject(window, "windowController", windowController, .OBJC_ASSOCIATION_RETAIN)
    }
}
