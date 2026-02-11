//
//  AssetDownloadServiceTests.swift
//  StoriTests
//
//  Unit tests for AssetDownloadService – asset requests use X-Device-ID and no JWT.
//

import XCTest
@testable import Stori

// MARK: - Thread-safe request capture (no nonisolated(unsafe))

/// Holds the last URLRequest seen by the protocol. Lock-protected so URLSession and test can access safely.
private final class RequestCaptureHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: URLRequest?

    func get() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ request: URLRequest?) {
        lock.lock()
        defer { lock.unlock() }
        value = request
    }
}

// MARK: - Request-capturing URLProtocol

private final class CaptureRequestProtocol: URLProtocol {
    private static let capture = RequestCaptureHolder()
    static var lastRequest: URLRequest? {
        get { capture.get() }
        set { capture.set(newValue) }
    }
    static let testHost = "asset-test.example.com"

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == testHost
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capture.set(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = Self.responseBody(for: request.url)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func responseBody(for url: URL?) -> Data {
        guard let path = url?.path else { return "[]".data(using: .utf8)! }
        if path.contains("/download-url") {
            return #"{"url":"https://test.example.com/asset.zip","expires_at":"2026-12-31T00:00:00Z"}"#.data(using: .utf8)!
        }
        return "[]".data(using: .utf8)!
    }

    override func stopLoading() {}
}

// MARK: - Tests

@MainActor
final class AssetDownloadServiceTests: XCTestCase {

    private let testBaseURL = "https://asset-test.example.com"
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        CaptureRequestProtocol.lastRequest = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CaptureRequestProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        session = nil
        CaptureRequestProtocol.lastRequest = nil
        super.tearDown()
    }

    /// Asset endpoints must send X-Device-ID (device UUID) and must NOT send Authorization (no JWT).
    func testListDrumKitsSendsDeviceIdAndNoAuthorization() async throws {
        let service = AssetDownloadService(baseURL: testBaseURL, session: session)
        _ = try await service.listDrumKits()
        try assertLastRequestHasDeviceIdAndNoAuth()
    }

    func testListDrumKitsRequestURL() async throws {
        let service = AssetDownloadService(baseURL: testBaseURL, session: session)
        _ = try await service.listDrumKits()

        let request = try XCTUnwrap(CaptureRequestProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/assets/drum-kits")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testListSoundfontsSendsDeviceIdAndNoAuthorization() async throws {
        let service = AssetDownloadService(baseURL: testBaseURL, session: session)
        _ = try await service.listSoundfonts()
        try assertLastRequestHasDeviceIdAndNoAuth()
        let request = try XCTUnwrap(CaptureRequestProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/assets/soundfonts")
    }

    func testGetDrumKitDownloadURLSendsDeviceIdAndNoAuthorization() async throws {
        let service = AssetDownloadService(baseURL: testBaseURL, session: session)
        _ = try await service.getDrumKitDownloadURL(kitId: "cr78")
        try assertLastRequestHasDeviceIdAndNoAuth()
        let request = try XCTUnwrap(CaptureRequestProtocol.lastRequest)
        XCTAssertTrue(request.url?.path.contains("/drum-kits/cr78/download-url") == true)
    }

    func testGetSoundFontDownloadURLSendsDeviceIdAndNoAuthorization() async throws {
        let service = AssetDownloadService(baseURL: testBaseURL, session: session)
        _ = try await service.getSoundFontDownloadURL(soundfontId: "gm")
        try assertLastRequestHasDeviceIdAndNoAuth()
        let request = try XCTUnwrap(CaptureRequestProtocol.lastRequest)
        XCTAssertTrue(request.url?.path.contains("/soundfonts/gm/download-url") == true)
    }

    func testGetBundleDownloadURLSendsDeviceIdAndNoAuthorization() async throws {
        let service = AssetDownloadService(baseURL: testBaseURL, session: session)
        _ = try await service.getBundleDownloadURL()
        try assertLastRequestHasDeviceIdAndNoAuth()
        let request = try XCTUnwrap(CaptureRequestProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/assets/bundle/download-url")
    }

    private func assertLastRequestHasDeviceIdAndNoAuth() throws {
        let request = try XCTUnwrap(CaptureRequestProtocol.lastRequest)
        let deviceId = request.value(forHTTPHeaderField: "X-Device-ID")
        let auth = request.value(forHTTPHeaderField: "Authorization")
        XCTAssertNotNil(deviceId, "Asset requests must include X-Device-ID")
        XCTAssertFalse(deviceId?.isEmpty ?? true, "X-Device-ID must be non-empty")
        XCTAssertTrue(
            deviceId?.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil,
            "X-Device-ID should be UUID format, got: \(deviceId ?? "nil")"
        )
        XCTAssertNil(auth, "Asset requests must not send Authorization (no JWT for assets)")
    }
}
