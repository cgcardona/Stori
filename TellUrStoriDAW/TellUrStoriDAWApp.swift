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
        }
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
