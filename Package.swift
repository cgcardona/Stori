// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// NOTE: This Package.swift is for reference only.
// The actual dependencies are managed directly in the Xcode project.
// See project.pbxproj for the authoritative package references.

let package = Package(
    name: "Stori",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "StoriWallet",
            targets: ["StoriWallet"]
        ),
    ],
    dependencies: [
        // MARK: - Ethereum & Crypto (commented out for DAW-only; uncomment when Wallet/Blockchain goes live)
        // .package(url: "https://github.com/Boilertalk/Web3.swift", from: "0.8.0"),
        // .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.0"),
        // .package(url: "https://github.com/attaswift/BigInt", from: "5.3.0"),
        
        // MARK: - Secure Storage (commented out for DAW-only; uncomment when Wallet/Blockchain goes live)
        
        // KeychainAccess - Wrapper around iOS/macOS Keychain
        // Cleaner API than raw Security framework
        // .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
    ],
    targets: [
        .target(
            name: "StoriWallet",
            dependencies: [
                // .product(name: "Web3", package: "Web3.swift"),
                // "CryptoSwift",
                // "BigInt",
                // "KeychainAccess",
            ],
            path: "Stori/Core/Wallet"
        ),
    ]
)
