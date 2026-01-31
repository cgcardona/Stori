//
//  ContentView.swift
//  Stori
//
//  Created by Gabriel Cardona on 9/1/25.
//

import SwiftUI

struct ContentView: View {
    private var projectManager = SharedProjectManager.shared
    
    var body: some View {
        MainDAWView()
            .frame(minWidth: 800, minHeight: 600)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Dynamic window title - shows project name when open
            .navigationTitle(projectManager.currentProject?.name ?? "")
    }
}
