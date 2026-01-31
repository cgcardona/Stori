//
//  WalletSetupView.swift
//  Stori
//
//  Wallet creation and import flows with polished UI
//

import SwiftUI

enum WalletSetupMode: String, CaseIterable, Identifiable {
    case create = "Create New"
    case importMnemonic = "Import Mnemonic"
    case importPrivateKey = "Import Private Key"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .create: return "plus.circle.fill"
        case .importMnemonic: return "doc.text.fill"
        case .importPrivateKey: return "key.fill"
        }
    }
    
    var description: String {
        switch self {
        case .create: return "Generate a new secure wallet"
        case .importMnemonic: return "Restore from recovery phrase"
        case .importPrivateKey: return "For development/testing"
        }
    }
}

struct WalletSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: WalletSetupMode
    
    init(initialMode: WalletSetupMode = .create) {
        _mode = State(initialValue: initialMode)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Mode selector
            modeSelector
                .padding(.vertical, 16)
            
            Divider()
            
            // Content based on mode
            Group {
                switch mode {
                case .create:
                    CreateWalletView(onComplete: { dismiss() })
                case .importMnemonic:
                    ImportMnemonicView(onComplete: { dismiss() })
                case .importPrivateKey:
                    ImportPrivateKeyView(onComplete: { dismiss() })
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 650, height: 750)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wallet Setup")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Secure your TUS tokens and NFTs")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
        }
        .padding(20)
    }
    
    private var modeSelector: some View {
        HStack(spacing: 12) {
            ForEach(WalletSetupMode.allCases, id: \.self) { setupMode in
                ModeButton(
                    mode: setupMode,
                    isSelected: mode == setupMode,
                    action: { mode = setupMode }
                )
            }
        }
        .padding(.horizontal, 20)
    }
}

struct ModeButton: View {
    let mode: WalletSetupMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .accentColor)
                
                Text(mode.rawValue)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(mode.description)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Create Wallet View

struct CreateWalletView: View {
    let onComplete: () -> Void
    
    private let walletService = WalletService.shared
    @State private var step: CreateWalletStep = .intro
    @State private var language: MnemonicLanguage = .english
    @State private var strength: MnemonicStrength = .words24
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var generatedMnemonic: [String] = []
    @State private var confirmationWords: [Int: String] = [:]
    @State private var verificationIndices: [Int] = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    enum CreateWalletStep: Int, CaseIterable {
        case intro = 0
        case configure = 1
        case showMnemonic = 2
        case verifyMnemonic = 3
        case setPassword = 4
        
        var title: String {
            switch self {
            case .intro: return "Welcome"
            case .configure: return "Configure"
            case .showMnemonic: return "Backup"
            case .verifyMnemonic: return "Verify"
            case .setPassword: return "Secure"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
                .padding(.vertical, 20)
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch step {
                    case .intro:
                        VaultIntroStep {
                            withAnimation(.spring(response: 0.3)) {
                                step = .configure
                            }
                        }
                    case .configure:
                        configureView
                    case .showMnemonic:
                        showMnemonicView
                    case .verifyMnemonic:
                        verifyMnemonicView
                    case .setPassword:
                        setPasswordView
                    }
                }
                .padding(24)
            }
        }
    }
    
    private var progressIndicator: some View {
        HStack(spacing: 0) {
            ForEach(CreateWalletStep.allCases, id: \.rawValue) { stepItem in
                HStack(spacing: 8) {
                    Circle()
                        .fill(step.rawValue >= stepItem.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Group {
                                if step.rawValue > stepItem.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                } else {
                                    Text("\(stepItem.rawValue + 1)")
                                        .font(.caption.bold())
                                        .foregroundColor(step.rawValue >= stepItem.rawValue ? .white : .secondary)
                                }
                            }
                        )
                    
                    Text(stepItem.title)
                        .font(.caption)
                        .foregroundColor(step.rawValue >= stepItem.rawValue ? .primary : .secondary)
                        .fixedSize()
                }
                
                if stepItem != CreateWalletStep.allCases.last {
                    Rectangle()
                        .fill(step.rawValue > stepItem.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: 60)
                }
            }
        }
        .padding(.horizontal, 40)
    }
    
    private var configureView: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("Configure Your Wallet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose your security preferences")
                    .foregroundColor(.secondary)
            }
            
            // Options
            VStack(spacing: 20) {
                // Language picker
                OptionCard(title: "Recovery Phrase Language", icon: "globe") {
                    Picker("Language", selection: $language) {
                        ForEach(MnemonicLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                // Strength picker
                OptionCard(title: "Security Level", icon: "shield.checkered") {
                    Picker("Strength", selection: $strength) {
                        ForEach(MnemonicStrength.allCases) { str in
                            HStack {
                                Text(str.displayName)
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(str.securityLevel)
                                    .foregroundColor(.secondary)
                            }
                            .tag(str)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 280)
                }
            }
            .frame(maxWidth: 500)
            
            Spacer()
            
            PrimaryButton(title: "Generate Recovery Phrase", icon: "arrow.right") {
                generateMnemonic()
            }
            .disabled(isCreating)
        }
    }
    
    private var showMnemonicView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Your Recovery Phrase")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Write these words down in order and store them safely")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Mnemonic grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(generatedMnemonic.enumerated()), id: \.offset) { index, word in
                    MnemonicWordCard(index: index + 1, word: word)
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(16)
            
            // Warning
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keep this phrase secret!")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text("Anyone with these words can access your wallet. Never share them online or with anyone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            PrimaryButton(title: "I've Written It Down", icon: "checkmark") {
                prepareVerification()
                step = .verifyMnemonic
            }
        }
    }
    
    private var verifyMnemonicView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                
                Text("Verify Your Backup")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enter the words at the specified positions to confirm you saved them")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Verification fields
            VStack(spacing: 16) {
                ForEach(verificationIndices, id: \.self) { index in
                    HStack(spacing: 16) {
                        Text("Word #\(index + 1)")
                            .font(.headline)
                            .frame(width: 100, alignment: .trailing)
                        
                        TextField("Enter word", text: Binding(
                            get: { confirmationWords[index] ?? "" },
                            set: { confirmationWords[index] = $0.lowercased() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .padding(24)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(16)
            
            if let error = errorMessage {
                WalletErrorBanner(message: error)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                SecondaryButton(title: "Back", icon: "arrow.left") {
                    step = .showMnemonic
                }
                
                PrimaryButton(title: "Verify & Continue", icon: "arrow.right") {
                    verifyMnemonic()
                }
            }
        }
    }
    
    private var setPasswordView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.linearGradient(colors: [.blue, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("Secure Your Wallet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create a password to encrypt your wallet on this device")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                #if DEBUG
                Text("Dev Mode: Password is optional")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
                #endif
            }
            
            // Password fields
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.headline)
                    SecureField("At least 8 characters", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm Password")
                        .font(.headline)
                    SecureField("Re-enter your password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
                
                // Password strength indicator
                if !password.isEmpty {
                    PasswordStrengthIndicator(password: password)
                        .frame(width: 300)
                }
            }
            .padding(24)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(16)
            
            if let error = errorMessage {
                WalletErrorBanner(message: error)
            }
            
            Spacer()
            
            PrimaryButton(
                title: isCreating ? "Creating Wallet..." : "Create Wallet",
                icon: "wallet.bifold.fill"
            ) {
                createWallet()
            }
            #if DEBUG
            .disabled(password != confirmPassword || isCreating)
            #else
            .disabled(password.isEmpty || password != confirmPassword || password.count < 8 || isCreating)
            #endif
        }
    }
    
    // MARK: - Actions
    
    private func generateMnemonic() {
        isCreating = true
        errorMessage = nil
        
        do {
            let generator = MnemonicGenerator(language: language)
            generatedMnemonic = try generator.generate(strength: strength)
            step = .showMnemonic
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isCreating = false
    }
    
    private func prepareVerification() {
        let indices = (0..<generatedMnemonic.count).shuffled().prefix(3).sorted()
        verificationIndices = Array(indices)
        confirmationWords = [:]
    }
    
    private func verifyMnemonic() {
        errorMessage = nil
        
        for index in verificationIndices {
            let expected = generatedMnemonic[index].lowercased()
            let entered = (confirmationWords[index] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            
            if entered != expected {
                errorMessage = "Word #\(index + 1) is incorrect. Please check and try again."
                return
            }
        }
        
        step = .setPassword
    }
    
    private func createWallet() {
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }
        
        // Validate password (allow empty only in DEBUG for convenience)
        #if !DEBUG
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters"
            return
        }
        #endif
        
        let walletPassword = password
        
        isCreating = true
        errorMessage = nil
        
        Task {
            do {
                try await walletService.importMnemonic(
                    generatedMnemonic,
                    language: language,
                    password: walletPassword
                )
                await MainActor.run {
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

// MARK: - Import Mnemonic View

struct ImportMnemonicView: View {
    let onComplete: () -> Void
    
    private let walletService = WalletService.shared
    @State private var mnemonicText = ""
    @State private var language: MnemonicLanguage = .english
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    private var wordCount: Int {
        mnemonicText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text("Import Recovery Phrase")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Enter your 12-24 word recovery phrase")
                        .foregroundColor(.secondary)
                }
                
                // Language picker
                OptionCard(title: "Phrase Language", icon: "globe") {
                    Picker("Language", selection: $language) {
                        ForEach(MnemonicLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                .frame(maxWidth: 500)
                
                // Mnemonic input
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recovery Phrase")
                            .font(.headline)
                        Spacer()
                        Text("\(wordCount) words")
                            .font(.caption)
                            .foregroundColor(isValidWordCount ? .green : .secondary)
                    }
                    
                    TextEditor(text: $mnemonicText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    
                    Text("Separate words with spaces or new lines")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: 500)
                
                // Password fields
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.headline)
                        SecureField("At least 8 characters", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.headline)
                        SecureField("Re-enter password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: 300)
                
                if let error = errorMessage {
                    WalletErrorBanner(message: error)
                }
                
                Spacer(minLength: 20)
                
                PrimaryButton(
                    title: isImporting ? "Importing..." : "Import Wallet",
                    icon: "arrow.down.circle.fill"
                ) {
                    importWallet()
                }
                #if DEBUG
                .disabled(!isValidWordCount || password != confirmPassword || isImporting)
                #else
                .disabled(!isValidWordCount || password.isEmpty || password != confirmPassword || password.count < 8 || isImporting)
                #endif
            }
            .padding(24)
        }
    }
    
    private var isValidWordCount: Bool {
        [12, 15, 18, 21, 24].contains(wordCount)
    }
    
    private func importWallet() {
        let words = mnemonicText
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        guard isValidWordCount else {
            errorMessage = "Invalid word count. Expected 12, 15, 18, 21, or 24 words."
            return
        }
        
        // Allow empty password in DEBUG for convenience
        let walletPassword = password
        
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                try await walletService.importMnemonic(
                    words,
                    language: language,
                    password: walletPassword
                )
                await MainActor.run { onComplete() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

// MARK: - Import Private Key View

struct ImportPrivateKeyView: View {
    let onComplete: () -> Void
    
    private let walletService = WalletService.shared
    @State private var privateKey = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showKey = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Import Private Key")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("For development and testing only")
                            .foregroundColor(.orange)
                    }
                    .font(.subheadline)
                }
                
                // Private key input
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Private Key (hex)")
                            .font(.headline)
                        Spacer()
                        Toggle("Show", isOn: $showKey)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .scaleEffect(0.8)
                    }
                    
                    Group {
                        if showKey {
                            TextField("0x... or 64 hex characters", text: $privateKey)
                        } else {
                            SecureField("0x... or 64 hex characters", text: $privateKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    
                    // SECURITY: Quick-fill dev key button removed
                    // For testing, paste your test private key manually
                }
                .padding(16)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                .frame(maxWidth: 500)
                
                // Password fields
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.headline)
                        SecureField("At least 8 characters", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.headline)
                        SecureField("Re-enter password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: 300)
                
                if let error = errorMessage {
                    WalletErrorBanner(message: error)
                }
                
                Spacer(minLength: 20)
                
                PrimaryButton(
                    title: isImporting ? "Importing..." : "Import Wallet",
                    icon: "arrow.down.circle.fill"
                ) {
                    importWallet()
                }
                #if DEBUG
                .disabled(privateKey.isEmpty || password != confirmPassword || isImporting)
                #else
                .disabled(privateKey.isEmpty || password.isEmpty || password != confirmPassword || password.count < 8 || isImporting)
                #endif
            }
            .padding(24)
        }
    }
    
    private func importWallet() {
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }
        
        // Allow empty password in DEBUG for convenience
        let walletPassword = password
        
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                try await walletService.importPrivateKey(privateKey, password: walletPassword)
                await MainActor.run { onComplete() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

// MARK: - Reusable Components

struct OptionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            Text(title)
                .font(.headline)
            
            Spacer()
            
            content()
        }
        .padding(16)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

struct MnemonicWordCard: View {
    let index: Int
    let word: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .trailing)
            
            Text(word)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

struct PrimaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .fontWeight(.semibold)
                Image(systemName: icon)
            }
            .frame(minWidth: 200)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.1))
            .foregroundColor(.primary)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

struct WalletErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }
}

struct PasswordStrengthIndicator: View {
    let password: String
    
    private var strength: Int {
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.contains(where: { $0.isNumber }) { score += 1 }
        if password.contains(where: { $0.isUppercase }) { score += 1 }
        if password.contains(where: { "!@#$%^&*(),.?\":{}|<>".contains($0) }) { score += 1 }
        return score
    }
    
    private var strengthLabel: String {
        switch strength {
        case 0...1: return "Weak"
        case 2: return "Fair"
        case 3: return "Good"
        case 4...5: return "Strong"
        default: return "Unknown"
        }
    }
    
    private var strengthColor: Color {
        switch strength {
        case 0...1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4...5: return .green
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(strengthColor)
                        .frame(width: geometry.size.width * CGFloat(strength) / 5, height: 6)
                        .cornerRadius(3)
                        .animation(.easeOut(duration: 0.2), value: strength)
                }
            }
            .frame(height: 6)
            
            Text("Password strength: \(strengthLabel)")
                .font(.caption)
                .foregroundColor(strengthColor)
        }
    }
}
