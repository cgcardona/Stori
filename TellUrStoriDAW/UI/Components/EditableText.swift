import SwiftUI

struct EditableText: View {
    let text: String
    let placeholder: String
    let onTextChanged: (String) -> Void
    let validator: ((String) -> ValidationResult)?
    
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
    
    init(
        text: String,
        placeholder: String = "Enter text",
        font: Font = .body,
        foregroundColor: Color = .primary,
        editingStyle: EditingStyle = .roundedBorder,
        helpText: String? = "Double-click to edit",
        validator: ((String) -> ValidationResult)? = nil,
        onTextChanged: @escaping (String) -> Void
    ) {
        self.text = text
        self.placeholder = placeholder
        self.font = font
        self.foregroundColor = foregroundColor
        self.editingStyle = editingStyle
        self.helpText = helpText
        self.validator = validator
        self.onTextChanged = onTextChanged
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
        Text(text.isEmpty ? placeholder : text)
            .font(font)
            .foregroundColor(text.isEmpty ? .secondary : foregroundColor)
            .onTapGesture(count: 2) {
                startEditing()
            }
            .help(helpText ?? "Double-click to edit")
            .contentShape(Rectangle()) // Make entire area tappable
    }
    
    // MARK: - Editing View
    private var editingView: some View {
        VStack(alignment: .leading, spacing: 4) {
            editingStyle.apply(to: 
                TextField(placeholder, text: $editingText)
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
            
            // Error message
            if showingError && !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
    }
    
    // MARK: - Editing Actions
    private func startEditing() {
        editingText = text
        isEditing = true
        showingError = false
        errorMessage = ""
        
        // Focus the text field after a brief delay to ensure it's rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }
    
    private func commitEdit() {
        let trimmedText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate before committing
        if let validator = validator {
            let result = validator(trimmedText)
            if !result.isValid {
                showError(result.errorMessage)
                return
            }
        }
        
        // Commit the change
        onTextChanged(trimmedText)
        isEditing = false
        showingError = false
    }
    
    private func cancelEdit() {
        editingText = text
        isEditing = false
        showingError = false
        errorMessage = ""
    }
    
    private func validateText(_ text: String) {
        guard let validator = validator else {
            showingError = false
            return
        }
        
        let result = validator(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if result.isValid {
            showingError = false
            errorMessage = ""
        } else {
            showError(result.errorMessage)
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Supporting Types

struct ValidationResult {
    let isValid: Bool
    let errorMessage: String
    
    static let valid = ValidationResult(isValid: true, errorMessage: "")
    
    static func invalid(_ message: String) -> ValidationResult {
        return ValidationResult(isValid: false, errorMessage: message)
    }
}

enum EditingStyle {
    case plain
    case roundedBorder
    
    @ViewBuilder
    func apply<Content: View>(to content: Content) -> some View {
        switch self {
        case .plain:
            content.textFieldStyle(.plain)
        case .roundedBorder:
            content.textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Convenience Validators

extension ValidationResult {
    static func notEmpty(_ text: String) -> ValidationResult {
        return text.isEmpty ? .invalid("Text cannot be empty") : .valid
    }
    
    static func maxLength(_ text: String, _ maxLength: Int) -> ValidationResult {
        return text.count > maxLength ? .invalid("Text cannot exceed \(maxLength) characters") : .valid
    }
    
    static func noSpecialCharacters(_ text: String) -> ValidationResult {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return text.rangeOfCharacter(from: invalidChars) != nil ? 
            .invalid("Text cannot contain special characters") : .valid
    }
    
    static func combine(_ validators: [(String) -> ValidationResult]) -> (String) -> ValidationResult {
        return { text in
            for validator in validators {
                let result = validator(text)
                if !result.isValid {
                    return result
                }
            }
            return .valid
        }
    }
}
