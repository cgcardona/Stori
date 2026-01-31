//
//  ExportProgressView.swift
//  Stori
//
//  Progress indicator for project export operations
//

import SwiftUI

struct ExportProgressView: View {
    let progress: Double
    let status: String
    let elapsedTime: TimeInterval
    let estimatedTimeRemaining: TimeInterval?
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            // Progress card
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, options: .repeating)
                
                // Title
                Text("Exporting Project")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 280)
                    
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
                
                // Percentage and Time
                HStack(spacing: 16) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    if let timeRemaining = estimatedTimeRemaining, timeRemaining > 0 {
                        Text("\(formatTime(timeRemaining)) remaining")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(formatTime(elapsedTime)) elapsed")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Cancel button
                Button(action: onCancel) {
                    Text("Cancel Export")
                        .font(.system(.body, design: .default))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(32)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            }
            .frame(width: 360)
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
