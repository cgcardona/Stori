//
//  GasControls.swift
//  Stori
//
//  Gas fee controls with Simple/Advanced modes
//

import SwiftUI
import BigInt

enum GasSpeed: String, CaseIterable {
    case slow = "Slow"
    case standard = "Standard"
    case fast = "Fast"
    
    var icon: String {
        switch self {
        case .slow: return "tortoise.fill"
        case .standard: return "hare.fill"
        case .fast: return "bolt.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .slow: return .blue
        case .standard: return .green
        case .fast: return .orange
        }
    }
    
    var estimatedTime: String {
        switch self {
        case .slow: return "~2-5 min"
        case .standard: return "~30-60 sec"
        case .fast: return "~15-30 sec"
        }
    }
}

struct GasControls: View {
    @Binding var mode: GasControlMode
    @Binding var simpleSpeed: GasSpeed
    @Binding var maxFeePerGas: String
    @Binding var maxPriorityFee: String
    @Binding var gasLimit: String
    
    enum GasControlMode {
        case simple
        case advanced
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Mode toggle
            HStack {
                Text("Gas Settings")
                    .font(.headline)
                
                Spacer()
                
                Picker("Mode", selection: $mode) {
                    Text("Simple").tag(GasControlMode.simple)
                    Text("Advanced").tag(GasControlMode.advanced)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            
            switch mode {
            case .simple:
                SimpleGasSelector(speed: $simpleSpeed)
            case .advanced:
                AdvancedGasControls(
                    maxFee: $maxFeePerGas,
                    priorityFee: $maxPriorityFee,
                    gasLimit: $gasLimit
                )
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Simple Gas Selector

struct SimpleGasSelector: View {
    @Binding var speed: GasSpeed
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(GasSpeed.allCases, id: \.self) { gasSpeed in
                Button(action: { speed = gasSpeed }) {
                    HStack(spacing: 12) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(gasSpeed.color.opacity(0.15))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: gasSpeed.icon)
                                .font(.system(size: 16))
                                .foregroundColor(gasSpeed.color)
                        }
                        
                        // Info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gasSpeed.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text(gasSpeed.estimatedTime)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Selection indicator
                        if speed == gasSpeed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(gasSpeed.color)
                        } else {
                            Circle()
                                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 2)
                                .frame(width: 20, height: 20)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(speed == gasSpeed ? gasSpeed.color.opacity(0.08) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                speed == gasSpeed ? gasSpeed.color.opacity(0.3) : Color.secondary.opacity(0.15),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Advanced Gas Controls

struct AdvancedGasControls: View {
    @Binding var maxFee: String
    @Binding var priorityFee: String
    @Binding var gasLimit: String
    
    var body: some View {
        VStack(spacing: 12) {
            // Warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Advanced settings — only modify if you understand gas mechanics")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(8)
            
            // Max Fee Per Gas
            LabeledGasField(
                label: "Max Fee (gwei)",
                hint: "Max you'll pay per gas unit",
                value: $maxFee,
                icon: "gauge.high"
            )
            
            // Priority Fee
            LabeledGasField(
                label: "Priority Fee (gwei)",
                hint: "Tip to validators for faster inclusion",
                value: $priorityFee,
                icon: "speedometer"
            )
            
            // Gas Limit
            LabeledGasField(
                label: "Gas Limit",
                hint: "Max gas units to use (21000 for simple transfers)",
                value: $gasLimit,
                icon: "fuelpump"
            )
            
            // Cost estimate
            if let estimate = calculateMaxCost() {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Max Transaction Cost")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(estimate)
                            .font(.system(size: 14, weight: .bold))
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }
    
    private func calculateMaxCost() -> String? {
        guard let maxFeeGwei = Double(maxFee),
              let limit = Double(gasLimit),
              maxFeeGwei > 0, limit > 0 else {
            return nil
        }
        
        // Convert gwei to ETH/TUS
        let maxCostETH = (maxFeeGwei * limit) / 1_000_000_000
        return String(format: "%.6f TUS", maxCostETH)
    }
}

// MARK: - Labeled Gas Field

struct LabeledGasField: View {
    let label: String
    let hint: String
    @Binding var value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            
            TextField(hint, text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
        }
    }
}
