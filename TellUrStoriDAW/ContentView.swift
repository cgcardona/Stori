//
//  ContentView.swift
//  TellUrStoriDAW
//
//  Created by Gabriel Cardona on 9/1/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MainDAWView()
            .frame(minWidth: 800, minHeight: 600)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
}
