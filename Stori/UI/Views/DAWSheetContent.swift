//
//  DAWSheetContent.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - DAW Sheet Content View

struct DAWSheetContent: View {
    let sheet: DAWSheet
    
    var body: some View {
        switch sheet {
        case .virtualKeyboard:
            VirtualKeyboardView()
        }
    }
}
