//
//  ExportSettingsSheet.swift
//  Stori
//
//  Professional export settings dialog with format selection
//  Professional audio export dialog with format and quality options
//

import SwiftUI
import AVFoundation

// MARK: - Export Settings Model

struct ExportSettings {
    var format: AudioFileFormat = .wav
    var bitDepth: BitDepthOption = .bit24
    var channels: ChannelOption = .stereo
    var normalizeAudio: Bool = true
    var includeMarkers: Bool = false
    var filename: String = ""
    
    // Fixed to 48kHz - matches project sample rate
    var sampleRate: Double { 48000 }
    
    /// Computed audio file settings for AVAudioFile
    var audioSettings: [String: Any] {
        var settings: [String: Any] = [
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels.channelCount
        ]
        
        switch format {
        case .wav:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = bitDepth.value
            settings[AVLinearPCMIsFloatKey] = bitDepth == .bit32Float
            settings[AVLinearPCMIsBigEndianKey] = false
            settings[AVLinearPCMIsNonInterleaved] = false
            
        case .aiff:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = bitDepth.value
            settings[AVLinearPCMIsFloatKey] = bitDepth == .bit32Float
            settings[AVLinearPCMIsBigEndianKey] = true
            settings[AVLinearPCMIsNonInterleaved] = false
            
        case .m4a:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = 320_000  // 320 kbps AAC
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.max.rawValue
            
        case .flac:
            settings[AVFormatIDKey] = kAudioFormatFLAC
            settings[AVLinearPCMBitDepthKey] = bitDepth.value
        }
        
        return settings
    }
}

// MARK: - Sample Rate Options

enum SampleRateOption: String, CaseIterable, Identifiable {
    case rate22050 = "22.05 kHz"
    case rate44100 = "44.1 kHz"
    case rate48000 = "48 kHz"
    case rate88200 = "88.2 kHz"
    case rate96000 = "96 kHz"
    
    var id: String { rawValue }
    
    var value: Double {
        switch self {
        case .rate22050: return 22050
        case .rate44100: return 44100
        case .rate48000: return 48000
        case .rate88200: return 88200
        case .rate96000: return 96000
        }
    }
    
    var displayName: String { rawValue }
    
    var description: String {
        switch self {
        case .rate22050: return "Low quality, small file"
        case .rate44100: return "CD quality"
        case .rate48000: return "Professional standard"
        case .rate88200: return "High resolution"
        case .rate96000: return "Studio master"
        }
    }
}

// MARK: - Bit Depth Options

enum BitDepthOption: String, CaseIterable, Identifiable {
    case bit16 = "16-bit"
    case bit24 = "24-bit"
    case bit32Float = "32-bit Float"
    
    var id: String { rawValue }
    
    var value: Int {
        switch self {
        case .bit16: return 16
        case .bit24: return 24
        case .bit32Float: return 32
        }
    }
    
    var displayName: String { rawValue }
    
    var description: String {
        switch self {
        case .bit16: return "Standard audio, compatible everywhere"
        case .bit24: return "Professional quality, recommended"
        case .bit32Float: return "Maximum quality, largest files"
        }
    }
}

// MARK: - Channel Options

enum ChannelOption: String, CaseIterable, Identifiable {
    case mono = "Mono"
    case stereo = "Stereo"
    
    var id: String { rawValue }
    
    var channelCount: Int {
        switch self {
        case .mono: return 1
        case .stereo: return 2
        }
    }
    
    var displayName: String { rawValue }
}

// MARK: - Export Settings Sheet View

struct ExportSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let projectName: String
    let projectDuration: TimeInterval
    let audioEngine: AudioEngine
    let onExport: (ExportSettings) -> Void
    
    @State private var settings = ExportSettings()
    @State private var showingAdvanced = false
    @State private var showingClipWarning = false  // Issue #73: Clip detection warning
    
    // Estimated file size
    private var estimatedFileSize: String {
        let durationSeconds = projectDuration
        let sampleRate = settings.sampleRate  // Fixed to 48kHz
        let channels = Double(settings.channels.channelCount)
        let bytesPerSample: Double
        
        switch settings.format {
        case .wav, .aiff:
            bytesPerSample = Double(settings.bitDepth.value) / 8.0
            let totalBytes = durationSeconds * sampleRate * channels * bytesPerSample
            return formatFileSize(totalBytes)
            
        case .m4a:
            let bitrate: Double = 320_000  // 320 kbps AAC
            let totalBytes = (bitrate / 8.0) * durationSeconds
            return formatFileSize(totalBytes)
            
        case .flac:
            // FLAC typically compresses to 50-60% of WAV
            bytesPerSample = Double(settings.bitDepth.value) / 8.0
            let wavBytes = durationSeconds * sampleRate * channels * bytesPerSample
            return formatFileSize(wavBytes * 0.55)
        }
    }
    
    private func formatFileSize(_ bytes: Double) -> String {
        if bytes < 1_000_000 {
            return String(format: "%.1f KB", bytes / 1_000)
        } else if bytes < 1_000_000_000 {
            return String(format: "%.1f MB", bytes / 1_000_000)
        } else {
            return String(format: "%.2f GB", bytes / 1_000_000_000)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    filenameSection
                    formatSection
                    qualitySection
                    
                    if showingAdvanced {
                        advancedSection
                    }
                    
                    estimateSection
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 520, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier(AccessibilityID.Export.dialog)
        .onAppear {
            settings.filename = projectName
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Image(systemName: "square.and.arrow.up")
                .font(.title)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Project")
                    .font(.headline)
                Text("Configure your export settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    // MARK: - Filename Section
    
    private var filenameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filename")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            HStack {
                TextField("Enter filename", text: $settings.filename)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !settings.filename.isEmpty {
                            checkClippingAndExport()
                        }
                    }
                
                Text(".\(settings.format.rawValue)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Format Section
    
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Format")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(AudioFileFormat.allCases, id: \.self) { format in
                    formatCard(format)
                }
            }
        }
    }
    
    private func formatCard(_ format: AudioFileFormat) -> some View {
        Button(action: { settings.format = format }) {
            VStack(spacing: 6) {
                Image(systemName: format.isLossless ? "waveform" : "waveform.badge.minus")
                    .font(.title2)
                    .foregroundColor(settings.format == format ? .white : .accentColor)
                
                Text(format.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(settings.format == format ? .white : .primary)
                
                Text(format.isLossless ? "Lossless" : "Compressed")
                    .font(.caption2)
                    .foregroundColor(settings.format == format ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.format == format ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(settings.format == format ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Quality Section
    
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                // Sample Rate (fixed to 48kHz)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("48 kHz")
                        .font(.body)
                        .frame(width: 120, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                }
                
                // Bit Depth (only for lossless formats)
                if settings.format.isLossless {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bit Depth")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $settings.bitDepth) {
                            ForEach(BitDepthOption.allCases) { depth in
                                Text(depth.displayName).tag(depth)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
                
                // Channels
                VStack(alignment: .leading, spacing: 4) {
                    Text("Channels")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $settings.channels) {
                        ForEach(ChannelOption.allCases) { channel in
                            Text(channel.displayName).tag(channel)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                
                Spacer()
            }
            
            // Quality description
            Text(qualityDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }
    
    private var qualityDescription: String {
        switch settings.format {
        case .wav, .aiff:
            return "48 kHz • \(settings.bitDepth.description)"
        case .m4a:
            return "320 kbps AAC • High quality compressed"
        case .flac:
            return "48 kHz • Lossless compression • 50-60% smaller than WAV"
        }
    }
    
    // MARK: - Advanced Section
    
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced Options")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            Toggle("Normalize audio to 0 dB", isOn: $settings.normalizeAudio)
                .font(.body)
            
            Toggle("Include markers (if supported)", isOn: $settings.includeMarkers)
                .font(.body)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Estimate Section
    
    private var estimateSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Estimated File Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(estimatedFileSize)
                    .font(.title3.weight(.semibold))
            }
            
            Spacer()
            
            Button(action: { showingAdvanced.toggle() }) {
                HStack(spacing: 4) {
                    Text(showingAdvanced ? "Hide Advanced" : "Show Advanced")
                        .font(.caption)
                    Image(systemName: showingAdvanced ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    // MARK: - Footer View
    
    private var footerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)
            .storiAccessibilityID(AccessibilityID.Export.dialogCancel)
            
            Spacer()
            
            Button("Export") {
                checkClippingAndExport()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(settings.filename.isEmpty)
            .storiAccessibilityID(AccessibilityID.Export.dialogConfirm)
        }
        .accessibilityElement(children: .contain)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        // Clip warning alert (Issue #73)
        .alert("Clipping Detected", isPresented: $showingClipWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Export Anyway", role: .destructive) {
                proceedWithExport()
            }
        } message: {
            Text("Your mix contains **\(audioEngine.clipCount) clipped sample(s)** exceeding 0dBFS.\n\nThis will cause **permanent digital distortion** in the exported file. Consider reducing levels or enabling normalization before exporting.\n\nExport anyway?")
        }
    }
    
    // MARK: - Clip Detection Helper (Issue #73)
    
    /// Check for clipping before export and warn user
    private func checkClippingAndExport() {
        if audioEngine.isClipping {
            // Show warning dialog
            showingClipWarning = true
        } else {
            // No clipping, proceed directly
            proceedWithExport()
        }
    }
    
    /// Proceed with export (called after user confirms or if no clipping)
    private func proceedWithExport() {
        onExport(settings)
        dismiss()
    }
}
