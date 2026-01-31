//
//  SetupWizardView.swift
//  Stori
//
//  First-run setup wizard that guides users through downloading
//  the SoundFont for MIDI playback.
//

import SwiftUI

// MARK: - SetupWizardView

struct SetupWizardView: View {
    @Bindable var setupManager: SetupManager
    @State private var currentStep: SetupStep = .welcome
    @State private var selectedComponents: Set<SetupComponent> = []
    @Environment(\.dismiss) private var dismiss
    
    enum SetupStep {
        case welcome
        case downloading
        case complete
    }
    
    var body: some View {
        ZStack {
            // Background
            backgroundGradient
            
            VStack(spacing: 0) {
                // Progress indicator
                SetupProgressBar(currentStep: currentStep)
                    .padding(.top, 20)
                    .padding(.horizontal, 40)
                
                // Content
                Group {
                    switch currentStep {
                    case .welcome:
                        WelcomeStepView(onContinue: { startDownloads() })
                    case .downloading:
                        DownloadingStepView(
                            setupManager: setupManager,
                            onMinimize: { dismiss() },
                            onComplete: { currentStep = .complete }
                        )
                    case .complete:
                        CompleteStepView(onLaunch: { dismiss() })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .frame(width: 700, height: 550)
        .onAppear {
            setupManager.refreshStatus()
            // Select the soundFont component
            selectedComponents = Set(SetupComponent.allCases)
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.1, blue: 0.2),
                Color(red: 0.15, green: 0.1, blue: 0.25)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private func startDownloads() {
        currentStep = .downloading
        Task {
            await setupManager.downloadComponents(selectedComponents)
        }
    }
}

// MARK: - SetupProgressBar

struct SetupProgressBar: View {
    let currentStep: SetupWizardView.SetupStep
    
    private let steps: [(SetupWizardView.SetupStep, String)] = [
        (.welcome, "Welcome"),
        (.downloading, "Download"),
        (.complete, "Complete")
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 8) {
                    // Circle indicator
                    ZStack {
                        Circle()
                            .fill(stepColor(for: step.0))
                            .frame(width: 28, height: 28)
                        
                        if isCompleted(step.0) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isCurrent(step.0) ? .white : .gray)
                        }
                    }
                    
                    // Label
                    Text(step.1)
                        .font(.system(size: 12, weight: isCurrent(step.0) ? .semibold : .regular))
                        .foregroundColor(isCurrent(step.0) ? .white : .gray)
                }
                
                // Connector line
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(isCompleted(step.0) ? Color.green : Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                }
            }
        }
    }
    
    private func isCurrent(_ step: SetupWizardView.SetupStep) -> Bool {
        step == currentStep
    }
    
    private func isCompleted(_ step: SetupWizardView.SetupStep) -> Bool {
        let order: [SetupWizardView.SetupStep] = [.welcome, .downloading, .complete]
        guard let currentIndex = order.firstIndex(of: currentStep),
              let stepIndex = order.firstIndex(of: step) else { return false }
        return stepIndex < currentIndex
    }
    
    private func stepColor(for step: SetupWizardView.SetupStep) -> Color {
        if isCompleted(step) {
            return .green
        } else if isCurrent(step) {
            return .blue
        } else {
            return Color.gray.opacity(0.3)
        }
    }
}

// MARK: - WelcomeStepView

struct WelcomeStepView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App icon
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 12) {
                Text("Welcome to Stori")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Your AI-powered digital audio workstation")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                SetupFeatureRow(icon: "pianokeys", title: "128 MIDI Instruments", description: "Full General MIDI soundset")
                SetupFeatureRow(icon: "waveform", title: "AI Music Composition", description: "Cloud-powered music generation")
                SetupFeatureRow(icon: "bubble.left.and.bubble.right", title: "AI Assistant", description: "Natural language DAW control")
                SetupFeatureRow(icon: "link", title: "Blockchain Tokenization", description: "Turn your music into NFTs")
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 20)
            
            Text("Let's download the MIDI instruments soundbank (~140 MB)")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button(action: onContinue) {
                HStack {
                    Text("Download & Continue")
                    Image(systemName: "arrow.down.circle")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }
}

struct SetupFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
}

// MARK: - DownloadingStepView

struct DownloadingStepView: View {
    @Bindable var setupManager: SetupManager
    let onMinimize: () -> Void
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Downloading MIDI Instruments")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)
            
            // Overall progress
            VStack(spacing: 8) {
                ProgressView(value: setupManager.overallProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                
                Text("\(Int(setupManager.overallProgress * 100))% Complete")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 60)
            
            // Component progress list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(setupManager.components) { status in
                        DownloadProgressRow(status: status)
                    }
                }
                .padding(.horizontal, 40)
            }
            .frame(maxHeight: 280)
            
            // Info text
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("You can minimize this window and start using the DAW. Downloads will continue in the background.")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 16) {
                Button(action: {
                    setupManager.cancelAllDownloads()
                }) {
                    Text("Cancel")
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: onMinimize) {
                    HStack {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                        Text("Minimize")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .onChange(of: setupManager.state) {
            if case .completed = setupManager.state {
                onComplete()
            }
        }
    }
}

struct DownloadProgressRow: View {
    let status: ComponentStatus
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Group {
                if status.isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if status.isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if status.error != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                } else {
                    Image(systemName: "clock")
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 24)
            
            // Component name
            VStack(alignment: .leading, spacing: 2) {
                Text(status.component.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                
                if status.isDownloading {
                    Text(status.formattedProgress)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                } else if let error = status.error {
                    Text(error.localizedDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Progress bar (if downloading)
            if status.isDownloading {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: status.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 100)
                        .tint(.blue)
                    
                    if !status.formattedETA.isEmpty {
                        Text(status.formattedETA)
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
            } else if status.isInstalled {
                Text("Complete")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }
}

// MARK: - CompleteStepView

struct CompleteStepView: View {
    let onLaunch: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Success animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text("MIDI instruments are ready to use.")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                TipRow(icon: "music.note", text: "Create tracks using the + button in the track list")
                TipRow(icon: "keyboard", text: "Use the virtual keyboard or connect a MIDI controller")
                TipRow(icon: "bubble.left", text: "Use the AI Composer to create music with natural language")
                TipRow(icon: "questionmark.circle", text: "Press Cmd+? for keyboard shortcuts")
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 20)
            
            Spacer()
            
            Button(action: onLaunch) {
                HStack {
                    Text("Start Creating")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 14)
                .background(Color.green)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }
}

struct TipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.green)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.gray)
            
            Spacer()
        }
    }
}
