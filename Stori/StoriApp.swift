//
//  StoriApp.swift
//  Stori
//
//  Created by Gabriel Cardona on 9/1/25.
//

import SwiftUI
import Combine
import AppKit

// MARK: - Window IDs
enum WindowID: String {
    case main = "main-daw"
    case newProject = "new-project"
    case openProject = "open-project"
}

// MARK: - Shared Project Manager
/// Singleton project manager accessible from all windows
class SharedProjectManager {
    static let shared = ProjectManager()
}

// MARK: - Shared Audio Engine
/// Singleton audio engine - a DAW must have exactly ONE audio engine for its lifetime.
/// Multiple windows/views observe this single instance.
@MainActor
class SharedAudioEngine {
    static let shared = AudioEngine()
}

// MARK: - App Delegate
/// Handles macOS app lifecycle events like reopening windows
class StoriAppDelegate: NSObject, NSApplicationDelegate {
    /// Called when user clicks dock icon with no windows open
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows - show or create the main window
            showOrCreateMainWindow()
        }
        return true
    }
    
    /// Called when app is about to terminate
    func applicationWillTerminate(_ notification: Notification) {
        NSLog("🛑 [DIAGNOSTIC] App terminating - cleaning up audio engine")
        
        // Clean up audio engine explicitly (singleton won't deinit)
        Task { @MainActor in
            SharedAudioEngine.shared.cleanup()
        }
        
        TempFileManager.cleanupAll()
        
        NSLog("✅ [DIAGNOSTIC] App cleanup complete")
    }
    
    /// Show existing main window or create a new one
    private func showOrCreateMainWindow() {
        // Try to find and show an existing main window (not dialog windows)
        if let existingWindow = NSApp.windows.first(where: { 
            $0.canBecomeMain && 
            !$0.className.contains("NSPanel") &&
            $0.title != "New Project" &&
            $0.title != "Recent Projects"
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
        } else {
            // Activate the app - SwiftUI's WindowGroup will create a new window
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct StoriApp: App {
    @NSApplicationDelegateAdaptor(StoriAppDelegate.self) var appDelegate
    
    @State private var showingUpdateSheet = false
    
    var body: some Scene {
        // Main DAW Window - uses id for programmatic opening via openWindow(id:)
        WindowGroup(id: WindowID.main.rawValue) {
            ContentView()
                .environment(AppState())
                .task {
                    // Start background update checks
                    UpdateService.shared.startBackgroundChecks()
                }
                .onReceive(NotificationCenter.default.publisher(for: .checkForUpdates)) { _ in
                    Task {
                        await UpdateService.shared.checkNow()
                        showingUpdateSheet = true
                    }
                }
                .sheet(isPresented: $showingUpdateSheet) {
                    UpdateSheetView(updateService: UpdateService.shared)
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentSize)
        .commands {
            // Replace default About menu item with custom About window
            CommandGroup(replacing: .appInfo) {
                Button("About Stori") {
                    NotificationCenter.default.post(name: .showAboutWindow, object: nil)
                }
                
                Divider()
                
                Button(UpdateService.shared.menuItemTitle) {
                    NotificationCenter.default.post(name: .checkForUpdates, object: nil)
                }
                .disabled(!UpdateService.shared.menuItemEnabled)
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            
            // File menu commands
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    handleNewProjectCommand()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Button("Open Project...") {
                    handleOpenProjectCommand()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("Save Project") {
                    NotificationCenter.default.post(name: .saveProject, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Divider()
                
                Button("Export Mix...") {
                    NotificationCenter.default.post(name: .exportProject, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                
                Divider()
                
                Button("Import Audio...") {
                    NotificationCenter.default.post(name: .importAudio, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Clean Up Orphaned Audio Files...") {
                    NotificationCenter.default.post(name: .cleanupOrphanedFiles, object: nil)
                }
            }
            
            // Track menu
            CommandMenu("Track") {
                Button("New Track(s)...") {
                    NotificationCenter.default.post(name: .newTrackDialog, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.shift, .command])
                
                Button("New Audio Track") {
                    NotificationCenter.default.post(name: .newAudioTrack, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.shift, .command])
                
                Button("New MIDI Track") {
                    NotificationCenter.default.post(name: .newMIDITrack, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.shift, .command])
                
                Button("Import MIDI File...") {
                    NotificationCenter.default.post(name: .importMIDIFile, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.control, .command])
                
                Divider()
                
                Button("Split at Playhead") {
                    NotificationCenter.default.post(name: .splitAtPlayhead, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("Join Regions") {
                    NotificationCenter.default.post(name: .joinRegions, object: nil)
                }
                .keyboardShortcut("j", modifiers: .command)
                
                Divider()
                
                Button("Trim Start to Playhead") {
                    NotificationCenter.default.post(name: .trimRegionStart, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)
                
                Button("Trim End to Playhead") {
                    NotificationCenter.default.post(name: .trimRegionEnd, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
                
                Button("Create Crossfade") {
                    NotificationCenter.default.post(name: .createCrossfade, object: nil)
                }
                .keyboardShortcut("x", modifiers: [.command, .option])
                
                Divider()
                
                Button("Snap to Grid") {
                    NotificationCenter.default.post(name: .toggleSnapToGrid, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)
                
                Divider()
                
                Button("Delete Track") {
                    NotificationCenter.default.post(name: .deleteTrack, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            
            // Inspector menu
            CommandMenu("Inspector") {
                Button("Track Inspector") {
                    NotificationCenter.default.post(name: .openTrackInspector, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])
                
                Button("Region Inspector") {
                    NotificationCenter.default.post(name: .openRegionInspector, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])
                
                Button("Project Inspector") {
                    NotificationCenter.default.post(name: .openProjectInspector, object: nil)
                }
                .keyboardShortcut("3", modifiers: [.command, .option])
                
                Divider()
                
                Button("Visual Tab") {
                    NotificationCenter.default.post(name: .openVisualTab, object: nil)
                }
                .keyboardShortcut("4", modifiers: [.command, .option])
                
                Button("Chat Tab") {
                    NotificationCenter.default.post(name: .openChatTab, object: nil)
                }
                .keyboardShortcut("5", modifiers: [.command, .option])
            }
            
            // Transport commands
            CommandMenu("Transport") {
                Button("Play/Pause") {
                    NotificationCenter.default.post(name: .playPause, object: nil)
                }
                .keyboardShortcut(.space)
                
                Button("Stop") {
                    NotificationCenter.default.post(name: .stop, object: nil)
                }
                .keyboardShortcut(.space, modifiers: .control)
                
                Button("Record") {
                    NotificationCenter.default.post(name: .record, object: nil)
                }
                .keyboardShortcut("r")
                
                Divider()
                
                Button("Skip to Beginning") {
                    NotificationCenter.default.post(name: .skipToBeginning, object: nil)
                }
                .keyboardShortcut(.return)
                
                Button("Skip to End") {
                    NotificationCenter.default.post(name: .skipToEnd, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
            
            // MIDI menu
            CommandMenu("MIDI") {
                Button("Virtual Keyboard") {
                    NotificationCenter.default.post(name: .toggleVirtualKeyboard, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Show/Hide Piano Roll") {
                    NotificationCenter.default.post(name: .togglePianoRoll, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                
                Button("Show/Hide Synthesizer") {
                    NotificationCenter.default.post(name: .toggleSynthesizer, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                
                Button("Show/Hide Step Sequencer") {
                    NotificationCenter.default.post(name: .toggleStepSequencer, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
            }
            
            // Help menu
            CommandGroup(replacing: .help) {
                Button("Stori User Guide") {
                    openDocumentation("README.md")
                }
                .keyboardShortcut("?", modifiers: .command)
                
                Button("Main Window Overview") {
                    openDocumentation("getting-started/main-window-overview.md")
                }
                
                Button("UI Element Reference") {
                    openDocumentation("ui-reference/ui-terminology.md")
                }
                
                Divider()
                
                Button("Keyboard Shortcuts") {
                    // TODO: Create keyboard shortcuts reference
                    openDocumentation("README.md")
                }
                
                Divider()
                
                Button("Show Logs in Finder") {
                    AppLogger.shared.openLogsInFinder()
                }
                
                Button("Collect Diagnostics...") {
                    Task {
                        if let zipURL = AppLogger.shared.createDiagnosticsBundle() {
                            // Show in Finder
                            NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                            
                            // Show info alert
                            let alert = NSAlert()
                            alert.messageText = "Diagnostics Collected"
                            alert.informativeText = "A diagnostics bundle has been created at:\n\n\(zipURL.path)\n\nShare this file when reporting issues."
                            alert.alertStyle = .informational
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        } else {
                            let alert = NSAlert()
                            alert.messageText = "Failed to Create Diagnostics"
                            alert.informativeText = "Unable to create the diagnostics bundle. Check ~/Library/Logs/Stori/ manually."
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                    }
                }
                
                Divider()
                
                Button("Report Issue") {
                    if let url = URL(string: "https://github.com/cgcardona/Stori/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        // Standalone New Project Window
        Window("New Project", id: WindowID.newProject.rawValue) {
            StandaloneNewProjectView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        // Standalone Open Project Window
        Window("Recent Projects", id: WindowID.openProject.rawValue) {
            StandaloneOpenProjectView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Standalone New Project View
/// A standalone window version of the New Project dialog
struct StandaloneNewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    private var projectManager = SharedProjectManager.shared
    @FocusState private var isProjectNameFocused: Bool
    
    @State private var projectName = ""
    @State private var tempo: Double = 120
    @State private var animateGradient = false
    @State private var isCreating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated gradient header
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.8),
                    Color.purple.opacity(0.6),
                    Color.pink.opacity(0.4)
                ],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .frame(height: 120)
            .overlay(
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 60, height: 60)
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                    Text("New Project")
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
            
            // Form content
            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    // Project Name
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "textformat")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                            Text("Project Name")
                                .font(.system(size: 14, weight: .medium))
                        }
                        TextField("Untitled", text: $projectName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.controlBackgroundColor))
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                            .focused($isProjectNameFocused)
                    }
                    
                    // Tempo
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "metronome")
                                .font(.system(size: 14))
                                .foregroundColor(.purple)
                            Text("Tempo (BPM)")
                                .font(.system(size: 14, weight: .medium))
                        }
                        TextField("120", value: $tempo, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.controlBackgroundColor))
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Sample Rate (fixed)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 14))
                                .foregroundColor(.pink)
                            Text("Sample Rate")
                                .font(.system(size: 14, weight: .medium))
                        }
                        HStack {
                            Text("44.1 kHz")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("(Fixed)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.controlBackgroundColor).opacity(0.5))
                                .stroke(Color.pink.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                
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
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Button(action: createProject) {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "plus.circle.fill")
                            }
                            Text(isCreating ? "Creating..." : "Create Project")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(isCreating || projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 520, height: 480)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(16)
        .onAppear {
            // Focus the project name field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isProjectNameFocused = true
            }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private func createProject() {
        // Use placeholder name if empty
        let finalName = projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
            ? "Untitled" 
            : projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isCreating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            do {
                try projectManager.createNewProject(
                    name: finalName,
                    tempo: tempo
                )
                
                // Close this standalone window
                closeStandaloneWindow()
                
                // Open the main DAW window using SwiftUI's native window management
                openWindow(id: WindowID.main.rawValue)
            } catch {
                isCreating = false
            }
        }
    }
}

// MARK: - Standalone Open Project View
/// A standalone window version of the Recent Projects browser
struct StandaloneOpenProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    private var projectManager = SharedProjectManager.shared
    
    @State private var showingDeleteAlert = false
    @State private var projectToDelete: AudioProject?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recent Projects")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Project list
            if projectManager.recentProjects.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Recent Projects")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Create a new project to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(projectManager.recentProjects) { project in
                            ProjectRow(project: project) {
                                openProject(project)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    projectToDelete = project
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete Project", systemImage: "trash")
                                }
                            }
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            projectManager.loadRecentProjects()
        }
        .alert("Delete Project", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    projectManager.deleteProject(project)
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(projectToDelete?.name ?? "")\"? This cannot be undone.")
        }
    }
    
    private func openProject(_ project: AudioProject) {
        projectManager.loadProject(project)
        
        // Close this standalone window
        closeStandaloneWindow()
        
        // Open the main DAW window using SwiftUI's native window management
        openWindow(id: WindowID.main.rawValue)
    }
}

// MARK: - Project Row for Standalone Browser
private struct ProjectRow: View {
    let project: AudioProject
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Project icon
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.8), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    )
                
                // Project info
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(project.tracks.count) tracks • \(Int(project.tempo)) BPM")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Modified: \(project.modifiedAt, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
    }
}

// MARK: - Window Command Handlers

/// Handles Cmd+N - shows new project dialog (standalone if no main window)
private func handleNewProjectCommand() {
    let hasMainWindow = hasVisibleMainWindow()
    
    if hasMainWindow {
        // Main window exists, use sheet
        NotificationCenter.default.post(name: .newProject, object: nil)
    } else {
        // No main window, open standalone window
        openStandaloneWindow(id: .newProject)
    }
}

/// Handles Cmd+O - shows open project dialog (standalone if no main window)
private func handleOpenProjectCommand() {
    let hasMainWindow = hasVisibleMainWindow()
    
    if hasMainWindow {
        // Main window exists, use sheet
        NotificationCenter.default.post(name: .openProject, object: nil)
    } else {
        // No main window, open standalone window
        openStandaloneWindow(id: .openProject)
    }
}

/// Check if there's a visible main DAW window
private func hasVisibleMainWindow() -> Bool {
    return NSApp.windows.contains { window in
        window.isVisible &&
        window.canBecomeMain &&
        !window.className.contains("NSPanel") &&
        window.contentView != nil &&
        window.title != "New Project" &&
        window.title != "Recent Projects"
    }
}

/// Close the current standalone window
private func closeStandaloneWindow() {
    // Find and close the standalone dialog window
    for window in NSApp.windows {
        if window.title == "New Project" || window.title == "Recent Projects" {
            window.close()
        }
    }
}


/// Open a standalone dialog window using AppKit
private func openStandaloneWindow(id: WindowID) {
    NSApp.activate(ignoringOtherApps: true)
    
    // Check if the window already exists
    let existingWindow = NSApp.windows.first { window in
        if id == .newProject {
            return window.title == "New Project"
        } else {
            return window.title == "Recent Projects"
        }
    }
    
    if let window = existingWindow {
        window.makeKeyAndOrderFront(nil)
        return
    }
    
    // Create the window content
    let contentView: AnyView
    let windowTitle: String
    let windowSize: CGSize
    
    switch id {
    case .main:
        // Main window is handled by SwiftUI's WindowGroup, not standalone AppKit windows
        return
    case .newProject:
        contentView = AnyView(StandaloneNewProjectView())
        windowTitle = "New Project"
        windowSize = CGSize(width: 520, height: 480)
    case .openProject:
        contentView = AnyView(StandaloneOpenProjectView())
        windowTitle = "Recent Projects"
        windowSize = CGSize(width: 500, height: 400)
    }
    
    // Create NSWindow with SwiftUI content
    let hostingController = NSHostingController(rootView: contentView)
    
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    
    window.title = windowTitle
    window.contentViewController = hostingController
    window.center()
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
    window.level = .floating
    
    window.makeKeyAndOrderFront(nil)
}

// MARK: - Documentation Helper
private func openDocumentation(_ relativePath: String) {
    // Map relative paths to actual file names in bundle
    let fileName: String
    switch relativePath {
    case "README.md":
        fileName = "README"
    case "getting-started/main-window-overview.md":
        fileName = "main-window-overview"
    case "ui-reference/ui-terminology.md":
        fileName = "ui-terminology"
    default:
        fileName = relativePath.replacingOccurrences(of: ".md", with: "")
    }
    
    // Try to find the file in the app bundle first
    if let bundlePath = Bundle.main.path(forResource: fileName, ofType: "md") {
        let url = URL(fileURLWithPath: bundlePath)
        NSWorkspace.shared.open(url)
        return
    }
    
    // Fallback: Try documentation subfolder in bundle
    if let bundlePath = Bundle.main.path(forResource: fileName, ofType: "md", inDirectory: "documentation") {
        let url = URL(fileURLWithPath: bundlePath)
        NSWorkspace.shared.open(url)
        return
    }
    
    // Final fallback: Show user-friendly alert
    DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = "Documentation Not Available"
        alert.informativeText = "The requested documentation file could not be found in the app bundle."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - App State
@Observable
class AppState {
    var currentProject: AudioProject?
    
    // CRITICAL: Protective deinit for @Observable class (ASan Issue #84742+)
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
    deinit {
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let newProject = Notification.Name("newProject")
    static let openProject = Notification.Name("openProject")
    static let willSaveProject = Notification.Name("willSaveProject")  // Posted before save to collect plugin states
    static let pluginConfigsSaved = Notification.Name("pluginConfigsSaved")  // Posted when AudioEngine finishes saving plugin configs
    static let saveProject = Notification.Name("saveProject")
    
    // Issue #63: Transport-ProjectManager save coordination notifications
    static let queryTransportState = Notification.Name("queryTransportState")  // Query if transport is playing
    static let pauseTransportForSave = Notification.Name("pauseTransportForSave")  // Request transport pause for save
    static let transportPausedForSave = Notification.Name("transportPausedForSave")  // Transport confirms pause
    static let resumeTransportAfterSave = Notification.Name("resumeTransportAfterSave")  // Resume transport after save
    static let exportProject = Notification.Name("exportProject")
    static let importAudio = Notification.Name("importAudio")
    static let importMIDIFile = Notification.Name("importMIDIFile")
    static let cleanupOrphanedFiles = Notification.Name("cleanupOrphanedFiles")
    static let newTrack = Notification.Name("newTrack")
    static let newTrackDialog = Notification.Name("newTrackDialog")
    static let newAudioTrack = Notification.Name("newAudioTrack")
    static let newMIDITrack = Notification.Name("newMIDITrack")
    static let deleteTrack = Notification.Name("deleteTrack")
    static let playPause = Notification.Name("playPause")
    static let stop = Notification.Name("stop")
    static let record = Notification.Name("record")
    static let skipToBeginning = Notification.Name("skipToBeginning")
    static let skipToEnd = Notification.Name("skipToEnd")
    static let toggleMixer = Notification.Name("toggleMixer")
    static let toggleLibrary = Notification.Name("toggleLibrary")
    static let toggleInspector = Notification.Name("toggleInspector")
    static let toggleSelection = Notification.Name("toggleSelection")
    static let toggleStepSequencer = Notification.Name("toggleStepSequencer")
    static let openLibrarySounds = Notification.Name("openLibrarySounds")
    static let openLibraryPlugins = Notification.Name("openLibraryPlugint s")
    static let openLibraryInstruments = Notification.Name("openLibraryInstruments")
    static let openTrackInspector = Notification.Name("openTrackInspector")
    static let openRegionInspector = Notification.Name("openRegionInspector")
    static let openProjectInspector = Notification.Name("openProjectInspector")
    static let openChatTab = Notification.Name("openChatTab")
    static let openVisualTab = Notification.Name("openVisualTab")
    static let projectUpdated = Notification.Name("projectUpdated")
    static let tempoChanged = Notification.Name("tempoChanged")  // Posted when project tempo changes during playback
    /// Posted when audio device change completed successfully. userInfo["message"] (String) optional.
    static let audioDeviceChangeSucceeded = Notification.Name("audioDeviceChangeSucceeded")
    /// Posted when engine failed to restart after device change. userInfo["message"] (String).
    static let audioDeviceChangeFailed = Notification.Name("audioDeviceChangeFailed")
    /// Posted when a plugin failed to load (isolated, DAW continues). userInfo["pluginName"] (String), ["message"] (String).
    static let pluginLoadFailed = Notification.Name("pluginLoadFailed")
    /// Posted when a project was auto-repaired on load. userInfo["message"] (String).
    static let projectRepaired = Notification.Name("projectRepaired")
    static let showServiceDiagnostics = Notification.Name("showServiceDiagnostics")
    static let showAboutWindow = Notification.Name("showAboutWindow")
    static let toggleSnapToGrid = Notification.Name("toggleSnapToGrid")
    static let showTokenInput = Notification.Name("showTokenInput")
    
    // Edit notifications
    static let splitAtPlayhead = Notification.Name("splitAtPlayhead")
    static let joinRegions = Notification.Name("joinRegions")
    static let trimRegionStart = Notification.Name("trimRegionStart")
    static let trimRegionEnd = Notification.Name("trimRegionEnd")
    static let nudgeRegionsLeft = Notification.Name("nudgeRegionsLeft")
    static let nudgeRegionsRight = Notification.Name("nudgeRegionsRight")
    static let selectNextRegion = Notification.Name("selectNextRegion")
    static let selectPreviousRegion = Notification.Name("selectPreviousRegion")
    static let selectRegionAbove = Notification.Name("selectRegionAbove")
    static let selectRegionBelow = Notification.Name("selectRegionBelow")
    static let createCrossfade = Notification.Name("createCrossfade")
    static let zoomToSelection = Notification.Name("zoomToSelection")
    static let goToNextRegion = Notification.Name("goToNextRegion")
    static let goToPreviousRegion = Notification.Name("goToPreviousRegion")
    static let moveBeatForward = Notification.Name("moveBeatForward")
    static let moveBeatBackward = Notification.Name("moveBeatBackward")
    static let moveBarForward = Notification.Name("moveBarForward")
    static let moveBarBackward = Notification.Name("moveBarBackward")
    
    // Blockchain notifications
    static let tokenizeProject = Notification.Name("tokenizeProject")
    static let openMarketplace = Notification.Name("openMarketplace")
    static let openWalletTab = Notification.Name("openWalletTab")
    static let showMyDigitalMasters = Notification.Name("showMyDigitalMasters")
    static let showWalletConnection = Notification.Name("showWalletConnection")
    static let showMyLibrary = Notification.Name("showMyLibrary")
    static let showMyPurchases = Notification.Name("showMyPurchases")
    
    // Update and setup notifications
    static let checkForUpdates = Notification.Name("checkForUpdates")
}
