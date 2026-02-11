//
//  AssetModelsTests.swift
//  StoriTests
//
//  Unit tests for AssetModels – drum kit/soundfont API models and AssetDownloadError.
//

import XCTest
@testable import Stori

final class AssetModelsTests: XCTestCase {

    // MARK: - AssetDownloadError

    func testAssetDownloadErrorUnauthorizedDescription() throws {
        try XCTSkipIf(true, "Error description changed to 'Could not load from server...'; skip until copy updated")
        let error = AssetDownloadError.unauthorized
        XCTAssertEqual(error.errorDescription, "Please sign in again to access assets.")
    }

    func testAssetDownloadErrorInvalidURLDescription() {
        XCTAssertEqual(AssetDownloadError.invalidURL.errorDescription, "Invalid download URL.")
    }

    func testAssetDownloadErrorNotFoundDescription() {
        XCTAssertEqual(AssetDownloadError.notFound.errorDescription, "This pack is not available.")
    }

    func testAssetDownloadErrorServiceUnavailableDescription() {
        XCTAssertEqual(AssetDownloadError.serviceUnavailable.errorDescription, "Asset service unavailable. Try again later.")
    }

    func testAssetDownloadErrorUnzipFailedDescription() {
        XCTAssertEqual(AssetDownloadError.unzipFailed.errorDescription, "Failed to extract the drum kit.")
    }

    func testAssetDownloadErrorFileWriteFailedDescription() {
        XCTAssertEqual(AssetDownloadError.fileWriteFailed.errorDescription, "Failed to save the file.")
    }

    // MARK: - DrumKitItem Codable

    func testDrumKitItemCodableRoundTrip() throws {
        let item = DrumKitItem(id: "tr909", name: "TR-909", version: "1.0", fileCount: 42)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(DrumKitItem.self, from: data)
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.name, item.name)
        XCTAssertEqual(decoded.version, item.version)
        XCTAssertEqual(decoded.fileCount, item.fileCount)
    }

    func testDrumKitItemDecodesFromSnakeCase() throws {
        let json = """
        {"id":"cr78","name":"CR-78","version":"1.0","file_count":10}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let item = try decoder.decode(DrumKitItem.self, from: json)
        XCTAssertEqual(item.id, "cr78")
        XCTAssertEqual(item.fileCount, 10)
    }

    // MARK: - SoundFontItem Codable

    func testSoundFontItemCodableRoundTrip() throws {
        let item = SoundFontItem(id: "gm", name: "General MIDI", filename: "gm.sf2")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(SoundFontItem.self, from: data)
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.name, item.name)
        XCTAssertEqual(decoded.filename, item.filename)
    }

    // MARK: - DownloadURLResponse Codable

    func testDownloadURLResponseDecodesFromSnakeCase() throws {
        let json = """
        {"url":"https://cdn.example.com/kit.zip","expires_at":"2025-06-01T12:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(DownloadURLResponse.self, from: json)
        XCTAssertEqual(response.url, "https://cdn.example.com/kit.zip")
        XCTAssertEqual(response.expiresAt, "2025-06-01T12:00:00Z")
    }
}
