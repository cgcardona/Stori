//
//  TransactionColorBorder.swift
//  Stori
//
//  Color-coded left border for transaction rows for quick visual scanning
//

import SwiftUI

/// Transaction type color coding
enum TransactionBorderColor {
    case receive  // Green
    case send     // Red
    case nft      // Purple
    case contract // Blue
    
    var color: Color {
        switch self {
        case .receive: return hexColor("10B981")
        case .send: return hexColor("EF4444")
        case .nft: return hexColor("8B5CF6")
        case .contract: return hexColor("3B82F6")
        }
    }
}

/// Adds a color-coded left border to transaction rows
struct TransactionColorBorderModifier: ViewModifier {
    let borderColor: TransactionBorderColor
    
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            // Color-coded left border
            Rectangle()
                .fill(borderColor.color)
                .frame(width: 3)
            
            content
        }
    }
}

extension View {
    /// Adds a color-coded left border based on transaction type
    func transactionBorder(_ color: TransactionBorderColor) -> some View {
        modifier(TransactionColorBorderModifier(borderColor: color))
    }
}

/// Helper function for hex colors (if not already defined globally)
private func hexColor(_ hex: String) -> Color {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default: (a, r, g, b) = (255, 0, 0, 0)
    }
    return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
}
