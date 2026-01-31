//
//  CreateLicenseView.swift
//  Stori
//
//  Created by TellUrStori on 12/9/25.
//

import SwiftUI

/// Multi-step modal for creating a license instance from a Digital Master
struct CreateLicenseView: View {
    let master: DigitalMasterItem
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var currentStep: CreationStep = .selectType
    @State private var config = LicenseConfiguration()
    @State private var isCreating: Bool = false
    @State private var createdInstance: LicenseInstance?
    @State private var errorMessage: String?
    
    enum CreationStep {
        case selectType
        case configure
        case confirm
        case creating
        case success
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content based on step
            switch currentStep {
            case .selectType:
                licenseTypeSelection
            case .configure:
                licenseConfiguration
            case .confirm:
                confirmationView
            case .creating:
                creatingView
            case .success:
                successView
            }
        }
        .frame(width: 720, height: currentStep == .selectType ? 760 : 700)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            if currentStep != .selectType && currentStep != .creating && currentStep != .success {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        goBack()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 60)
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("Create License Instance")
                    .font(.headline)
                
                Text(master.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
    
    // MARK: - Step 1: License Type Selection
    
    private var licenseTypeSelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose License Type")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Select the type of license you want to create for your Digital Master")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    ForEach(LicenseType.allCases) { type in
                        LicenseTypeCard(
                            type: type,
                            isSelected: config.licenseType == type
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                config.licenseType = type
                            }
                        }
                    }
                }
                
                Spacer(minLength: 20)
                
                // Continue button
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        currentStep = .configure
                    }
                } label: {
                    HStack {
                        Text("Continue with \(config.licenseType.title)")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: config.licenseType.gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }
    
    // MARK: - Step 2: Configuration
    
    private var licenseConfiguration: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Type header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: config.licenseType.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: config.licenseType.systemIcon)
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Configure \(config.licenseType.title)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(config.licenseType.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Configuration fields based on type
                configFields
                
                Divider()
                
                // Fee breakdown
                feeBreakdown
                
                Spacer(minLength: 20)
                
                // Actions
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            currentStep = .confirm
                        }
                    } label: {
                        HStack {
                            Text("Review & Create")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: config.licenseType.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }
    
    @ViewBuilder
    private var configFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Price
            if config.licenseType != .streaming {
                configField(
                    title: "Price per Instance",
                    icon: "dollarsign.circle",
                    color: .green
                ) {
                    HStack {
                        TextField("0.5", value: $config.price, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        
                        Text("TUS")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )
                }
            }
            
            // Streaming price per stream
            if config.licenseType == .streaming {
                configField(
                    title: "Price per Stream",
                    icon: "waveform",
                    color: .blue
                ) {
                    HStack {
                        TextField("0.001", value: $config.pricePerStream, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        
                        Text("TUS")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )
                }
            }
            
            // Max Supply
            if config.licenseType != .streaming {
                configField(
                    title: "Maximum Supply",
                    icon: "number.circle",
                    color: .purple
                ) {
                    HStack {
                        TextField("100", value: $config.maxSupply, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        
                        Text("(0 = unlimited)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )
                }
            }
            
            // Limited Play - plays included
            if config.licenseType == .limitedPlay {
                configField(
                    title: "Plays Included",
                    icon: "play.circle",
                    color: .orange
                ) {
                    HStack {
                        TextField("10", value: $config.playsIncluded, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        
                        Text("plays")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )
                }
            }
            
            // Time Limited - duration
            if config.licenseType == .timeLimited {
                configField(
                    title: "Access Duration",
                    icon: "calendar",
                    color: .green
                ) {
                    HStack {
                        TextField("30", value: $config.durationDays, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        
                        Text("days")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )
                }
            }
            
            // Commercial terms
            if config.licenseType == .commercialLicense {
                configField(
                    title: "Commercial Terms",
                    icon: "doc.text",
                    color: .indigo
                ) {
                    TextEditor(text: $config.commercialTerms)
                        .font(.system(size: 14))
                        .frame(height: 80)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.controlBackgroundColor))
                        )
                }
            }
            
            // Transferable toggle
            if config.licenseType != .streaming {
                HStack {
                    Toggle(isOn: $config.isTransferable) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.left.arrow.right.circle")
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allow Resale")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Buyers can transfer or resell their license")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }
    
    private func configField<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            
            content()
        }
    }
    
    private var feeBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fee Breakdown")
                .font(.headline)
            
            VStack(spacing: 8) {
                // Note: royaltyPercentage is stored in basis points (1000 = 10%)
                let royaltyPercent = Double(master.royaltyPercentage) / 100.0
                
                feeRow(label: "Platform Fee", value: "1%", sublabel: nil, color: .secondary)
                feeRow(label: "Creator Royalty", value: String(format: "%.1f%%", royaltyPercent), sublabel: "From Digital Master", color: .secondary)
                
                Divider()
                
                feeRow(
                    label: "You Receive",
                    value: String(format: "%.1f%%", 100 - 1 - royaltyPercent),
                    sublabel: config.licenseType != .streaming
                        ? String(format: "(%.4f TUS per sale)", config.creatorRevenuePerSale(royaltyPercent: Int(royaltyPercent)))
                        : nil,
                    color: .green
                )
                
                if config.maxSupply > 0 && config.licenseType != .streaming {
                    feeRow(
                        label: "Potential Revenue",
                        value: String(format: "%.2f TUS", config.potentialRevenue(royaltyPercent: Int(royaltyPercent))),
                        sublabel: "If all \(config.maxSupply) sell",
                        color: .green
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.controlBackgroundColor))
            )
        }
    }
    
    private func feeRow(label: String, value: String, sublabel: String?, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                if let sub = sublabel {
                    Text(sub)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
    }
    
    // MARK: - Step 3: Confirmation
    
    private var confirmationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Summary card
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: config.licenseType.gradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: config.licenseType.systemIcon)
                                .font(.title)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(config.licenseType.title)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("for \(master.title)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Divider()
                    
                    // Config summary
                    VStack(spacing: 12) {
                        if config.licenseType == .streaming {
                            summaryRow(icon: "waveform", label: "Price per Stream", value: "\(config.pricePerStream) TUS")
                        } else {
                            summaryRow(icon: "dollarsign.circle", label: "Price", value: "\(config.price) TUS")
                            summaryRow(icon: "number.circle", label: "Max Supply", value: config.maxSupply == 0 ? "Unlimited" : "\(config.maxSupply)")
                        }
                        
                        if config.licenseType == .limitedPlay {
                            summaryRow(icon: "play.circle", label: "Plays Included", value: "\(config.playsIncluded)")
                        }
                        
                        if config.licenseType == .timeLimited {
                            summaryRow(icon: "calendar", label: "Duration", value: "\(config.durationDays) days")
                        }
                        
                        summaryRow(icon: "arrow.left.arrow.right", label: "Transferable", value: config.isTransferable ? "Yes" : "No")
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.controlBackgroundColor))
                )
                
                // Warning/info - now wallet-based
                HStack(spacing: 12) {
                    Image(systemName: "wallet.pass.fill")
                        .foregroundColor(.purple)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your wallet will pay the gas fee")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("This creates an ERC-1155 license instance on Stori L1")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.purple.opacity(0.1))
                )
                
                if let error = errorMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                
                // Actions
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button {
                        createLicense()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Create License Instance")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: config.licenseType.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }
    
    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
        .font(.system(size: 14))
    }
    
    // MARK: - Step 4: Creating
    
    private var creatingView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Animated icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: config.licenseType.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .opacity(0.2)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: config.licenseType.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .opacity(0.4)
                
                Image(systemName: config.licenseType.systemIcon)
                    .font(.system(size: 32))
                    .foregroundColor(config.licenseType.accentColor)
            }
            
            VStack(spacing: 8) {
                Text("Creating License Instance...")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Submitting transaction to blockchain")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            ProgressView()
                .scaleEffect(1.2)
            
            Spacer()
        }
    }
    
    // MARK: - Step 5: Success
    
    private var successView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Success icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text("License Instance Created!")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("\(config.licenseType.title) for \(master.title)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let instance = createdInstance {
                VStack(spacing: 12) {
                    // Instance ID
                    HStack {
                        Text("Instance ID:")
                            .foregroundColor(.secondary)
                        if instance.instanceId.starts(with: "tx:") || instance.instanceId == "pending" {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Pending indexing...")
                                    .foregroundColor(.orange)
                            }
                        } else {
                            Text(instance.instanceId)
                                .monospaced()
                        }
                    }
                    .font(.caption)
                    
                    // Transaction hash
                    if !instance.transactionHash.isEmpty {
                        HStack {
                            Text("Transaction:")
                                .foregroundColor(.secondary)
                            Text(instance.transactionHash.prefix(20) + "...")
                                .monospaced()
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(instance.transactionHash, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.controlBackgroundColor))
                )
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
    
    // MARK: - Actions
    
    private func goBack() {
        switch currentStep {
        case .configure:
            currentStep = .selectType
        case .confirm:
            currentStep = .configure
        default:
            break
        }
    }
    
    private func createLicense() {
        withAnimation(.spring(response: 0.3)) {
            currentStep = .creating
        }
        errorMessage = nil
        
        Task {
            await performLicenseCreation()
        }
    }
    
    private func performLicenseCreation() async {
        do {
            // Convert license type to contract enum
            let contractLicenseType: LicenseInstanceMintingService.ContractLicenseType
            switch config.licenseType {
            case .fullOwnership: contractLicenseType = .fullOwnership
            case .streaming: contractLicenseType = .streaming
            case .limitedPlay: contractLicenseType = .limitedPlay
            case .timeLimited: contractLicenseType = .timeLimited
            case .commercialLicense: contractLicenseType = .commercialLicense
            }
            
            // Parse master ID from token ID string
            let masterId: Int
            if master.tokenId.hasPrefix("0x") {
                masterId = Int(master.tokenId.dropFirst(2), radix: 16) ?? 1
            } else {
                masterId = Int(master.tokenId) ?? 1
            }
            
            
            // Get price
            let price = config.licenseType == .streaming ? config.pricePerStream : config.price
            
            // Use wallet-based service
            let result = try await LicenseInstanceMintingService.shared.createLicenseInstance(
                masterId: masterId,
                licenseType: contractLicenseType,
                price: price,
                maxSupply: config.maxSupply,
                playsPerInstance: config.playsIncluded,
                durationInDays: config.durationDays,
                isTransferable: config.isTransferable
            )
            
            
            await MainActor.run {
                createdInstance = LicenseInstance(
                    id: UUID().uuidString,
                    instanceId: result.instanceId ?? "pending",
                    masterId: master.tokenId,
                    licenseType: config.licenseType,
                    price: price,
                    maxSupply: config.maxSupply,
                    totalMinted: 0,
                    isTransferable: config.isTransferable,
                    metadataURI: nil,
                    createdAt: Date(),
                    transactionHash: result.transactionHash
                )
                
                withAnimation(.spring(response: 0.3)) {
                    currentStep = .success
                }
            }
            
        } catch {
            
            await MainActor.run {
                errorMessage = error.localizedDescription
                withAnimation(.spring(response: 0.3)) {
                    currentStep = .confirm
                }
            }
        }
    }
}

// MARK: - License Type Card

struct LicenseTypeCard: View {
    let type: LicenseType
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: type.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: type.systemIcon)
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(type.icon) \(type.title)")
                        .font(.headline)
                    
                    Text(type.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Best for: \(type.bestFor)")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(type.accentColor)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected
                            ? type.accentColor.opacity(0.1)
                            : Color(.controlBackgroundColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected
                            ? type.accentColor
                            : (isHovered ? type.accentColor.opacity(0.5) : Color.clear),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
