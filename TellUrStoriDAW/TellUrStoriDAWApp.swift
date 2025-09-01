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
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentSize)
        .commands {
            // File menu commands
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    // Handle new project
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            // Transport commands
            CommandGroup(after: .toolbar) {
                Menu("Transport") {
                    Button("Play/Pause") {
                        // Handle play/pause
                    }
                    .keyboardShortcut(.space)
                    
                    Button("Stop") {
                        // Handle stop
                    }
                    .keyboardShortcut(.space, modifiers: .command)
                    
                    Button("Record") {
                        // Handle record
                    }
                    .keyboardShortcut("r")
                }
            }
        }
    }
}
