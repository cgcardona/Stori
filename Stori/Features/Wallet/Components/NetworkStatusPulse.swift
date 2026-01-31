//
//  NetworkStatusPulse.swift
//  Stori
//
//  Animated network status indicator with pulse effect
//

import SwiftUI

/// Network status with pulsing animation
struct NetworkStatusPulse: View {
    enum Status {
        case connected
        case syncing
        case disconnected
        
        var color: Color {
            switch self {
            case .connected: return .green
            case .syncing: return .orange
            case .disconnected: return .red
            }
        }
        
        var label: String {
            switch self {
            case .connected: return "Connected"
            case .syncing: return "Syncing"
            case .disconnected: return "Disconnected"
            }
        }
    }
    
    let status: Status
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                // Pulse ring (only for connected)
                if status == .connected {
                    Circle()
                        .stroke(status.color.opacity(0.3), lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }
                
                // Core dot
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 16, height: 16)
            
            Text(status.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(status.color)
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: status) { _, _ in
            // Reset and restart animation on status change
            scale = 1.0
            opacity = 1.0
            startAnimation()
        }
    }
    
    private func startAnimation() {
        switch status {
        case .connected:
            // Gentle pulse for connected state
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: false)
            ) {
                scale = 1.8
                opacity = 0.0
            }
        case .syncing:
            // Quick flash for syncing
            withAnimation(
                .easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true)
            ) {
                opacity = 0.3
            }
        case .disconnected:
            // No animation for disconnected
            break
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        NetworkStatusPulse(status: .connected)
        NetworkStatusPulse(status: .syncing)
        NetworkStatusPulse(status: .disconnected)
    }
    .padding()
}
