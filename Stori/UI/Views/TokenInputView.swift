//
//  TokenInputView.swift
//  Stori
//
//  JWT token input and validation view
//

import SwiftUI

struct TokenInputView: View {
    @State private var token: String = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var expirationInfo: String?
    
    @Environment(\.dismiss) var dismiss
    
    let allowDismiss: Bool
    
    init(allowDismiss: Bool = true) {
        self.allowDismiss = allowDismiss
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                
                Text("Composer Access")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Paste your access code to unlock AI-powered music creation.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 20)
            
            // Token input
            VStack(alignment: .leading, spacing: 8) {
                TextField("Access Code", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isValidating || showSuccess)
                    .onSubmit {
                        validateToken()
                    }
                
                Text("Codes are provided by the TellUrStori team and expire after a set period.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Error message
            if let errorMessage = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Success message
            if showSuccess {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Access code activated successfully!")
                            .foregroundStyle(.green)
                            .fontWeight(.medium)
                    }
                    
                    if let expirationInfo = expirationInfo {
                        Text(expirationInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .transition(.opacity)
            }
            
            Spacer()
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }
                
                Button(showSuccess ? "Continue" : "Activate") {
                    if showSuccess {
                        dismiss()
                    } else {
                        validateToken()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.isEmpty || isValidating)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(width: 550, height: 450)
    }
    
    // MARK: - Actions
    
    private func validateToken() {
        guard !token.isEmpty else { return }
        
        isValidating = true
        errorMessage = nil
        showSuccess = false
        expirationInfo = nil
        
        Task {
            do {
                let validation = try await AuthService.shared.authenticateWithToken(token)
                
                await MainActor.run {
                    showSuccess = true
                    isValidating = false
                    
                    // Show expiration info
                    if let expirationDate = validation.expirationDate {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        formatter.timeStyle = .short
                        expirationInfo = "Expires: \(formatter.string(from: expirationDate))"
                    }
                    
                    // Post notification with validation data
                    NotificationCenter.default.post(
                        name: .tokenValidated,
                        object: nil,
                        userInfo: ["validation": validation]
                    )
                    
                    // Auto-dismiss immediately after success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                }
            } catch let error as AuthError {
                await MainActor.run {
                    errorMessage = error.errorDescription
                    isValidating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to validate access code: \(error.localizedDescription)"
                    isValidating = false
                }
            }
        }
    }
}

#Preview {
    TokenInputView(allowDismiss: true)
}
