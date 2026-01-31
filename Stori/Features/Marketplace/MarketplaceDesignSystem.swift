//
//  MarketplaceDesignSystem.swift
//  Stori
//
//  Unified design system for the Stori Marketplace
//  Provides consistent colors, gradients, typography, and reusable components
//

import SwiftUI

// MARK: - Stori Colors

/// Unified color palette for the marketplace
enum StoriColors {
    // Primary Brand Colors
    static let primary = Color(red: 0.55, green: 0.35, blue: 1.0)        // Purple
    static let secondary = Color(red: 0.35, green: 0.75, blue: 1.0)      // Blue
    static let accent = Color(red: 1.0, green: 0.45, blue: 0.55)         // Coral/Pink
    
    // Semantic Colors
    static let success = Color(red: 0.2, green: 0.85, blue: 0.55)        // Mint Green
    static let warning = Color(red: 1.0, green: 0.75, blue: 0.25)        // Amber
    static let error = Color(red: 1.0, green: 0.35, blue: 0.4)           // Red
    
    // Surface Colors
    static let surfacePrimary = Color(.windowBackgroundColor)
    static let surfaceElevated = Color(.controlBackgroundColor)
    static let surfaceOverlay = Color.black.opacity(0.4)
    
    // Text Colors
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textMuted = Color.secondary.opacity(0.6)
    
    // License Type Colors
    static func licenseColor(for type: LicenseType) -> Color {
        switch type {
        case .fullOwnership: return Color(red: 0.95, green: 0.4, blue: 0.6)   // Pink
        case .streaming: return Color(red: 0.3, green: 0.7, blue: 1.0)        // Blue
        case .limitedPlay: return Color(red: 1.0, green: 0.65, blue: 0.3)     // Orange
        case .timeLimited: return Color(red: 0.4, green: 0.85, blue: 0.55)    // Green
        case .commercialLicense: return Color(red: 0.65, green: 0.45, blue: 1.0) // Purple
        }
    }
}

// MARK: - Stori Gradients

/// Unified gradient definitions
enum StoriGradients {
    // Brand Gradients
    static let primary = LinearGradient(
        colors: [StoriColors.primary, StoriColors.secondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let accent = LinearGradient(
        colors: [StoriColors.accent, StoriColors.primary],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    static let premium = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.85, blue: 0.4),
            Color(red: 1.0, green: 0.6, blue: 0.3)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // License Type Gradients
    static func licenseGradient(for type: LicenseType) -> LinearGradient {
        LinearGradient(
            colors: type.gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Background Gradients
    static let cardBackground = LinearGradient(
        colors: [
            Color(.controlBackgroundColor),
            Color(.controlBackgroundColor).opacity(0.95)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Glass Effect
    static func glassGradient(color: Color = .white) -> LinearGradient {
        LinearGradient(
            colors: [
                color.opacity(0.15),
                color.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Stori Typography

/// Typography scale for consistent text styling
enum StoriTypography {
    // Display
    static func display(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    
    // Headings
    static let h1 = Font.system(size: 24, weight: .bold, design: .rounded)
    static let h2 = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let h3 = Font.system(size: 16, weight: .semibold)
    
    // Body
    static let body = Font.system(size: 14, weight: .regular)
    static let bodyMedium = Font.system(size: 14, weight: .medium)
    static let bodySemibold = Font.system(size: 14, weight: .semibold)
    
    // Caption
    static let caption = Font.system(size: 12, weight: .regular)
    static let captionMedium = Font.system(size: 12, weight: .medium)
    static let captionSemibold = Font.system(size: 12, weight: .semibold)
    
    // Tiny
    static let tiny = Font.system(size: 10, weight: .medium)
    static let tinyBold = Font.system(size: 10, weight: .bold)
    
    // Monospace
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 10, weight: .medium, design: .monospaced)
}

// MARK: - Stori Spacing

/// Consistent spacing values
enum StoriSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

// MARK: - Stori Radius

/// Consistent corner radius values
enum StoriRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20
    static let full: CGFloat = 999
}

// MARK: - Reusable Components

/// Glass-morphism card background
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = StoriRadius.lg
    var padding: CGFloat = StoriSpacing.lg
    
    init(cornerRadius: CGFloat = StoriRadius.lg, padding: CGFloat = StoriSpacing.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.padding = padding
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }
}

/// Elevated card with shadow
struct ElevatedCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = StoriRadius.lg
    @State private var isHovered = false
    
    init(cornerRadius: CGFloat = StoriRadius.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isHovered
                            ? LinearGradient(colors: [StoriColors.primary.opacity(0.5), StoriColors.secondary.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isHovered ? StoriColors.primary.opacity(0.15) : Color.black.opacity(0.1),
                radius: isHovered ? 16 : 8,
                y: isHovered ? 8 : 4
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Gradient button with press animation
struct StoriButton: View {
    let title: String
    let icon: String?
    let style: ButtonStyle
    let action: () -> Void
    
    @State private var isPressed = false
    
    enum ButtonStyle {
        case primary
        case secondary
        case accent
        case ghost
        case license(LicenseType)
        
        var gradient: LinearGradient {
            switch self {
            case .primary:
                return StoriGradients.primary
            case .secondary:
                return LinearGradient(colors: [Color(.controlBackgroundColor)], startPoint: .leading, endPoint: .trailing)
            case .accent:
                return StoriGradients.accent
            case .ghost:
                return LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
            case .license(let type):
                return StoriGradients.licenseGradient(for: type)
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .secondary, .ghost:
                return .primary
            default:
                return .white
            }
        }
        
        var needsBorder: Bool {
            switch self {
            case .secondary, .ghost:
                return true
            default:
                return false
            }
        }
    }
    
    init(_ title: String, icon: String? = nil, style: ButtonStyle = .primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: StoriSpacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(StoriTypography.bodySemibold)
            }
            .foregroundColor(style.foregroundColor)
            .padding(.horizontal, StoriSpacing.xl)
            .padding(.vertical, StoriSpacing.md)
            .background(style.gradient)
            .clipShape(RoundedRectangle(cornerRadius: StoriRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: StoriRadius.md)
                    .stroke(
                        style.needsBorder
                            ? Color.secondary.opacity(0.3)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
    }
}

/// Floating pill badge
struct StoriBadge: View {
    let text: String
    let icon: String?
    let style: BadgeStyle
    
    enum BadgeStyle {
        case `default`
        case success
        case warning
        case info
        case premium
        case license(LicenseType)
        
        var backgroundColor: Color {
            switch self {
            case .default: return Color.secondary.opacity(0.2)
            case .success: return StoriColors.success.opacity(0.2)
            case .warning: return StoriColors.warning.opacity(0.2)
            case .info: return StoriColors.secondary.opacity(0.2)
            case .premium: return Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.2)
            case .license(let type): return StoriColors.licenseColor(for: type).opacity(0.2)
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .default: return .secondary
            case .success: return StoriColors.success
            case .warning: return StoriColors.warning
            case .info: return StoriColors.secondary
            case .premium: return Color(red: 0.85, green: 0.6, blue: 0.2)
            case .license(let type): return StoriColors.licenseColor(for: type)
            }
        }
    }
    
    init(_ text: String, icon: String? = nil, style: BadgeStyle = .default) {
        self.text = text
        self.icon = icon
        self.style = style
    }
    
    var body: some View {
        HStack(spacing: StoriSpacing.xxs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(StoriTypography.tinyBold)
        }
        .foregroundColor(style.foregroundColor)
        .padding(.horizontal, StoriSpacing.sm)
        .padding(.vertical, StoriSpacing.xxs)
        .background(
            Capsule().fill(style.backgroundColor)
        )
    }
}

/// Animated play button
struct PlayButton: View {
    let isPlaying: Bool
    let isLoading: Bool
    let size: CGFloat
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    init(isPlaying: Bool, isLoading: Bool = false, size: CGFloat = 50, color: Color = StoriColors.primary, action: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.isLoading = isLoading
        self.size = size
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Glow
                Circle()
                    .fill(color.opacity(isHovered ? 0.3 : 0.15))
                    .frame(width: size + 10, height: size + 10)
                    .blur(radius: 8)
                
                // Background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: color.opacity(0.4), radius: 8, y: 4)
                
                // Icon
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundColor(.white)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Progress bar with gradient
struct StoriProgressBar: View {
    let progress: Double
    let licenseType: LicenseType?
    var height: CGFloat = 4
    var showKnob: Bool = false
    
    @State private var isDragging = false
    var onSeek: ((Double) -> Void)?
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: height)
                
                // Progress fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        licenseType != nil
                            ? StoriGradients.licenseGradient(for: licenseType!)
                            : StoriGradients.primary
                    )
                    .frame(width: geo.size.width * min(1, max(0, progress)), height: height)
                
                // Knob
                if showKnob {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .offset(x: geo.size.width * min(1, max(0, progress)) - 7)
                        .opacity(isDragging ? 1 : 0)
                }
            }
            .frame(height: max(height, 14))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let newProgress = max(0, min(1, value.location.x / geo.size.width))
                        onSeek?(newProgress)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: max(height, 14))
    }
}

/// Stat display badge for marketplace
struct StoriStatBadge: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(StoriTypography.h2)
                .foregroundColor(color)
            Text(label)
                .font(StoriTypography.tiny)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, StoriSpacing.md)
        .padding(.vertical, StoriSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: StoriRadius.sm)
                .fill(color.opacity(0.1))
        )
    }
}

/// IPFS Image loader with fallback
struct IPFSImage: View {
    let uri: String?
    let fallbackGradient: [Color]
    var cornerRadius: CGFloat = StoriRadius.lg
    
    private var gatewayURL: URL? {
        guard let uri = uri, !uri.isEmpty else { return nil }
        if uri.hasPrefix("ipfs://") {
            let cid = String(uri.dropFirst(7))
            return URL(string: "http://127.0.0.1:8080/ipfs/\(cid)")
        }
        return URL(string: uri)
    }
    
    var body: some View {
        Group {
            if let url = gatewayURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        gradientFallback
                    @unknown default:
                        gradientFallback
                    }
                }
            } else {
                gradientFallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    private var gradientFallback: some View {
        ZStack {
            LinearGradient(
                colors: fallbackGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.white.opacity(0.25))
        }
    }
}

/// Animated skeleton loader
struct SkeletonLoader: View {
    @State private var isAnimating = false
    var height: CGFloat = 20
    var cornerRadius: CGFloat = StoriRadius.sm
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Color.secondary.opacity(0.1),
                        Color.secondary.opacity(0.2),
                        Color.secondary.opacity(0.1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: height)
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 300 : -300)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - View Modifiers

/// Glow effect modifier
struct GlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? color.opacity(0.6) : .clear, radius: radius)
            .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}

extension View {
    func glow(color: Color, radius: CGFloat = 10, when isActive: Bool = true) -> some View {
        modifier(GlowModifier(color: color, radius: radius, isActive: isActive))
    }
}
