//
//  DigitalMasterCard.swift
//  Stori
//
//  Created by TellUrStori on 12/9/25.
//

import SwiftUI

/// Card component displaying a Digital Master in the grid view
struct DigitalMasterCard: View {
    let master: DigitalMasterItem
    let onTap: () -> Void
    
    @State private var isHovered: Bool = false
    
    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: master.createdAt, relativeTo: Date())
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Cover image / placeholder
                coverImage
                
                // Content
                VStack(alignment: .leading, spacing: 12) {
                    // Title and token ID
                    VStack(alignment: .leading, spacing: 4) {
                        Text(master.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        
                        Text("Token ID: \(master.tokenId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                    
                    // Description
                    Text(master.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    // Stats row
                    HStack(spacing: 16) {
                        statItem(icon: "music.note.list", value: "\(master.stems.count)", label: "STEMs")
                        statItem(icon: "doc.on.doc", value: "\(master.licenseCount)", label: "Licenses")
                        
                        Spacer()
                        
                        // Revenue badge
                        if master.totalRevenue > 0 {
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", master.totalRevenue))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                Text("TUS")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.green, .teal],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                    }
                    
                    Divider()
                    
                    // Footer
                    HStack {
                        // Owners
                        HStack(spacing: -6) {
                            ForEach(master.owners.prefix(3)) { owner in
                                ownerAvatar(address: owner.address)
                            }
                            if master.owners.count > 3 {
                                Text("+\(master.owners.count - 3)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.gray))
                            }
                        }
                        
                        Spacer()
                        
                        // Date and royalty
                        HStack(spacing: 8) {
                            Text(formattedDate)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            Text("\(formatBasisPoints(master.royaltyPercentage)) royalty")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isHovered
                            ? LinearGradient(
                                colors: [.purple.opacity(0.5), .blue.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [Color.clear, Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              ),
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isHovered ? Color.purple.opacity(0.2) : Color.black.opacity(0.1),
                radius: isHovered ? 12 : 6,
                x: 0,
                y: isHovered ? 8 : 4
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    // MARK: - Cover Image
    
    /// Convert IPFS URI to HTTP gateway URL
    private func ipfsGatewayURL(for uri: String?) -> URL? {
        guard let uri = uri else { return nil }
        
        if uri.hasPrefix("ipfs://") {
            let cid = String(uri.dropFirst(7))
            return URL(string: "http://127.0.0.1:8080/ipfs/\(cid)")
        } else if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
            return URL(string: uri)
        }
        return nil
    }
    
    private var coverImage: some View {
        ZStack {
            // Try to load IPFS image, fallback to gradient
            if let imageURL = ipfsGatewayURL(for: master.imageURL?.absoluteString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        gradientPlaceholder
                    case .empty:
                        gradientPlaceholder
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            )
                    @unknown default:
                        gradientPlaceholder
                    }
                }
            } else {
                gradientPlaceholder
            }
            
            // Content overlay
            VStack {
                Spacer()
                
                HStack {
                    // License badge
                    if master.licenseCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                            Text("\(master.licenseCount) active")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 10))
                            Text("Create license")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                    }
                    
                    Spacer()
                }
                .padding(12)
            }
        }
        .frame(height: 140)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 12
            )
        )
    }
    
    private var gradientPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors(for: master.title),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Pattern overlay
            GeometryReader { geo in
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: CGFloat.random(in: 30...80))
                        .offset(
                            x: CGFloat(i) * geo.size.width / 4,
                            y: CGFloat.random(in: 0...geo.size.height)
                        )
                        .blur(radius: 20)
                }
            }
            
            // Music icon
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.white.opacity(0.3))
        }
    }
    
    // MARK: - Helper Views
    
    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 12, weight: .semibold))
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    private func ownerAvatar(address: String) -> some View {
        // Generate consistent color from address
        let color = colorFromAddress(address)
        
        return Circle()
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 24, height: 24)
            .overlay(
                Text(String(address.dropFirst(2).prefix(2)).uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            )
            .overlay(
                Circle()
                    .strokeBorder(Color(.controlBackgroundColor), lineWidth: 2)
            )
    }
    
    // MARK: - Helpers
    
    private func gradientColors(for title: String) -> [Color] {
        // Generate consistent gradient based on title
        let hash = abs(title.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 360) % 360) / 360.0
        
        return [
            Color(hue: hue1, saturation: 0.6, brightness: 0.7),
            Color(hue: hue2, saturation: 0.5, brightness: 0.5)
        ]
    }
    
    private func colorFromAddress(_ address: String) -> Color {
        let hash = abs(address.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.7)
    }
    
    /// Format basis points (10000 = 100%) to percentage string
    private func formatBasisPoints(_ basisPoints: Int) -> String {
        let percentage = Double(basisPoints) / 100.0
        if percentage == percentage.rounded() {
            return "\(Int(percentage))%"
        } else {
            return String(format: "%.1f%%", percentage)
        }
    }
}
