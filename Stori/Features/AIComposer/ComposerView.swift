//
//  ComposerView.swift
//  Stori
//
//  Cursor-style AI Composer interface with conversation history
//

import SwiftUI
import Combine

struct ComposerView: View {
    @Environment(ProjectManager.self) private var projectManager
    @Environment(AudioEngine.self) private var audioEngine
    
    @State private var composerClient = LLMComposerClient()
    @State private var dispatcher: AICommandDispatcher?
    @State private var conversationService = ConversationService.shared
    
    // Authentication
    @State private var hasValidToken = false
    @State private var showingTokenInput = false
    
    // Conversations
    @State private var conversations: [Conversation] = []
    @State private var selectedConversationId: String?
    @State private var showingConversationSearch = false
    @State private var isLoadingConversations = false
    
    // Current input
    @State private var promptText = ""
    @State private var isComposing = false
    @State private var composerState: ComposerState = .idle
    @State private var streamingContent = ""
    @State private var thinkingContent = ""  // Chain of thought from thinking_delta
    @State private var statusMessage = ""  // Current status from backend
    @State private var activeTools: [String] = []  // Tools currently executing
    @State private var completedTools: [String] = []  // Tools that finished
    @State private var failedTools: [String] = []  // Tools that errored
    @State private var usingIntentEngine = false
    @State private var detectedGoal: MusicalGoal?
    @State private var requestStartTime: Date?
    @State private var showQuickActions = false
    @State private var metrics = IntentEngineMetrics()
    
    enum ComposerState {
        case idle
        case thinking      // Questions, explanations, RAG-powered answers
        case editing       // DAW operations, tool calls, project modifications
        case composing     // AI music generation (MusicGen, MIDI creation)
    }
    
    // Budget details popup
    @State private var showingBudgetDetails = false
    
    // Error handling
    @State private var conversationLoadError: String?
    @State private var selectedModelId: String = ""
    @State private var showModelPicker = false
    @State private var hoveredModel: AIModelInfo?
    @State private var isInitializing = false
    
    // Computed
    private var currentProjectId: String? {
        projectManager.currentProject?.id.uuidString
    }
    
    /// Conversations filtered by current project
    /// Note: Composer is hidden when no project is open, so this always has a projectId
    private var filteredConversations: [Conversation] {
        guard let projectId = currentProjectId else {
            return [] // Should never happen - composer is hidden without project
        }
        // Show only conversations for this project
        return conversations.filter { $0.projectId == projectId }
    }
    
    private var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationId }
    }
    
    private var budget: BudgetState {
        UserManager.shared.budget
    }
    
    private var selectedModel: AIModelInfo? {
        UserManager.shared.selectedModel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if hasValidToken {
                // Only show composer if project is open
                if currentProjectId == nil {
                    // No project open - show empty state
                    noProjectView
                } else if isInitializing {
                    // Loading state during initialization
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading composer...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Cursor-style interface
                    VStack(spacing: 0) {
                        // Error banner (if needed)
                        if let error = conversationLoadError, !conversations.isEmpty {
                            errorBanner(error)
                        }
                        
                        conversationTabs
                    }
                    Divider()
                    conversationView
                    Divider()
                    bottomBar
                }
            } else {
                lockedView
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingTokenInput) {
            TokenInputView(allowDismiss: hasValidToken)
        }
        .onChange(of: hasValidToken) { oldValue, newValue in
            if newValue && !oldValue {
                // Token just became valid - initialize composer
                isInitializing = true
                Task {
                    await UserManager.shared.ensureRegistered()
                    
                    do {
                        try await UserManager.shared.fetchAvailableModels()
                        // Sync selected model ID
                        await MainActor.run {
                            selectedModelId = UserManager.shared.selectedModelId
                        }
                    } catch {
                    }
                    
                    // Load conversation history
                    await loadConversations()
                    
                    // Done initializing
                    await MainActor.run {
                        isInitializing = false
                    }
                }
            } else if !newValue && oldValue {
                // Token became invalid - clear all data
                conversations = []
                selectedConversationId = nil
                try? TokenManager.shared.deleteToken()
            }
        }
        .onChange(of: currentProjectId) { oldProjectId, newProjectId in
            // Project changed - reload conversations for new project
            if hasValidToken {
                selectedConversationId = nil  // Clear selection
                Task {
                    await loadConversations()
                }
            }
        }
        .onAppear {
            dispatcher = AICommandDispatcher(projectManager: projectManager, audioEngine: audioEngine)
            
            // Check backend connection in background
            Task {
                await composerClient.checkConnection()
            }
            
            // Auto-unlock if valid token exists
            if TokenManager.shared.hasToken {
                Task {
                    do {
                        let token = try TokenManager.shared.getToken()
                        let validation = try await AuthService.shared.authenticateWithToken(token)
                        await MainActor.run {
                            hasValidToken = true
                        }
                    } catch {
                        // Token invalid - delete it and stay locked
                        try? TokenManager.shared.deleteToken()
                        hasValidToken = false
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tokenValidated)) { _ in
            hasValidToken = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .tokenExpired)) { _ in
            hasValidToken = false
            try? TokenManager.shared.deleteToken()
            // Don't auto-show token input - let user decide when to unlock composer
        }
    }
    
    // MARK: - Conversation Tabs
    
    private var conversationTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(filteredConversations) { conversation in
                    conversationTab(conversation)
                }
                
                // New conversation button
                Button(action: createNewConversation) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("New conversation")
                .accessibilityLabel("New conversation")
                .accessibilityHint("Creates a new chat conversation")
                .keyboardShortcut("n", modifiers: [.command])
                
                // Search button
                Button(action: { showingConversationSearch.toggle() }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Search conversations")
                .accessibilityLabel("Search conversations")
                .accessibilityHint("Opens search to find previous conversations")
                .keyboardShortcut("f", modifiers: [.command])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 44)
        .background(Color(.controlBackgroundColor))
    }
    
    private func conversationTab(_ conversation: Conversation) -> some View {
        let isSelected = conversation.id == selectedConversationId
        
        return Button(action: {
            selectedConversationId = conversation.id
        }) {
            HStack(spacing: 6) {
                Text(conversation.title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Button(action: {
                    closeConversation(conversation.id)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isSelected ? 1 : 0)
                .accessibilityLabel("Close \(conversation.title)")
                .accessibilityHint("Closes this conversation tab")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color(.textBackgroundColor) : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(conversation.title) conversation")
        .accessibilityHint(isSelected ? "Currently selected conversation" : "Tap to switch to this conversation")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
    
    // MARK: - Conversation View
    
    private var conversationView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let conversation = selectedConversation {
                    ForEach(conversation.messages) { message in
                        messageRow(message)
                        Divider()
                            .padding(.leading, 60)
                    }
                    
                    // Show streaming message if composing
                    if isComposing && !streamingContent.isEmpty {
                        streamingMessageRow()
                        Divider()
                            .padding(.leading, 60)
                    } else if isComposing {
                        // Show typing indicator if no content yet
                        typingIndicatorRow()
                        Divider()
                            .padding(.leading, 60)
                    }
                } else {
                    emptyConversationView
                }
            }
        }
    }
    
    private func streamingMessageRow() -> some View {
        HStack(alignment: .top, spacing: 12) {
            // AI Avatar
            avatar(for: .assistant)
            
            // Streaming content
            VStack(alignment: .leading, spacing: 12) {
                // Status message
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                // Show thinking content if available (chain of thought)
                if !thinkingContent.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("💭 Chain of Thought")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Text(thinkingContent)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                    }
                }
                
                // Tool execution progress
                if !activeTools.isEmpty || !completedTools.isEmpty || !failedTools.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(completedTools, id: \.self) { tool in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 12))
                                Text(formatToolName(tool))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        ForEach(failedTools, id: \.self) { tool in
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 12))
                                Text(formatToolName(tool))
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        ForEach(activeTools, id: \.self) { tool in
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 12, height: 12)
                                Text(formatToolName(tool))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                }
                
                // Main response content
                if !streamingContent.isEmpty {
                    Text(streamingContent)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
                
                // Blinking cursor
                HStack(spacing: 4) {
                    Text("▋")
                        .font(.system(size: 13))
                        .foregroundColor(.purple)
                        .opacity(0.7)
                    
                    Text(composerStateText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.trailing, 12)
            
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    private func formatToolName(_ tool: String) -> String {
        // Convert snake_case to readable format
        // "stori_add_midi_track" → "Add MIDI Track"
        tool.replacingOccurrences(of: "stori_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
    
    /// Tool name from action (for display and icon lookup)
    private func toolNameFromAction(_ action: MessageAction) -> String? {
        if let name = action.extraMetadata?.toolName, !name.isEmpty { return name }
        // Parse "Execute stori_xxx" or "✅ stori_xxx" from description
        let d = action.description
        if let range = d.range(of: "stori_[a-z0-9_]+", options: .regularExpression) {
            return String(d[range])
        }
        return nil
    }
    
    /// Human-readable label for action row (formatted tool name, no "Execute" prefix)
    private func actionDisplayLabel(_ action: MessageAction) -> String {
        if action.type == .toolExecution, let name = toolNameFromAction(action) {
            return formatToolName(name)
        }
        return action.description
    }
    
    /// SF Symbol for each tool (different icon per tool call)
    private func iconForTool(_ toolName: String) -> String {
        let normalized = toolName.lowercased().replacingOccurrences(of: "stori_", with: "")
        switch normalized {
        case "set_tempo": return "metronome"
        case "set_key_signature": return "signature"
        case "add_midi_track": return "pianokeys"
        case "add_midi_region": return "rectangle.stack"
        case "generate_drums": return "drum.drums.fill"
        case "add_notes": return "music.note.list"
        case "generate_bass": return "waveform"
        case "add_insert_effect": return "slider.horizontal.3"
        case "set_track_volume": return "speaker.wave.2.fill"
        case "ensure_bus": return "bus"
        case "add_send": return "paperplane.fill"
        case "add_automation": return "chart.line.uptrend.xyaxis"
        default: return "wrench.and.screwdriver"
        }
    }
    
    private func typingIndicatorRow() -> some View {
        HStack(alignment: .top, spacing: 12) {
            // AI Avatar
            avatar(for: .assistant)
            
            VStack(alignment: .leading, spacing: 8) {
                // Intent Engine Badge
                if usingIntentEngine {
                    IntentEngineBadge(goal: detectedGoal)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Tool execution status
                if !completedTools.isEmpty || !activeTools.isEmpty || !failedTools.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(completedTools, id: \.self) { tool in
                            HStack(spacing: 6) {
                                Text("✅")
                                    .font(.system(size: 11))
                                Text(formatToolName(tool))
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        ForEach(activeTools, id: \.self) { tool in
                            HStack(spacing: 6) {
                                Text("⚙️")
                                    .font(.system(size: 11))
                                Text(formatToolName(tool))
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        ForEach(failedTools, id: \.self) { tool in
                            HStack(spacing: 6) {
                                Text("❌")
                                    .font(.system(size: 11))
                                Text(formatToolName(tool))
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Animated typing indicator
                HStack(spacing: 4) {
                    AnimatedDotsView()
                    
                    Text(composerStateText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 12)
            
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    private var composerStateText: String {
        switch composerState {
        case .idle:
            return ""
        case .thinking:
            // Show active tools if any are running
            if !activeTools.isEmpty {
                let toolNames = activeTools.map { formatToolName($0) }.joined(separator: ", ")
                return "🔧 \(toolNames)"
            }
            // Show status message if available
            if !statusMessage.isEmpty && statusMessage != "Thinking..." {
                return statusMessage
            }
            return "Thinking"
        case .editing:
            // Show active tools if any are running
            if !activeTools.isEmpty {
                let toolNames = activeTools.map { formatToolName($0) }.joined(separator: ", ")
                return "🔧 \(toolNames)"
            }
            // Show status message if available
            if !statusMessage.isEmpty && statusMessage != "Editing..." {
                return statusMessage
            }
            return "Editing"
        case .composing:
            // Show active tools if any are running
            if !activeTools.isEmpty {
                let toolNames = activeTools.map { formatToolName($0) }.joined(separator: ", ")
                return "🔧 \(toolNames)"
            }
            // Show status message if available
            if !statusMessage.isEmpty && statusMessage != "Composing..." {
                return statusMessage
            }
            return "Composing"
        }
    }
    
    private func messageRow(_ message: ConversationMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatar(for: message.role)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                
                // Actions
                if !message.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.actions) { action in
                            actionRow(action)
                        }
                    }
                }
                
                // Timestamp
                Text(timeString(for: message.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func avatar(for role: ConversationMessage.MessageRole) -> some View {
        Group {
            if role == .user {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    )
            } else {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                    )
            }
        }
    }
    
    private func actionRow(_ action: MessageAction) -> some View {
        let displayLabel = actionDisplayLabel(action)
        let toolIcon: String = {
            if action.type == .toolExecution, let name = toolNameFromAction(action) {
                return iconForTool(name)
            }
            return action.icon
        }()
        
        return HStack(spacing: 6) {
            Image(systemName: action.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(action.success ? .green : .red)
            
            Image(systemName: toolIcon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Text(displayLabel)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(action.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(6)
        .accessibilityLabel("\(action.success ? "Success" : "Failed"): \(displayLabel)")
        .accessibilityAddTraits(.isStaticText)
    }
    
    private var emptyConversationView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            if let error = conversationLoadError {
                // Error state
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(.orange.opacity(0.7))
                
                Text("Unable to load conversations")
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                
                Button(action: {
                    Task { await loadConversations() }
                }) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 8)
            } else {
                // Empty state
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 48))
                    .foregroundColor(.purple.opacity(0.5))
                
                Text("Start a new conversation")
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text("Describe what you want to create or modify in your project")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: {
                Task { await loadConversations() }
            }) {
                Text("Retry")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderless)
            
            Button(action: {
                conversationLoadError = nil
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Quick Actions (Intent Engine goals)
            if showQuickActions {
                quickActionsView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Input area
            HStack(alignment: .bottom, spacing: 10) {
                // Quick Actions Toggle
                Button(action: { withAnimation { showQuickActions.toggle() } }) {
                    Image(systemName: showQuickActions ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
                        .font(.system(size: 18))
                        .foregroundColor(.purple)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quick actions")
                .accessibilityHint("Shows musical goal shortcuts")
                
                TextField("Describe what you want to create or change...", text: $promptText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(10)
                    .onSubmit {
                        sendMessage()
                    }
                    .accessibilityLabel("Message input")
                    .accessibilityHint("Type your request to the AI composer. Press Return to send")
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(canSend ? .purple : .gray.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send message")
                .accessibilityHint(canSend ? "Sends your message to the AI" : "Enter text to enable sending")
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            // Model selector and budget
            HStack(spacing: 12) {
                // Custom model selector with popover
                Button {
                    showModelPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        if let model = selectedModel, model.hasThinking {
                            Image(systemName: "brain")
                                .font(.system(size: 10))
                        }
                        Text(selectedModel?.name ?? "Select Model")
                            .font(.system(size: 11))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                    modelPickerPopover
                }
                .overlay(alignment: .topLeading) {
                    // Model details panel - appears to LEFT of popover
                    if showModelPicker, let model = hoveredModel {
                        modelDetailsPanel(model)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
                            .frame(width: 300)
                            .offset(x: -310, y: 30) // Left of button, below it
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.15), value: hoveredModel != nil)
                            .zIndex(1000)
                    }
                }
                .frame(height: 20)
                .accessibilityLabel("AI Model: \(selectedModel?.name ?? "None selected")")
                .accessibilityHint("Choose which AI model to use for composition")
                
                Spacer()
                
                // Budget display (clickable)
                Button(action: { showingBudgetDetails.toggle() }) {
                    HStack(spacing: 6) {
                        // Progress ring
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                                .frame(width: 16, height: 16)
                            
                            Circle()
                                .trim(from: 0, to: budget.percentRemaining)
                                .stroke(budgetColor, lineWidth: 2)
                                .frame(width: 16, height: 16)
                                .rotationEffect(.degrees(-90))
                        }
                        
                        Text("\(Int(budget.percentRemaining * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingBudgetDetails, arrowEdge: .top) {
                    budgetDetailsPopover
                }
                .help("Budget: \(budget.displayString)")
                .accessibilityLabel("Budget: \(Int(budget.percentRemaining * 100)) percent remaining")
                .accessibilityHint("Shows detailed budget usage and remaining credits")
                .accessibilityValue(budget.displayString)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.controlBackgroundColor))
    }
    
    private var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isComposing &&
        UserManager.shared.hasBudget
    }
    
    private var budgetColor: Color {
        switch budget.warningLevel {
        case .normal: return .green
        case .low: return .yellow
        case .critical: return .orange
        case .exhausted: return .red
        }
    }
    
    // MARK: - Model Picker Popover
    
    private var modelPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(UserManager.shared.availableModels) { model in
                modelRow(model)
            }
        }
        .padding(6)
        .onHover { hovering in
            if !hovering {
                hoveredModel = nil
            }
        }
    }
    
    private func modelRow(_ model: AIModelInfo) -> some View {
        Button {
            selectedModelId = model.id
            UserManager.shared.selectedModelId = model.id
            showModelPicker = false
        } label: {
            HStack(spacing: 6) {
                // Left: Model name + brain icon (grouped together)
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    
                    if model.hasThinking {
                        Image(systemName: "brain")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Right: Checkmark (far right)
                if model.id == selectedModelId {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.purple)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(width: 220)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(hoveredModel?.id == model.id ? 0.08 : 0))
        )
        .onHover { hovering in
            if hovering {
                hoveredModel = model
            }
        }
        .accessibilityLabel("\(model.name)")
        .accessibilityHint(model.hasThinking ? "Thinking model" : "")
    }
    
    // MARK: - Model Details Panel
    
    private func modelDetailsPanel(_ model: AIModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Model name
            Text(model.name)
                .font(.system(size: 14, weight: .semibold))
            
            // Description
            Text(model.description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Specs
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.contextWindow)
                        .font(.system(size: 11, weight: .medium))
                    Text("context")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayCost)
                        .font(.system(size: 11, weight: .medium))
                    Text("per 1M")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                if let effort = model.reasoningEffort {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version:")
                            .font(.system(size: 11, weight: .medium))
                        Text(effort)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
    
    // MARK: - Budget Details Popover
    
    private var budgetDetailsPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Usage & Budget")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            
            // Main stats
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(budget.formattedRemaining)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                    Text("/ \(budget.formattedLimit)")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(budgetColor)
                            .frame(width: max(0, geo.size.width * budget.percentRemaining), height: 8)
                    }
                }
                .frame(height: 8)
            }
            
            Divider()
            
            // Details
            VStack(alignment: .leading, spacing: 10) {
                detailRow(label: "Requests used", value: "\(budget.usageCount)")
                detailRow(label: "Avg cost/request", value: budget.usageCount > 0 ? String(format: "$%.3f", (budget.limit - budget.remaining) / Double(budget.usageCount)) : "$0.000")
                detailRow(label: "Est. remaining", value: "\(estimatedRequestsRemaining) requests")
            }
            
            Divider()
            
            // Reset info
            VStack(alignment: .leading, spacing: 6) {
                Text("Budget resets monthly")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                if let tokenExpiry = tokenExpirationTime() {
                    Text("Token expires: \(tokenExpiry)")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
    }
    
    private var estimatedRequestsRemaining: Int {
        guard budget.usageCount > 0, budget.remaining > 0 else { return 0 }
        let avgCost = (budget.limit - budget.remaining) / Double(budget.usageCount)
        guard avgCost > 0 else { return 0 }
        return Int(budget.remaining / avgCost)
    }
    
    // MARK: - Locked View
    
    private var lockedView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Access Code Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your access code has expired. Enter a new code to continue using the AI Composer.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            
            Button(action: { showingTokenInput = true }) {
                Label("Enter New Access Code", systemImage: "key.fill")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Enter new access code")
            .accessibilityHint("Opens dialog to enter a fresh authentication token")
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var noProjectView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Project Open")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Open or create a project to use the AI Composer. Conversations are linked to projects, keeping your work organized.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard canSend else { return }
        
        let raw = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = PromptSanitizer.truncatePrompt(PromptSanitizer.sanitize(raw))
        promptText = ""
        
        Task {
            // Auto-create conversation if none selected (like Cursor)
            if selectedConversationId == nil {
                guard let projectId = currentProjectId else {
                    return
                }
                
                // Use first ~50 chars of prompt as title (KISS approach)
                let titleLimit = 50
                let title = message.count > titleLimit 
                    ? String(message.prefix(titleLimit)) + "..."
                    : message
                
                do {
                    let detail = try await conversationService.createConversation(
                        title: title,
                        projectId: projectId
                    )
                    let newConversation = Conversation(from: detail)
                    
                    await MainActor.run {
                        conversations.insert(newConversation, at: 0)
                        selectedConversationId = newConversation.id
                    }
                } catch {
                    await MainActor.run {
                        handleError(error)
                    }
                    return
                }
            }
            
            guard let conversationId = selectedConversationId else { return }
            
            // Add user message optimistically
            await MainActor.run {
                guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
                let userMessage = ConversationMessage(role: .user, content: message)
                conversations[conversationIndex].messages.append(userMessage)
                conversations[conversationIndex].updatedAt = Date()
                
                isComposing = true
                composerState = .thinking  // Start with thinking, backend will send specific state
                streamingContent = ""
                thinkingContent = ""  // Reset chain of thought
                statusMessage = ""
                activeTools = []
                completedTools = []
                failedTools = []
                usingIntentEngine = false  // Reset
                detectedGoal = nil
                requestStartTime = Date()  // Start timing
            }
            
            // Prepare to collect actions
            var accumulatedActions: [MessageAction] = []
            
            do {
                try await conversationService.sendMessage(
                    conversationId: conversationId,
                    prompt: message,
                    model: UserManager.shared.selectedModelId,
                    storePrompt: UserManager.shared.storePrompts
                ) { event in
                    Task { @MainActor in
                        switch event {
                        case .status(let status):
                            self.statusMessage = status
                            // Detect Intent Engine usage from status messages
                            if status.contains("transformation") {
                                self.usingIntentEngine = true
                                // Try to extract goal from status
                                // e.g., "Applying 'dark' transformation..." → "dark"
                                if let goal = self.extractGoal(from: status) {
                                    self.detectedGoal = goal
                                }
                            }
                            
                        case .state(let state):
                            // Update composer state based on backend intent
                            switch state {
                            case "thinking":
                                self.composerState = .thinking
                            case "editing":
                                self.composerState = .editing
                            case "composing":
                                self.composerState = .composing
                            default:
                                self.composerState = .thinking  // Fallback
                            }
                        
                        case .thinkingDelta(let content):
                            // Chain of thought streaming
                            self.thinkingContent += content
                        
                        case .content(let text):
                            self.streamingContent += text
                            
                        case .budgetUpdate(let update):
                            UserManager.shared.updateBudget(remaining: update.budget_remaining)
                        
                        case .toolStart(let toolName):
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if !self.activeTools.contains(toolName) {
                                    self.activeTools.append(toolName)
                                }
                            }
                        
                        case .toolComplete(let result):
                            // Move from active to completed with animation
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                self.activeTools.removeAll { $0 == result.tool }
                                if !self.completedTools.contains(result.tool) {
                                    self.completedTools.append(result.tool)
                                }
                            }
                            
                            let action = MessageAction(
                                type: result.success ? .projectModified : .error,
                                description: result.result,
                                success: result.success
                            )
                            accumulatedActions.append(action)
                        
                        case .toolError(let error):
                            // Extract tool name from error (format: "toolName: error message")
                            let toolName = error.components(separatedBy: ":").first ?? "Unknown"
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                self.activeTools.removeAll { $0 == toolName }
                                if !self.failedTools.contains(toolName) {
                                    self.failedTools.append(toolName)
                                }
                            }
                            
                            let action = MessageAction(
                                type: .error,
                                description: error,
                                success: false
                            )
                            accumulatedActions.append(action)
                        
                    case .complete:
                        
                        // Add assistant message with accumulated content
                        if let index = self.conversations.firstIndex(where: { $0.id == conversationId }) {
                            let assistantMessage = ConversationMessage(
                                role: .assistant,
                                content: self.streamingContent,
                                actions: accumulatedActions
                            )
                            self.conversations[index].messages.append(assistantMessage)
                            self.streamingContent = ""
                            self.thinkingContent = ""  // Reset chain of thought
                            accumulatedActions = []
                        }
                        
                        // Record metrics
                        if let startTime = self.requestStartTime {
                            let duration = Date().timeIntervalSince(startTime)
                            if self.usingIntentEngine {
                                self.metrics.recordIntentEngine(duration: duration)
                            } else {
                                self.metrics.recordLLMFallback(duration: duration)
                            }
                        }
                        
                        self.isComposing = false
                        self.composerState = .idle
                        self.usingIntentEngine = false
                        self.detectedGoal = nil
                        self.requestStartTime = nil
                        self.statusMessage = ""
                        self.activeTools = []
                        self.completedTools = []
                        self.failedTools = []
                        
                        // Reload conversation to get saved version from backend
                        Task {
                            await self.loadConversation(id: conversationId)
                        }
                        
                        case .error(let error):
                            self.conversationLoadError = error
                            self.isComposing = false
                            self.composerState = .idle
                            self.usingIntentEngine = false
                            self.detectedGoal = nil
                            self.thinkingContent = ""
                            self.streamingContent = ""
                            self.statusMessage = ""
                            self.activeTools = []
                            self.completedTools = []
                            self.failedTools = []
                            
                        case .toolCall(let toolCallEvent):
                            // Execute tool in real-time as SSE event arrives
                            
                            // Convert ToolCallEvent to ComposerToolCall
                            let toolCall = ComposerToolCall(
                                tool: toolCallEvent.name,
                                params: toolCallEvent.params
                            )
                            
                            // Execute tool using dispatcher
                            if let dispatcher = self.dispatcher {
                                Task {
                                    let result = await dispatcher.executeToolCall(toolCall)
                                    if !result.success {
                                    }
                                }
                            } else {
                            }
                        
                        default:
                            break
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isComposing = false
                    self.composerState = .idle
                    self.usingIntentEngine = false
                    self.detectedGoal = nil
                    self.thinkingContent = ""
                    self.streamingContent = ""
                    self.statusMessage = ""
                    self.activeTools = []
                    self.completedTools = []
                    self.failedTools = []
                    self.handleError(error)
                }
            }
        }
    }
    
    private func createNewConversation() {
        Task {
            do {
                // Project ID is required (composer is hidden if no project)
                guard let projectId = currentProjectId else {
                    return
                }
                
                let detail = try await conversationService.createConversation(projectId: projectId)
                let newConversation = Conversation(from: detail)
                
                await MainActor.run {
                    conversations.insert(newConversation, at: 0)
                    selectedConversationId = newConversation.id
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
    
    private func closeConversation(_ id: String) {
        Task {
            do {
                try await conversationService.archiveConversation(id: id)
                
                await MainActor.run {
                    conversations.removeAll { $0.id == id }
                    if selectedConversationId == id {
                        selectedConversationId = conversations.first?.id
                    }
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
    
    // MARK: - Load Conversations
    
    private func loadConversations() async {
        // Require project ID (composer is hidden if no project)
        guard let projectId = currentProjectId else {
            return
        }
        
        isLoadingConversations = true
        conversationLoadError = nil // Clear any previous errors
        defer { isLoadingConversations = false }
        
        do {
            let response = try await conversationService.listConversations(projectId: projectId)
            
            
            await MainActor.run {
                conversations = response.conversations.map { Conversation(from: $0) }
                conversationLoadError = nil // Clear error on success
                
                
                // Select first conversation if none selected
                if selectedConversationId == nil, let first = conversations.first {
                    selectedConversationId = first.id
                    Task {
                        await loadConversation(id: first.id)
                    }
                }
            }
        } catch {
            await MainActor.run {
                handleError(error)
            }
        }
    }
    
    private func loadConversation(id: String) async {
        do {
            let detail = try await conversationService.getConversation(id: id)
            
            
            await MainActor.run {
                if let index = conversations.firstIndex(where: { $0.id == id }) {
                    conversations[index] = Conversation(from: detail)
                }
            }
        } catch {
            // Don't set conversationLoadError for individual conversation loading failures
            // This prevents blocking the entire UI when one conversation fails to load
            
            // Only handle auth errors globally
            if let convError = error as? ConversationError {
                switch convError {
                case .unauthorized:
                    await MainActor.run {
                        hasValidToken = false
                        try? TokenManager.shared.deleteToken()
                    }
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error) {
        if let convError = error as? ConversationError {
            switch convError {
            case .unauthorized:
                // Lock the UI and clear the expired token
                hasValidToken = false
                try? TokenManager.shared.deleteToken()
            case .insufficientBudget:
                conversationLoadError = "Budget exhausted. Ask TellUr Stori for more credits."
            case .notFound:
                conversationLoadError = "Conversation not found."
            default:
                conversationLoadError = "Connection issue. Check your network."
            }
        } else {
            conversationLoadError = "Unable to load conversations. Check your connection."
        }
    }
    
    // MARK: - Helpers
    
    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func modelTooltip(_ model: AIModelInfo) -> String {
        var tooltip = "\(model.name)\n\(model.description)\n\(model.contextWindow) context • \(model.displayCost)"
        if let reasoning = model.reasoningEffort {
            tooltip += "\n\nVersion: \(reasoning)"
        }
        return tooltip
    }
    
    private func tokenExpirationTime() -> String? {
        guard let token = try? TokenManager.shared.getToken() else { return nil }
        
        // Decode JWT to get expiration
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        
        let payloadPart = String(parts[1])
        // Add padding if needed
        var base64 = payloadPart
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return nil
        }
        
        let expirationDate = Date(timeIntervalSince1970: exp)
        let now = Date()
        let timeRemaining = expirationDate.timeIntervalSince(now)
        
        if timeRemaining < 0 {
            return "Expired"
        } else if timeRemaining < 3600 {
            let minutes = Int(timeRemaining / 60)
            return "in \(minutes)m"
        } else if timeRemaining < 86400 {
            let hours = Int(timeRemaining / 3600)
            return "in \(hours)h"
        } else {
            let days = Int(timeRemaining / 86400)
            return "in \(days)d"
        }
    }
    
    // MARK: - Quick Actions View
    
    private var quickActionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Goals")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GoalCategory.allCases, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 6) {
                                ForEach(category.goals) { goal in
                                    Button(action: { sendQuickGoal(goal) }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: goal.icon)
                                                .font(.system(size: 11))
                                            Text(goal.displayName)
                                                .font(.system(size: 12))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.purple.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(goal.examplePrompt)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
        .background(Color(.windowBackgroundColor).opacity(0.98))
    }
    
    private func sendQuickGoal(_ goal: MusicalGoal) {
        promptText = goal.examplePrompt
        sendMessage()
    }
    
    // MARK: - Intent Engine Helpers
    
    private func extractGoal(from status: String) -> MusicalGoal? {
        // Extract goal from status like "Applying 'dark' transformation..."
        let lowercased = status.lowercased()
        return MusicalGoal.allCases.first { goal in
            lowercased.contains("'\(goal.rawValue)'")
        }
    }
}

// MARK: - Intent Engine Badge View

struct IntentEngineBadge: View {
    let goal: MusicalGoal?
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10))
            if let goal = goal {
                HStack(spacing: 3) {
                    Image(systemName: goal.icon)
                        .font(.system(size: 10))
                    Text(goal.displayName)
                        .font(.system(size: 11, weight: .semibold))
                }
            } else {
                Text("Intelligent Mode")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [Color.purple, Color.purple.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
        .shadow(color: .purple.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Animated Dots View

struct AnimatedDotsView: View {
    @State private var animationPhase = 0
    
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: animationPhase == index ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.4),
                        value: animationPhase
                    )
            }
        }
        .onReceive(timer) { _ in
            animationPhase = (animationPhase + 1) % 3
        }
    }
}
