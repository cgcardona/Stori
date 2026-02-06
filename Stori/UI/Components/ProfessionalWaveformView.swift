//
//  ProfessionalWaveformView.swift
//  Stori
//
//  Professional waveform visualization for audio regions
//

import SwiftUI
import AVFoundation

/// Professional waveform view that renders stable, high-quality waveforms
/// from actual audio file data without being affected by playhead position.
/// 
/// Professional DAW behavior: This view renders at a FIXED size based on audio content.
/// It does NOT scale to fit container - the parent is responsible for:
/// - Setting the correct frame width (audioFile.duration * pixelsPerSecond)
/// - Tiling for loops (via HStack or similar)
/// - Clipping to region bounds
struct ProfessionalWaveformView: View {
    let audioFile: AudioFile
    let style: WaveformStyle
    let color: Color
    
    /// Region offset within the audio file (for split regions)
    let regionOffset: TimeInterval
    
    /// Region duration (for split regions)
    let regionDuration: TimeInterval
    
    @State private var audioAnalyzer = AudioAnalyzer()
    @State private var waveformData: AudioAnalyzer.WaveformData?
    @State private var isLoading = false
    @State private var loadingError: Error?
    
    /// Computed time range for this region within the audio file
    private var timeRange: ClosedRange<TimeInterval>? {
        // Only use time range if this is a partial region (offset > 0 or duration < file duration)
        let isPartialRegion = regionOffset > 0 || regionDuration < audioFile.duration - 0.01
        guard isPartialRegion else { return nil }
        
        let startTime = regionOffset
        let endTime = min(regionOffset + regionDuration, audioFile.duration)
        guard startTime < endTime else { return nil }
        
        return startTime...endTime
    }
    
    init(audioFile: AudioFile, style: WaveformStyle = .bars, color: Color = .white, regionOffset: TimeInterval = 0, regionDuration: TimeInterval? = nil) {
        self.audioFile = audioFile
        self.style = style
        self.color = color
        self.regionOffset = regionOffset
        self.regionDuration = regionDuration ?? audioFile.duration
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let waveformData = waveformData {
                    // Render professional waveform with time range for split regions
                    // Parent handles tiling for loops - this just renders ONE waveform
                    ProfessionalWaveformRenderer(
                        waveformData: waveformData,
                        size: geometry.size,
                        style: style,
                        color: color,
                        timeRange: timeRange
                    )
                    // Use drawingGroup to cache the rendering as a texture
                    // This prevents re-rendering when parent container resizes
                    .drawingGroup()
                } else if isLoading {
                    // Loading state with professional styling
                    LoadingWaveformView(size: geometry.size, color: color)
                } else if loadingError != nil {
                    // Error state with fallback waveform
                    FallbackWaveformView(size: geometry.size, color: color)
                } else {
                    // Initial state
                    Color.clear
                }
            }
        }
        .task {
            await loadWaveformData()
        }
        .onChange(of: audioFile.url) { _, _ in
            Task {
                await loadWaveformData()
            }
        }
    }
    
    /// Load waveform data using shared analyzer for consistent caching
    private func loadWaveformData() async {
        // Resolve URL on MainActor; async context may run off MainActor after first await
        let url = await audioFile.resolvedURL(projectDirectory: nil)
        let sharedAnalyzer = AudioAnalyzer.shared
        
        // Check cache first
        if let cachedData = sharedAnalyzer.getCachedWaveform(for: url) {
            await MainActor.run {
                self.waveformData = cachedData
                self.loadingError = nil
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            loadingError = nil
        }
        
        do {
            // Analyze with high resolution for professional quality
            let data = try await sharedAnalyzer.analyzeAudioFile(at: url, targetSamples: 2000)
            await MainActor.run {
                self.waveformData = data
                self.isLoading = false
                self.loadingError = nil
            }
        } catch {
            await MainActor.run {
                self.loadingError = error
                self.isLoading = false
            }
        }
    }
}

// MARK: - Professional Waveform Renderer

struct ProfessionalWaveformRenderer: View {
    let waveformData: AudioAnalyzer.WaveformData
    let size: CGSize
    let style: WaveformStyle
    let color: Color
    let timeRange: ClosedRange<TimeInterval>?
    
    init(waveformData: AudioAnalyzer.WaveformData, size: CGSize, style: WaveformStyle, color: Color, timeRange: ClosedRange<TimeInterval>? = nil) {
        self.waveformData = waveformData
        self.size = size
        self.style = style
        self.color = color
        self.timeRange = timeRange
    }
    
    var body: some View {
        switch style {
        case .bars:
            BarsWaveformView(waveformData: waveformData, size: size, color: color, timeRange: timeRange)
        case .line:
            LineWaveformView(waveformData: waveformData, size: size, color: color, timeRange: timeRange)
        case .filled:
            FilledWaveformView(waveformData: waveformData, size: size, color: color, timeRange: timeRange)
        }
    }
}

// MARK: - Bars Waveform (Professional DAW Style)

struct BarsWaveformView: View {
    let waveformData: AudioAnalyzer.WaveformData
    let size: CGSize
    let color: Color
    let timeRange: ClosedRange<TimeInterval>?
    
    init(waveformData: AudioAnalyzer.WaveformData, size: CGSize, color: Color, timeRange: ClosedRange<TimeInterval>? = nil) {
        self.waveformData = waveformData
        self.size = size
        self.color = color
        self.timeRange = timeRange
    }
    
    var body: some View {
        Canvas { context, canvasSize in
            // Render waveform at the canvas size (parent sets fixed width)
            let bars = waveformData.professionalWaveformBars(for: canvasSize, style: .bars, timeRange: timeRange)
            let centerY = canvasSize.height / 2
            let barWidth: CGFloat = max(1, canvasSize.width / CGFloat(max(1, bars.count)))
            
            // Create gradient for professional look
            let gradient = Gradient(colors: [
                color.opacity(0.9),
                color.opacity(0.6)
            ])
            
            for (index, bar) in bars.enumerated() {
                let x = CGFloat(index) * barWidth
                let barHeight = bar.height
                
                // Draw bar from center outward (professional DAW standard)
                let topRect = CGRect(
                    x: x,
                    y: centerY - barHeight / 2,
                    width: barWidth - 0.5, // Small gap between bars
                    height: barHeight / 2
                )
                
                let bottomRect = CGRect(
                    x: x,
                    y: centerY,
                    width: barWidth - 0.5,
                    height: barHeight / 2
                )
                
                // Draw with gradient
                context.fill(
                    Path(topRect),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: centerY - barHeight / 2),
                        endPoint: CGPoint(x: 0, y: centerY)
                    )
                )
                
                context.fill(
                    Path(bottomRect),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: centerY),
                        endPoint: CGPoint(x: 0, y: centerY + barHeight / 2)
                    )
                )
            }
        }
    }
}

// MARK: - Line Waveform

struct LineWaveformView: View {
    let waveformData: AudioAnalyzer.WaveformData
    let size: CGSize
    let color: Color
    let timeRange: ClosedRange<TimeInterval>?
    
    init(waveformData: AudioAnalyzer.WaveformData, size: CGSize, color: Color, timeRange: ClosedRange<TimeInterval>? = nil) {
        self.waveformData = waveformData
        self.size = size
        self.color = color
        self.timeRange = timeRange
    }
    
    var body: some View {
        Canvas { context, canvasSize in
            let points = waveformData.pathPoints(for: canvasSize, timeRange: timeRange)
            guard points.count >= 2 else { return }
            
            var path = Path()
            path.move(to: points[0])
            
            for i in stride(from: 1, to: points.count, by: 2) {
                if i < points.count {
                    path.addLine(to: points[i])
                }
            }
            
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}

// MARK: - Filled Waveform

struct FilledWaveformView: View {
    let waveformData: AudioAnalyzer.WaveformData
    let size: CGSize
    let color: Color
    let timeRange: ClosedRange<TimeInterval>?
    
    init(waveformData: AudioAnalyzer.WaveformData, size: CGSize, color: Color, timeRange: ClosedRange<TimeInterval>? = nil) {
        self.waveformData = waveformData
        self.size = size
        self.color = color
        self.timeRange = timeRange
    }
    
    var body: some View {
        Canvas { context, canvasSize in
            let points = waveformData.pathPoints(for: canvasSize, timeRange: timeRange)
            guard !points.isEmpty else { return }
            
            var path = Path()
            let centerY = canvasSize.height / 2
            
            // Start from center left
            path.move(to: CGPoint(x: 0, y: centerY))
            
            // Draw top half
            for i in stride(from: 0, to: points.count, by: 2) {
                if i < points.count {
                    path.addLine(to: points[i])
                }
            }
            
            // Draw bottom half (reversed)
            for i in stride(from: points.count - 1, through: 1, by: -2) {
                if i < points.count {
                    path.addLine(to: points[i])
                }
            }
            
            // Close path
            path.closeSubpath()
            
            // Fill with gradient
            let gradient = Gradient(colors: [
                color.opacity(0.8),
                color.opacity(0.3)
            ])
            
            context.fill(
                path,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: canvasSize.height)
                )
            )
        }
    }
}

// MARK: - Loading States

struct LoadingWaveformView: View {
    let size: CGSize
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<Int(size.width / 4), id: \.self) { _ in
                Rectangle()
                    .fill(color.opacity(0.3))
                    .frame(width: 2, height: CGFloat.random(in: 10...size.height * 0.8))
                    .animation(.easeInOut(duration: 1.5).repeatForever(), value: UUID())
            }
        }
    }
}

struct FallbackWaveformView: View {
    let size: CGSize
    let color: Color
    
    var body: some View {
        // Simple static waveform pattern
        HStack(spacing: 1) {
            ForEach(0..<Int(size.width / 3), id: \.self) { index in
                Rectangle()
                    .fill(color.opacity(0.4))
                    .frame(
                        width: 2,
                        height: sin(Double(index) * 0.3) * Double(size.height * 0.3) + Double(size.height * 0.4)
                    )
            }
        }
    }
}
