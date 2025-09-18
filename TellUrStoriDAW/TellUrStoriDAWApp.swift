//
//  TellUrStoriDAWApp.swift
//  TellUrStoriDAW
//
//  Created by Gabriel Cardona on 9/1/25.
//

import SwiftUI

@main
struct TellUrStoriDAWApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppState())
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentSize)
        .commands {
            // File menu commands
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    NotificationCenter.default.post(name: .newProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Button("Open Project...") {
                    NotificationCenter.default.post(name: .openProject, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("Save Project") {
                    NotificationCenter.default.post(name: .saveProject, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            
            // Track menu
            CommandMenu("Track") {
                Button("New Track") {
                    NotificationCenter.default.post(name: .newTrack, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.shift, .command])
                
                Divider()
                
                Button("Delete Track") {
                    NotificationCenter.default.post(name: .deleteTrack, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
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
                .keyboardShortcut(.space, modifiers: .command)
                
                Button("Record") {
                    NotificationCenter.default.post(name: .record, object: nil)
                }
                .keyboardShortcut("r")
                
                Divider()
                
                Button("Skip to Beginning") {
                    NotificationCenter.default.post(name: .skipToBeginning, object: nil)
                }
                .keyboardShortcut(.home)
                
                Button("Skip to End") {
                    NotificationCenter.default.post(name: .skipToEnd, object: nil)
                }
                .keyboardShortcut(.end)
            }
            
            // Help menu
            CommandGroup(replacing: .help) {
                Button("TellUrStori User Guide") {
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
                
                Button("Report Issue") {
                    if let url = URL(string: "https://github.com/cgcardona/TellUrStoriDAW/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
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
class AppState: ObservableObject {
    @Published var currentProject: AudioProject?
}

// MARK: - Notification Names
extension Notification.Name {
    static let newProject = Notification.Name("newProject")
    static let openProject = Notification.Name("openProject")
    static let saveProject = Notification.Name("saveProject")
    static let newTrack = Notification.Name("newTrack")
    static let deleteTrack = Notification.Name("deleteTrack")
    static let playPause = Notification.Name("playPause")
    static let stop = Notification.Name("stop")
    static let record = Notification.Name("record")
    static let skipToBeginning = Notification.Name("skipToBeginning")
    static let skipToEnd = Notification.Name("skipToEnd")
    static let toggleMixer = Notification.Name("toggleMixer")
    static let toggleLibrary = Notification.Name("toggleLibrary")
    static let toggleInspector = Notification.Name("toggleInspector")
}
