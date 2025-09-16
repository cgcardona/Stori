//
//  EditableSlider.swift
//  TellUrStoriDAW
//
//  Slider component with double-click value editing for precise control
//

import SwiftUI

struct EditableSlider<T: BinaryFloatingPoint & LosslessStringConvertible>: View where T.Stride: BinaryFloatingPoint {
    @Binding var value: T
    let range: ClosedRange<T>
    let step: T.Stride?
    let unit: String?
    let formatter: NumberFormatter?
    let onValueChanged: ((T) -> Void)?
    
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isTextFieldFocused: Bool
    
    // Styling options
    let sliderStyle: SliderStyle
    let font: Font
    let showValue: Bool
    let precision: Int?
    let helpText: String?
    
    init(
        value: Binding<T>,
        in range: ClosedRange<T>,
        step: T.Stride? = nil,
        unit: String? = nil,
        formatter: NumberFormatter? = nil,
        sliderStyle: SliderStyle = .default,
        font: Font = .caption,
        showValue: Bool = true,
        precision: Int? = nil,
        helpText: String? = "Drag to adjust, double-click to edit",
        onValueChanged: ((T) -> Void)? = nil
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.formatter = formatter
        self.sliderStyle = sliderStyle
        self.font = font
        self.showValue = showValue
        self.precision = precision
        self.helpText = helpText
        self.onValueChanged = onValueChanged
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Value display/editor
            if showValue {
                valueView
            }
            
            // Slider
            if !isEditing {
                sliderView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
    
    // MARK: - Value View
    private var valueView: some View {
        Group {
            if isEditing {
                editingValueView
            } else {
                displayValueView
            }
        }
    }
    
    private var displayValueView: some View {
        HStack(spacing: 2) {
            Text(formattedValue)
                .font(font)
                .foregroundColor(.primary)
                .monospacedDigit()
            
            if let unit = unit {
                Text(unit)
                    .font(font)
                    .foregroundColor(.secondary)
            }
        }
        .onTapGesture(count: 2) {
            startEditing()
        }
        .help(helpText ?? "Drag to adjust, double-click to edit")
        .contentShape(Rectangle())
    }
    
    private var editingValueView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                TextField("Value", text: $editingText)
                    .textFieldStyle(.roundedBorder)
                    .font(font)
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
                    .frame(width: 80)
                
                if let unit = unit {
                    Text(unit)
                        .font(font)
                        .foregroundColor(.secondary)
                }
            }
            
            // Error message
            if showingError && !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
    }
    
    // MARK: - Slider View
    private var sliderView: some View {
        Group {
            if let step = step {
                Slider(value: $value, in: range, step: step) {
                    EmptyView()
                } onEditingChanged: { editing in
                    if !editing {
                        onValueChanged?(value)
                    }
                }
            } else {
                Slider(value: $value, in: range) {
                    EmptyView()
                } onEditingChanged: { editing in
                    if !editing {
                        onValueChanged?(value)
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    private var formattedValue: String {
        if let formatter = formatter {
            return formatter.string(from: NSNumber(value: Double(value))) ?? String(Double(value))
        } else if let precision = precision {
            return String(format: "%.\(precision)f", Double(value))
        } else {
            // Auto-determine precision based on value magnitude
            let doubleValue = Double(value)
            if doubleValue >= 100 {
                return String(format: "%.0f", doubleValue)
            } else if doubleValue >= 10 {
                return String(format: "%.1f", doubleValue)
            } else {
                return String(format: "%.2f", doubleValue)
            }
        }
    }
    
    // MARK: - Editing Actions
    private func startEditing() {
        editingText = String(Double(value))
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
        guard let doubleValue = Double(trimmedText),
              let newValue = T(exactly: doubleValue) else {
            showError("Invalid number format")
            return
        }
        
        // Validate range
        if !range.contains(newValue) {
            showError("Value must be between \(formatRangeValue(range.lowerBound)) and \(formatRangeValue(range.upperBound))")
            return
        }
        
        // Commit the change
        value = newValue
        onValueChanged?(newValue)
        isEditing = false
        showingError = false
    }
    
    private func cancelEdit() {
        editingText = String(Double(value))
        isEditing = false
        showingError = false
        errorMessage = ""
    }
    
    private func validateText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it's a valid number
        guard let doubleValue = Double(trimmedText),
              let newValue = T(exactly: doubleValue) else {
            if !trimmedText.isEmpty {
                showError("Invalid number format")
            } else {
                showingError = false
            }
            return
        }
        
        // Check range
        if !range.contains(newValue) {
            showError("Value must be between \(formatRangeValue(range.lowerBound)) and \(formatRangeValue(range.upperBound))")
        } else {
            showingError = false
            errorMessage = ""
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    private func formatRangeValue(_ val: T) -> String {
        return String(format: "%.1f", Double(val))
    }
}

// MARK: - Slider Style Enum
enum SliderStyle {
    case `default`
    case minimal
}

// MARK: - Convenience Initializers
extension EditableSlider where T == Double {
    static func volume(
        value: Binding<Double>,
        onValueChanged: ((Double) -> Void)? = nil
    ) -> EditableSlider<Double> {
        return EditableSlider(
            value: value,
            in: 0.0...1.0,
            unit: nil,
            precision: 2,
            helpText: "Drag to adjust volume, double-click to edit",
            onValueChanged: onValueChanged
        )
    }
    
    static func pan(
        value: Binding<Double>,
        onValueChanged: ((Double) -> Void)? = nil
    ) -> EditableSlider<Double> {
        return EditableSlider(
            value: value,
            in: -1.0...1.0,
            precision: 2,
            helpText: "Drag to adjust pan, double-click to edit",
            onValueChanged: onValueChanged
        )
    }
    
    static func gain(
        value: Binding<Double>,
        range: ClosedRange<Double> = -60.0...12.0,
        onValueChanged: ((Double) -> Void)? = nil
    ) -> EditableSlider<Double> {
        return EditableSlider(
            value: value,
            in: range,
            unit: "dB",
            precision: 1,
            helpText: "Drag to adjust gain, double-click to edit",
            onValueChanged: onValueChanged
        )
    }
    
    static func frequency(
        value: Binding<Double>,
        range: ClosedRange<Double> = 20.0...20000.0,
        onValueChanged: ((Double) -> Void)? = nil
    ) -> EditableSlider<Double> {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        
        return EditableSlider(
            value: value,
            in: range,
            unit: "Hz",
            formatter: formatter,
            helpText: "Drag to adjust frequency, double-click to edit",
            onValueChanged: onValueChanged
        )
    }
    
    static func percentage(
        value: Binding<Double>,
        onValueChanged: ((Double) -> Void)? = nil
    ) -> EditableSlider<Double> {
        return EditableSlider(
            value: value,
            in: 0.0...100.0,
            unit: "%",
            precision: 1,
            helpText: "Drag to adjust percentage, double-click to edit",
            onValueChanged: onValueChanged
        )
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 30) {
        VStack {
            Text("Volume")
            EditableSlider.volume(value: .constant(0.75)) { newValue in
                print("Volume changed to: \(newValue)")
            }
        }
        
        VStack {
            Text("Pan")
            EditableSlider.pan(value: .constant(-0.25)) { newValue in
                print("Pan changed to: \(newValue)")
            }
        }
        
        VStack {
            Text("Gain")
            EditableSlider.gain(value: .constant(-6.0)) { newValue in
                print("Gain changed to: \(newValue)")
            }
        }
        
        VStack {
            Text("Frequency")
            EditableSlider.frequency(value: .constant(1000.0)) { newValue in
                print("Frequency changed to: \(newValue)")
            }
        }
    }
    .padding()
}
