//
//  LicensePlayerView.swift
//  Stori
//
//  Premium music player for purchased licenses
//  Spotify-inspired design with license-aware features
//

import SwiftUI
import AVFoundation

/// Full-featured license-aware audio player with premium design
struct LicensePlayerView: View {
    let license: PurchasedLicense
    
    @Environment(\.dismiss) private var dismiss
    @State private var playerState = LicensePlayerState()
    private let enforcer = LicenseEnforcer.shared
    
    // UI State
    @State private var showingLicenseInfo: Bool = false
    @State private var isDownloading: Bool = false
    @State private var downloadProgress: Double = 0
    @State private var showingDownloadSuccess: Bool = false
    @State private var isDraggingProgress: Bool = false
    @State private var dragProgress: Double = 0
    @State private var stemsExpanded: Bool = true
    @State private var showVolumeSlider: Bool = false
    
    // Digital Master and STEMs
    @State private var digitalMaster: DigitalMasterItem?
    @State private var isLoadingMaster: Bool = true
    @State private var stemPlayer: AVPlayer?
    @State private var playingStemId: UUID?
    @State private var isLoadingStemAudio: Bool = false
    
    private let accessControl: LicenseAccessControl
    private let accentColor: Color
    
    init(license: PurchasedLicense) {
        self.license = license
        self.accessControl = LicenseAccessControl(licenseType: license.licenseType)
        self.accentColor = StoriColors.licenseColor(for: license.licenseType)
    }
    
    var body: some View {
        ZStack {
            // Dynamic background
            playerBackground
            
            VStack(spacing: 0) {
                // Compact header
                playerHeader
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: StoriSpacing.xl) {
                        // Album Art with dynamic glow
                        albumArtView
                            .padding(.top, StoriSpacing.xl)
                        
                        // Track title and artist
                        trackInfoView
                        
                        // License badge
                        licenseBadgeView
                        
                        // Progress bar
                        playerProgressView
                            .padding(.horizontal, StoriSpacing.xxxl)
                        
                        // Transport controls
                        transportControlsView
                        
                        // Divider
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1)
                            .padding(.horizontal, StoriSpacing.xxxl)
                        
                        // STEMs Section
                        stemsSectionView
                            .padding(.horizontal, StoriSpacing.xxl)
                        
                        // Volume and actions
                        volumeAndActionsView
                            .padding(.horizontal, StoriSpacing.xxxl)
                        
                        // License rights summary
                        licenseRightsSummary
                            .padding(.horizontal, StoriSpacing.xxl)
                            .padding(.bottom, StoriSpacing.xxxl)
                    }
                }
            }
            
            // Warning overlay
            if playerState.showWarning {
                warningOverlay
            }
        }
        .frame(width: 520, height: 780)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            playerState.load(license: license)
            loadDigitalMaster()
        }
        .onDisappear {
            playerState.stop()
            stopStemPlayback()
        }
        .alert("Download Complete", isPresented: $showingDownloadSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(license.title) has been saved to your Downloads folder.")
        }
        .sheet(isPresented: $showingLicenseInfo) {
            LicenseDetailsSheet(license: license, accessControl: accessControl)
        }
    }
    
    // MARK: - Player Background
    
    private var playerBackground: some View {
        ZStack {
            // Base dark gradient
            LinearGradient(
                colors: [
                    Color(white: 0.08),
                    Color(white: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Accent color glow from top
            RadialGradient(
                colors: [
                    accentColor.opacity(0.35),
                    accentColor.opacity(0.1),
                    Color.clear
                ],
                center: .top,
                startRadius: 50,
                endRadius: 350
            )
            .offset(y: -50)
            
            // Secondary subtle glow
            RadialGradient(
                colors: [
                    accentColor.opacity(0.1),
                    Color.clear
                ],
                center: .bottom,
                startRadius: 100,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Header
    
    private var playerHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Now playing indicator
            VStack(spacing: 2) {
                Text("NOW PLAYING")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.5))
                
                Text(license.licenseType.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)
            }
            
            Spacer()
            
            Menu {
                Button {
                    showingLicenseInfo = true
                } label: {
                    Label("License Details", systemImage: "doc.text")
                }
                
                if accessControl.canDownload {
                    Button {
                        startDownload()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                
                if accessControl.canResell {
                    Button {
                        // TODO: Open resale flow
                    } label: {
                        Label("List for Sale", systemImage: "tag")
                    }
                }
                
                Divider()
                
                Button {
                    shareContent()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, StoriSpacing.md)
        .padding(.top, StoriSpacing.lg)
    }
    
    // MARK: - Album Art
    
    private var albumArtView: some View {
        ZStack {
            // Glow effect behind album art
            if let imageURL = license.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 260, height: 260)
                            .blur(radius: 60)
                            .opacity(0.5)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 30)
                    .fill(accentColor.opacity(0.3))
                    .frame(width: 280, height: 280)
                    .blur(radius: 50)
            }
            
            // Album art
            ZStack {
                if let imageURL = license.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            albumArtPlaceholder
                        @unknown default:
                            albumArtPlaceholder
                        }
                    }
                } else {
                    albumArtPlaceholder
                }
            }
            .frame(width: 260, height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            // Subtle rotation when playing
            .rotationEffect(.degrees(playerState.isPlaying ? 0.5 : 0))
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: playerState.isPlaying)
        }
    }
    
    private var albumArtPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: license.licenseType.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: license.licenseType.systemIcon)
                .font(.system(size: 70, weight: .light))
                .foregroundColor(.white.opacity(0.3))
        }
    }
    
    // MARK: - Track Info
    
    private var trackInfoView: some View {
        VStack(spacing: StoriSpacing.xs) {
            Text(license.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(license.artistName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    // MARK: - License Badge
    
    private var licenseBadgeView: some View {
        HStack(spacing: StoriSpacing.sm) {
            Image(systemName: statusIcon)
                .font(.system(size: 11, weight: .semibold))
            Text(statusText)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, StoriSpacing.lg)
        .padding(.vertical, StoriSpacing.sm)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
                .overlay(
                    Capsule()
                        .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Progress View
    
    private var playerProgressView: some View {
        VStack(spacing: StoriSpacing.sm) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)
                    
                    // Progress fill with gradient
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: license.licenseType.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * (isDraggingProgress ? dragProgress : playerState.progress), height: 4)
                    
                    // Interactive knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .offset(x: geo.size.width * (isDraggingProgress ? dragProgress : playerState.progress) - 7)
                        .opacity(isDraggingProgress ? 1 : 0)
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingProgress = true
                            dragProgress = max(0, min(1, value.location.x / geo.size.width))
                        }
                        .onEnded { _ in
                            playerState.seek(to: dragProgress)
                            isDraggingProgress = false
                        }
                )
            }
            .frame(height: 14)
            
            // Time labels
            HStack {
                Text(playerState.formattedCurrentTime)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                Text("-\(playerState.formattedTimeRemaining)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    // MARK: - Transport Controls
    
    private var transportControlsView: some View {
        HStack(spacing: StoriSpacing.xxxl) {
            // Shuffle (placeholder)
            Button { } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            
            // Skip backward
            Button {
                playerState.skipBackward()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            
            // Play/Pause - main button
            Button {
                // Stop stem if playing
                if playingStemId != nil {
                    stopStemPlayback()
                }
                playerState.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                        .shadow(color: accentColor.opacity(0.5), radius: 15, y: 5)
                    
                    Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.black)
                        .offset(x: playerState.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)
            .disabled(!enforcer.canPlay(license: license).isAllowed)
            
            // Skip forward
            Button {
                playerState.skipForward()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            
            // Repeat (placeholder)
            Button { } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Volume and Actions
    
    private var volumeAndActionsView: some View {
        HStack(spacing: StoriSpacing.lg) {
            // Volume control
            HStack(spacing: StoriSpacing.sm) {
                Button {
                    playerState.isMuted.toggle()
                } label: {
                    Image(systemName: playerState.isMuted ? "speaker.slash.fill" : volumeIcon)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24)
                }
                .buttonStyle(.plain)
                
                Slider(value: $playerState.volume, in: 0...1)
                    .tint(accentColor)
                    .frame(width: 100)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: StoriSpacing.lg) {
                if accessControl.canDownload {
                    Button {
                        startDownload()
                    } label: {
                        Image(systemName: isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloading)
                }
                
                Button {
                    shareContent()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                if accessControl.canResell {
                    Button {
                        // Resell flow
                    } label: {
                        Image(systemName: "tag")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var volumeIcon: String {
        if playerState.volume == 0 {
            return "speaker.fill"
        } else if playerState.volume < 0.5 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
    
    // MARK: - License Rights Summary
    
    private var licenseRightsSummary: some View {
        VStack(spacing: StoriSpacing.md) {
            HStack {
                Text("License Rights")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Button {
                    showingLicenseInfo = true
                } label: {
                    Text("View Details")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(accentColor)
                }
                .buttonStyle(.plain)
            }
            
            // Rights grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: StoriSpacing.sm) {
                ForEach(accessControl.rightsDescription.prefix(4), id: \.self) { right in
                    HStack(spacing: StoriSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(StoriColors.success)
                        
                        Text(right)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(StoriSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: StoriRadius.md)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: StoriRadius.md)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - STEMs Section
    
    private var stemsSectionView: some View {
        VStack(spacing: 0) {
            // Header with expand/collapse
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    stemsExpanded.toggle()
                }
            } label: {
                HStack {
                    HStack(spacing: StoriSpacing.sm) {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(accentColor)
                        
                        Text("Tracks")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if let master = digitalMaster {
                            Text("\(master.stems.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                    }
                    
                    Spacer()
                    
                    if isLoadingMaster {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.white)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .rotationEffect(.degrees(stemsExpanded ? 0 : -90))
                    }
                }
                .padding(StoriSpacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expandable content
            if stemsExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    if isLoadingMaster {
                        VStack(spacing: StoriSpacing.md) {
                            ForEach(0..<3, id: \.self) { _ in
                                HStack(spacing: StoriSpacing.md) {
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 36, height: 36)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white.opacity(0.1))
                                            .frame(width: 120, height: 12)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white.opacity(0.05))
                                            .frame(width: 60, height: 10)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, StoriSpacing.lg)
                                .padding(.vertical, StoriSpacing.sm)
                            }
                        }
                        .padding(.vertical, StoriSpacing.sm)
                    } else if let master = digitalMaster, !master.stems.isEmpty {
                        VStack(spacing: 2) {
                            ForEach(Array(master.stems.enumerated()), id: \.element.id) { index, stem in
                                stemRowView(stem, index: index)
                            }
                        }
                        .padding(.vertical, StoriSpacing.xs)
                    } else {
                        VStack(spacing: StoriSpacing.sm) {
                            Image(systemName: "waveform.slash")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.2))
                            Text("No tracks available")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, StoriSpacing.xl)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: StoriRadius.md)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: StoriRadius.md)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private func stemRowView(_ stem: MasterStemInfo, index: Int) -> some View {
        let isPlaying = playingStemId == stem.id
        let hasAudio = stem.audioURI != nil
        
        return Button {
            if hasAudio {
                toggleStemPlayback(for: stem)
            }
        } label: {
            HStack(spacing: StoriSpacing.md) {
                // Track number / Play indicator
                ZStack {
                    if isPlaying {
                        // Animated bars
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(accentColor)
                                    .frame(width: 3, height: CGFloat.random(in: 8...16))
                                    .animation(
                                        .easeInOut(duration: 0.4)
                                            .repeatForever()
                                            .delay(Double(i) * 0.1),
                                        value: isPlaying
                                    )
                            }
                        }
                        .frame(width: 20, height: 20)
                    } else if isLoadingStemAudio && playingStemId == stem.id {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(accentColor)
                    } else if hasAudio {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isPlaying ? accentColor.opacity(0.2) : Color.white.opacity(0.05))
                )
                
                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(stem.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isPlaying ? accentColor : .white)
                        .lineLimit(1)
                    
                    HStack(spacing: StoriSpacing.xs) {
                        Text(formatStemDuration(stem.duration))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                        
                        if isPlaying {
                            Circle()
                                .fill(StoriColors.success)
                                .frame(width: 4, height: 4)
                            Text("Playing")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(StoriColors.success)
                        }
                    }
                }
                
                Spacer()
                
                // Status badge
                HStack(spacing: 4) {
                    if hasAudio {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(StoriColors.success)
                        Text("IPFS")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                        Text("MIDI")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, StoriSpacing.lg)
            .padding(.vertical, StoriSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: StoriRadius.sm)
                    .fill(isPlaying ? accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasAudio)
        .opacity(hasAudio ? 1 : 0.5)
    }
    
    private func formatStemDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    // MARK: - Load Digital Master
    
    private func loadDigitalMaster() {
        isLoadingMaster = true
        
        Task {
            do {
                let master = try await DigitalMasterService.shared.fetchDigitalMasterById(tokenId: license.masterId)
                await MainActor.run {
                    digitalMaster = master
                    isLoadingMaster = false
                }
            } catch {
                await MainActor.run {
                    isLoadingMaster = false
                }
            }
        }
    }
    
    // MARK: - STEM Audio Playback
    
    private func toggleStemPlayback(for stem: MasterStemInfo) {
        // If currently playing this stem, stop it
        if playingStemId == stem.id {
            stopStemPlayback()
            return
        }
        
        // Stop any current stem playback
        stopStemPlayback()
        
        // Also pause main player if playing
        if playerState.isPlaying {
            playerState.togglePlayPause()
        }
        
        guard let audioURI = stem.audioURI else { return }
        
        // Convert IPFS URI to gateway URL
        let urlString: String
        if audioURI.hasPrefix("ipfs://") {
            let hash = String(audioURI.dropFirst(7))
            urlString = "\(StoriEnvironment.ipfsGatewayURL)/ipfs/\(hash)"
        } else {
            urlString = audioURI
        }
        
        guard let url = URL(string: urlString) else { return }
        
        isLoadingStemAudio = true
        playingStemId = stem.id
        
        // Create player and play
        let playerItem = AVPlayerItem(url: url)
        stemPlayer = AVPlayer(playerItem: playerItem)
        
        // Observe when playback ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            stopStemPlayback()
        }
        
        stemPlayer?.play()
        isLoadingStemAudio = false
    }
    
    private func stopStemPlayback() {
        stemPlayer?.pause()
        stemPlayer = nil
        playingStemId = nil
        isLoadingStemAudio = false
    }
    
    // MARK: - Status Properties
    
    private var statusIcon: String {
        switch license.licenseType {
        case .fullOwnership:
            return "crown.fill"
        case .streaming:
            return "infinity"
        case .limitedPlay:
            let remaining = enforcer.getRemainingPlays(for: license)
            return remaining <= 3 ? "exclamationmark.triangle.fill" : "play.circle.fill"
        case .timeLimited:
            if let days = license.daysRemaining, days <= 3 {
                return "clock.badge.exclamationmark.fill"
            }
            return "clock.fill"
        case .commercialLicense:
            return "building.2.fill"
        }
    }
    
    private var statusText: String {
        switch license.licenseType {
        case .fullOwnership:
            return "Full Ownership • Unlimited"
        case .streaming:
            return "Streaming • Unlimited Plays"
        case .limitedPlay:
            let remaining = enforcer.getRemainingPlays(for: license)
            let total = license.totalPlays ?? 0
            return "\(remaining)/\(total) plays remaining"
        case .timeLimited:
            if let days = license.daysRemaining {
                return "\(days) days remaining"
            }
            return "Time Limited"
        case .commercialLicense:
            return "Commercial • Full Rights"
        }
    }
    
    private var statusColor: Color {
        switch license.licenseType {
        case .fullOwnership:
            return StoriColors.licenseColor(for: .fullOwnership)
        case .streaming:
            return StoriColors.licenseColor(for: .streaming)
        case .limitedPlay:
            let remaining = enforcer.getRemainingPlays(for: license)
            return remaining <= 3 ? StoriColors.warning : StoriColors.licenseColor(for: .limitedPlay)
        case .timeLimited:
            if let days = license.daysRemaining, days <= 3 {
                return StoriColors.warning
            }
            return StoriColors.licenseColor(for: .timeLimited)
        case .commercialLicense:
            return StoriColors.licenseColor(for: .commercialLicense)
        }
    }
    
    // MARK: - Warning Overlay
    
    private var warningOverlay: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: StoriSpacing.xl) {
                // Warning icon with glow
                ZStack {
                    Circle()
                        .fill(StoriColors.warning.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .blur(radius: 15)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(StoriColors.warning)
                }
                
                Text(playerState.warningMessage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: StoriSpacing.md) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Go Back")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, StoriSpacing.xl)
                            .padding(.vertical, StoriSpacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: StoriRadius.md)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        playerState.showWarning = false
                    } label: {
                        Text("Continue Anyway")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, StoriSpacing.xl)
                            .padding(.vertical, StoriSpacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: StoriRadius.md)
                                    .fill(StoriColors.warning)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(StoriSpacing.xxxl)
            .background(
                RoundedRectangle(cornerRadius: StoriRadius.xl)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: StoriRadius.xl)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 30)
        }
    }
    
    // MARK: - Actions
    
    private func startDownload() {
        guard accessControl.canDownload else { return }
        
        isDownloading = true
        downloadProgress = 0
        
        // Simulate download
        // TODO: Replace with real IPFS download
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            downloadProgress += 0.02
            if downloadProgress >= 1.0 {
                timer.invalidate()
                isDownloading = false
                showingDownloadSuccess = true
            }
        }
    }
    
    private func shareContent() {
        let shareText = "Check out \"\(license.title)\" by \(license.artistName) on Stori!"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shareText, forType: .string)
    }
}

// MARK: - License Details Sheet

struct LicenseDetailsSheet: View {
    let license: PurchasedLicense
    let accessControl: LicenseAccessControl
    
    @Environment(\.dismiss) private var dismiss
    private let enforcer = LicenseEnforcer.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("License Details")
                    .font(.headline)
                
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
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // License Type Header
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: license.licenseType.gradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: license.licenseType.systemIcon)
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(license.licenseType.title)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(license.title)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Divider()
                    
                    // License Status
                    VStack(alignment: .leading, spacing: 12) {
                        Text("License Status")
                            .font(.headline)
                        
                        statusRow(icon: "checkmark.circle.fill", color: .green, label: "Status", value: license.accessState.label)
                        statusRow(icon: "calendar", color: .blue, label: "Purchased", value: formattedPurchaseDate)
                        statusRow(icon: "tag", color: .purple, label: "Price Paid", value: String(format: "%.3f TUS", license.purchasePrice))
                        
                        if license.licenseType == .limitedPlay {
                            let remaining = enforcer.getRemainingPlays(for: license)
                            let total = license.totalPlays ?? 0
                            statusRow(icon: "play.circle", color: remaining <= 3 ? .orange : .green, label: "Plays Remaining", value: "\(remaining) of \(total)")
                        }
                        
                        if license.licenseType == .timeLimited, let days = license.daysRemaining {
                            statusRow(icon: "clock", color: days <= 3 ? .orange : .green, label: "Time Remaining", value: "\(days) days")
                        }
                    }
                    
                    Divider()
                    
                    // Rights & Permissions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Rights")
                            .font(.headline)
                        
                        ForEach(accessControl.rightsDescription, id: \.self) { right in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(right)
                                    .font(.subheadline)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Restrictions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Restrictions")
                            .font(.headline)
                        
                        if !accessControl.canDownload {
                            restrictionRow("No offline download")
                        }
                        if !accessControl.canResell {
                            restrictionRow("Cannot be resold")
                        }
                        if !accessControl.hasUnlimitedPlays {
                            restrictionRow("Limited number of plays")
                        }
                        if accessControl.hasExpiration {
                            restrictionRow("Access expires after time period")
                        }
                        if license.licenseType != .commercialLicense {
                            restrictionRow("Personal use only - no commercial use")
                        }
                    }
                    
                    Divider()
                    
                    // Blockchain Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Blockchain")
                            .font(.headline)
                        
                        HStack {
                            Text("Instance ID")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(license.instanceId)
                                .font(.system(.caption, design: .monospaced))
                        }
                        
                        HStack {
                            Text("Transaction")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(license.transactionHash.prefix(10))...\(license.transactionHash.suffix(8))")
                                .font(.system(.caption, design: .monospaced))
                        }
                        
                        HStack {
                            Text("Network")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Stori L1")
                        }
                    }
                }
                .padding(24)
            }
            
            // Close Button
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding()
        }
        .frame(width: 450, height: 600)
        .background(Color(.windowBackgroundColor))
    }
    
    private var formattedPurchaseDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: license.purchaseDate)
    }
    
    private func statusRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
    
    private func restrictionRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red.opacity(0.7))
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
