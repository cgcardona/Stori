//
//  EditableNumeric.swift
//  TellUrStoriDAW
//
//  Universal numeric value editing component with validation and formatting
//

import SwiftUI

struct EditableNumeric<T: Numeric & LosslessStringConvertible & Comparable>: View {
    let value: T
    let range: ClosedRange<T>?
    let unit: String?
    let formatter: NumberFormatter?
    let onValueChanged: (T) -> Void
    
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isTextFieldFocused: Bool
    
    // Styling options
    let font: Font
    let foregroundColor: Color
    let editingStyle: EditingStyle
    let helpText: String?
    let precision: Int?
    
    init(
        value: T,
        range: ClosedRange<T>? = nil,
        unit: String? = nil,
        formatter: NumberFormatter? = nil,
        precision: Int? = nil,
        font: Font = .body,
        foregroundColor: Color = .primary,
        editingStyle: EditingStyle = .roundedBorder,
        helpText: String? = "Double-click to edit value",
        onValueChanged: @escaping (T) -> Void
    ) {
        self.value = value
        self.range = range
        self.unit = unit
        self.formatter = formatter
        self.precision = precision
        self.font = font
        self.foregroundColor = foregroundColor
        self.editingStyle = editingStyle
        self.helpText = helpText
        self.onValueChanged = onValueChanged
    }
    
    var body: some View {
        Group {
            if isEditing {
                editingView
            } else {
                displayView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
    
    // MARK: - Display View
    private var displayView: some View {
        HStack(spacing: 2) {
            Text(formattedValue)
                .font(font)
                .foregroundColor(foregroundColor)
            
            if let unit = unit {
                Text(unit)
                    .font(font)
                    .foregroundColor(.secondary)
            }
        }
        .onTapGesture(count: 2) {
            startEditing()
        }
        .help(helpText ?? "Double-click to edit value")
        .contentShape(Rectangle())
    }
    
    // MARK: - Editing View
    private var editingView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                editingStyle.apply(to:
                    TextField("Value", text: $editingText)
                        .font(font)
                        .foregroundColor(foregroundColor)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            commitEdit()
                        }
                        .onExitCommand {
                            cancelEdit()
                        }
                        .onChange(of: editingText) { _, newValue in
                            validateText(newValue)
                        }
                )
                
                if let unit = unit {
                    Text(unit)
                        .font(font)
                        .foregroundColor(.secondary)
                }
            }
            
            // Error message
            if showingError && !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
            
            // Range hint
            if let range = range {
                Text("Range: \(formatValue(range.lowerBound)) - \(formatValue(range.upperBound))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var formattedValue: String {
        return formatValue(value)
    }
    
    
    // MARK: - Helper Methods
    private func formatValue(_ val: T) -> String {
        if let formatter = formatter {
            return formatter.string(from: NSNumber(value: val as! Double)) ?? String(val)
        } else if let precision = precision, T.self == Double.self || T.self == Float.self {
            return String(format: "%.\(precision)f", val as! Double)
        } else {
            return String(val)
        }
    }
    
    private func startEditing() {
        editingText = String(value)
        isEditing = true
        showingError = false
        errorMessage = ""
        
        // Focus the text field after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }
    
    private func commitEdit() {
        let trimmedText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse the value
        guard let newValue = T(trimmedText) else {
            showError("Invalid number format")
            return
        }
        
        // Validate range
        if let range = range, !range.contains(newValue) {
            showError("Value must be between \(formatValue(range.lowerBound)) and \(formatValue(range.upperBound))")
            return
        }
        
        // Commit the change
        onValueChanged(newValue)
        isEditing = false
        showingError = false
    }
    
    private func cancelEdit() {
        editingText = String(value)
        isEditing = false
        showingError = false
        errorMessage = ""
    }
    
    private func validateText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it's a valid number
        guard let newValue = T(trimmedText) else {
            if !trimmedText.isEmpty {
                showError("Invalid number format")
            } else {
                showingError = false
            }
            return
        }
        
        // Check range
        if let range = range, !range.contains(newValue) {
            showError("Value must be between \(formatValue(range.lowerBound)) and \(formatValue(range.upperBound))")
        } else {
            showingError = false
            errorMessage = ""
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Convenience Initializers

extension EditableNumeric where T == Double {
    static func percentage(
        value: Double,
        font: Font = .body,
        onValueChanged: @escaping (Double) -> Void
    ) -> EditableNumeric<Double> {
        return EditableNumeric(
            value: value,
            range: 0.0...100.0,
            unit: "%",
            precision: 1,
            font: font,
            helpText: "Double-click to edit percentage",
            onValueChanged: onValueChanged
        )
    }
    
    static func decibels(
        value: Double,
        range: ClosedRange<Double> = -60.0...12.0,
        font: Font = .body,
        onValueChanged: @escaping (Double) -> Void
    ) -> EditableNumeric<Double> {
        return EditableNumeric(
            value: value,
            range: range,
            unit: "dB",
            precision: 1,
            font: font,
            helpText: "Double-click to edit level",
            onValueChanged: onValueChanged
        )
    }
    
    static func frequency(
        value: Double,
        range: ClosedRange<Double> = 20.0...20000.0,
        font: Font = .body,
        onValueChanged: @escaping (Double) -> Void
    ) -> EditableNumeric<Double> {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        
        return EditableNumeric(
            value: value,
            range: range,
            unit: "Hz",
            formatter: formatter,
            font: font,
            helpText: "Double-click to edit frequency",
            onValueChanged: onValueChanged
        )
    }
    
    static func milliseconds(
        value: Double,
        range: ClosedRange<Double> = 0.0...5000.0,
        font: Font = .body,
        onValueChanged: @escaping (Double) -> Void
    ) -> EditableNumeric<Double> {
        return EditableNumeric(
            value: value,
            range: range,
            unit: "ms",
            precision: 0,
            font: font,
            helpText: "Double-click to edit time",
            onValueChanged: onValueChanged
        )
    }
}

extension EditableNumeric where T == Int {
    static func bpm(
        value: Int,
        range: ClosedRange<Int> = 60...200,
        font: Font = .body,
        onValueChanged: @escaping (Int) -> Void
    ) -> EditableNumeric<Int> {
        return EditableNumeric(
            value: value,
            range: range,
            unit: "BPM",
            font: font,
            helpText: "Double-click to edit tempo",
            onValueChanged: onValueChanged
        )
    }
    
    static func sampleRate(
        value: Int,
        font: Font = .body,
        onValueChanged: @escaping (Int) -> Void
    ) -> EditableNumeric<Int> {
        return EditableNumeric(
            value: value,
            range: 44100...192000,
            unit: "Hz",
            font: font,
            helpText: "Double-click to edit sample rate",
            onValueChanged: onValueChanged
        )
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        EditableNumeric.bpm(value: 120) { newValue in
            print("BPM changed to: \(newValue)")
        }
        
        EditableNumeric.decibels(value: -12.5) { newValue in
            print("Level changed to: \(newValue)")
        }
        
        EditableNumeric.frequency(value: 1000.0) { newValue in
            print("Frequency changed to: \(newValue)")
        }
        
        EditableNumeric.percentage(value: 75.0) { newValue in
            print("Percentage changed to: \(newValue)")
        }
    }
    .padding()
}
