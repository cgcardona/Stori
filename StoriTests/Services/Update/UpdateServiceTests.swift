//
//  UpdateServiceTests.swift
//  StoriTests
//
//  Tests for UpdateService: state machine transitions, GitHub API handling,
//  ETag caching, version comparison, asset selection, security validation,
//  and network error handling using mock URLProtocol.
//

import XCTest
@testable import Stori

// MARK: - MockURLProtocol

/// A mock URL protocol for intercepting network requests in tests
final class MockURLProtocol: URLProtocol {
    
    /// Handler called for each request; returns (data, response, error)
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    
    /// Track all requests made
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    
    override func startLoading() {
        Self.capturedRequests.append(request)
        
        guard let handler = Self.requestHandler else {
            let error = NSError(domain: "MockURLProtocol", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No request handler set"
            ])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
    
    static func reset() {
        requestHandler = nil
        capturedRequests = []
    }
}

// MARK: - Test Helpers

private func makeGitHubReleaseJSON(
    tagName: String = "v0.2.3",
    name: String = "Stori v0.2.3",
    body: String = "Bug fixes and improvements",
    prerelease: Bool = false,
    draft: Bool = false,
    assetName: String = "Stori-v0.2.3.dmg",
    assetSize: Int64 = 50_000_000,
    publishedAt: String = "2026-01-15T12:00:00Z"
) -> Data {
    let json = """
    {
        "tag_name": "\(tagName)",
        "name": "\(name)",
        "body": "\(body)",
        "published_at": "\(publishedAt)",
        "html_url": "https://github.com/cgcardona/Stori/releases/tag/\(tagName)",
        "prerelease": \(prerelease),
        "draft": \(draft),
        "assets": [
            {
                "name": "\(assetName)",
                "browser_download_url": "https://github.com/cgcardona/Stori/releases/download/\(tagName)/\(assetName)",
                "size": \(assetSize),
                "content_type": "application/x-apple-diskimage"
            }
        ]
    }
    """
    return json.data(using: .utf8)!
}

private func makeHTTPResponse(url: URL, statusCode: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}

// MARK: - UpdateServiceTests

@MainActor
final class UpdateServiceTests: XCTestCase {
    
    private var service: UpdateService!
    private var store: UpdateStore!
    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var mockSession: URLSession!
    
    override func setUp() {
        super.setUp()
        
        MockURLProtocol.reset()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        
        suiteName = "com.stori.tests.updateService.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        store = UpdateStore(defaults: testDefaults)
        
        service = UpdateService(
            session: mockSession,
            store: store,
            currentVersion: SemanticVersion(major: 0, minor: 1, patch: 7),
            currentBuild: "42"
        )
    }
    
    override func tearDown() {
        MockURLProtocol.reset()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        store = nil
        service = nil
        mockSession = nil
        super.tearDown()
    }
    
    // MARK: - Initial State
    
    func testInitialState() {
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.currentVersion, SemanticVersion(major: 0, minor: 1, patch: 7))
        XCTAssertEqual(service.currentBuild, "42")
        XCTAssertFalse(service.hasUpdate)
        XCTAssertNil(service.availableRelease)
    }
    
    func testVersionDisplayString() {
        XCTAssertEqual(service.versionDisplayString, "v0.1.7 (42)")
    }
    
    // MARK: - Update Available
    
    func testCheckFindsUpdateAvailable() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                return (
                    makeGitHubReleaseJSON(tagName: "v0.2.3"),
                    makeHTTPResponse(url: url, statusCode: 200, headers: ["ETag": "W/\"test123\""])
                )
            }
            // All releases endpoint (for counting releases behind)
            return (
                "[]".data(using: .utf8)!,
                makeHTTPResponse(url: url, statusCode: 200)
            )
        }
        
        await service.checkNow()
        
        if case .updateAvailable(let release) = service.state {
            XCTAssertEqual(release.version, SemanticVersion(major: 0, minor: 2, patch: 3))
            XCTAssertEqual(release.tagName, "v0.2.3")
            XCTAssertEqual(release.assetName, "Stori-v0.2.3.dmg")
            XCTAssertTrue(release.downloadURL.absoluteString.contains("github.com"))
        } else {
            XCTFail("Expected .updateAvailable, got \(service.state)")
        }
        
        XCTAssertTrue(service.hasUpdate)
    }
    
    // MARK: - Up To Date
    
    func testCheckFindsUpToDate() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            return (
                makeGitHubReleaseJSON(tagName: "v0.1.7"),
                makeHTTPResponse(url: url, statusCode: 200)
            )
        }
        
        await service.checkNow()
        XCTAssertEqual(service.state, .upToDate)
        XCTAssertFalse(service.hasUpdate)
    }
    
    // MARK: - Ahead of Release
    
    func testCheckFindsAheadOfRelease() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            return (
                makeGitHubReleaseJSON(tagName: "v0.1.5"),
                makeHTTPResponse(url: url, statusCode: 200)
            )
        }
        
        await service.checkNow()
        XCTAssertEqual(service.state, .aheadOfRelease)
    }
    
    // MARK: - ETag Caching
    
    func testETagIsCached() async {
        let testETag = "W/\"etag-test-value\""
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                return (
                    makeGitHubReleaseJSON(tagName: "v0.1.7"),
                    makeHTTPResponse(url: url, statusCode: 200, headers: ["ETag": testETag])
                )
            }
            return ("[]".data(using: .utf8)!, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        await service.checkNow()
        XCTAssertEqual(store.cachedETag, testETag)
    }
    
    func testETagSentOnSubsequentRequests() async {
        let testETag = "W/\"etag-cached\""
        store.cachedETag = testETag
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                // Verify ETag is sent
                let sentETag = request.value(forHTTPHeaderField: "If-None-Match")
                XCTAssertEqual(sentETag, testETag)
                
                return (
                    Data(),
                    makeHTTPResponse(url: url, statusCode: 304)
                )
            }
            return ("[]".data(using: .utf8)!, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        await service.checkNow()
    }
    
    func testNotModifiedUsesCachedData() async {
        // Pre-cache data
        store.cachedETag = "W/\"cached\""
        store.cachedReleaseJSON = makeGitHubReleaseJSON(tagName: "v0.2.3")
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                return (
                    Data(), // Empty body on 304
                    makeHTTPResponse(url: url, statusCode: 304)
                )
            }
            return ("[]".data(using: .utf8)!, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        await service.checkNow()
        
        // Should have found the update from cached data
        if case .updateAvailable(let release) = service.state {
            XCTAssertEqual(release.version, SemanticVersion(major: 0, minor: 2, patch: 3))
        } else {
            XCTFail("Expected .updateAvailable from cached data, got \(service.state)")
        }
    }
    
    // MARK: - Rate Limiting
    
    func testHandlesRateLimiting() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            return (
                Data(),
                makeHTTPResponse(url: url, statusCode: 429, headers: ["Retry-After": "60"])
            )
        }
        
        await service.checkNow()
        
        if case .error(let error) = service.state {
            if case .rateLimited = error {
                // Expected
            } else {
                XCTFail("Expected rateLimited error, got \(error)")
            }
        } else {
            XCTFail("Expected .error state, got \(service.state)")
        }
    }
    
    // MARK: - Prerelease Handling
    
    func testSkipsPrereleaseByDefault() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            return (
                makeGitHubReleaseJSON(tagName: "v0.2.0-beta.1", prerelease: true),
                makeHTTPResponse(url: url, statusCode: 200)
            )
        }
        
        await service.checkNow()
        XCTAssertEqual(service.state, .upToDate, "Should skip prereleases by default")
    }
    
    func testIncludesPrereleaseWhenOptedIn() async {
        store.betaOptIn = true
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                return (
                    makeGitHubReleaseJSON(tagName: "v0.2.0-beta.1", prerelease: true,
                                          assetName: "Stori-v0.2.0-beta.1.dmg"),
                    makeHTTPResponse(url: url, statusCode: 200)
                )
            }
            return ("[]".data(using: .utf8)!, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        await service.checkNow()
        
        if case .updateAvailable(let release) = service.state {
            XCTAssertTrue(release.version.isPrerelease)
        } else {
            XCTFail("Expected .updateAvailable for prerelease with opt-in")
        }
    }
    
    // MARK: - Draft Releases
    
    func testSkipsDraftReleases() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            return (
                makeGitHubReleaseJSON(tagName: "v0.2.3", draft: true),
                makeHTTPResponse(url: url, statusCode: 200)
            )
        }
        
        await service.checkNow()
        XCTAssertEqual(service.state, .upToDate)
    }
    
    // MARK: - No Assets
    
    func testNoCompatibleAsset() async {
        let json = """
        {
            "tag_name": "v0.2.3",
            "name": "Stori v0.2.3",
            "body": "Test",
            "published_at": "2026-01-15T12:00:00Z",
            "html_url": "https://github.com/cgcardona/Stori/releases/tag/v0.2.3",
            "prerelease": false,
            "draft": false,
            "assets": []
        }
        """.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            return (json, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        await service.checkNow()
        
        if case .error(let error) = service.state {
            XCTAssertEqual(error, .noCompatibleAsset)
        } else {
            XCTFail("Expected .error(.noCompatibleAsset)")
        }
    }
    
    // MARK: - Asset Selection
    
    func testPrefersDMGOverZip() async {
        let json = """
        {
            "tag_name": "v0.2.3",
            "name": "Stori v0.2.3",
            "body": "",
            "published_at": "2026-01-15T12:00:00Z",
            "html_url": "https://github.com/cgcardona/Stori/releases/tag/v0.2.3",
            "prerelease": false,
            "draft": false,
            "assets": [
                {
                    "name": "Stori-v0.2.3.zip",
                    "browser_download_url": "https://github.com/cgcardona/Stori/releases/download/v0.2.3/Stori-v0.2.3.zip",
                    "size": 40000000,
                    "content_type": "application/zip"
                },
                {
                    "name": "Stori-v0.2.3.dmg",
                    "browser_download_url": "https://github.com/cgcardona/Stori/releases/download/v0.2.3/Stori-v0.2.3.dmg",
                    "size": 50000000,
                    "content_type": "application/x-apple-diskimage"
                }
            ]
        }
        """.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                return (json, makeHTTPResponse(url: url, statusCode: 200))
            }
            return ("[]".data(using: .utf8)!, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        await service.checkNow()
        
        if case .updateAvailable(let release) = service.state {
            XCTAssertTrue(release.assetName.hasSuffix(".dmg"), "Should prefer DMG over ZIP")
        } else {
            XCTFail("Expected .updateAvailable")
        }
    }
    
    func testFallsBackToZip() async {
        let json = """
        {
            "tag_name": "v0.2.3",
            "name": "Stori v0.2.3",
            "body": "",
            "published_at": "2026-01-15T12:00:00Z",
            "html_url": "https://github.com/cgcardona/Stori/releases/tag/v0.2.3",
            "prerelease": false,
            "draft": false,
            "assets": [
                {
                    "name": "Stori-v0.2.3.zip",
                    "browser_download_url": "https://github.com/cgcardona/Stori/releases/download/v0.2.3/Stori-v0.2.3.zip",
                    "size": 40000000,
                    "content_type": "application/zip"
                }
            ]
        }
        """.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                return (json, makeHTTPResponse(url: url, statusCode: 200))
            }
            return ("[]".data(using: .utf8)!, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        await service.checkNow()
        
        if case .updateAvailable(let release) = service.state {
            XCTAssertTrue(release.assetName.hasSuffix(".zip"), "Should fall back to ZIP")
        } else {
            XCTFail("Expected .updateAvailable")
        }
    }
    
    // MARK: - Security
    
    func testAllowedDownloadHosts() {
        XCTAssertTrue(UpdateService.isAllowedDownloadHost("github.com"))
        XCTAssertTrue(UpdateService.isAllowedDownloadHost("objects.githubusercontent.com"))
        XCTAssertTrue(UpdateService.isAllowedDownloadHost("api.github.com"))
        
        XCTAssertFalse(UpdateService.isAllowedDownloadHost("evil.com"))
        XCTAssertFalse(UpdateService.isAllowedDownloadHost("github.com.evil.com"))
        XCTAssertFalse(UpdateService.isAllowedDownloadHost(nil))
        XCTAssertFalse(UpdateService.isAllowedDownloadHost(""))
    }
    
    func testSanitizeVersion() {
        XCTAssertEqual(UpdateService.sanitizeVersionForFilename("0.2.3"), "0.2.3")
        XCTAssertEqual(UpdateService.sanitizeVersionForFilename("0.2.3-beta.1"), "0.2.3-beta.1")
        
        // Path traversal prevention
        XCTAssertFalse(UpdateService.sanitizeVersionForFilename("../../../etc/passwd").contains(".."))
        XCTAssertFalse(UpdateService.sanitizeVersionForFilename("0.2.3/evil").contains("/"))
        XCTAssertFalse(UpdateService.sanitizeVersionForFilename("0.2.3\\evil").contains("\\"))
        
        // Null byte
        XCTAssertFalse(UpdateService.sanitizeVersionForFilename("0.2.3\0evil").contains("\0"))
        
        // Length limit
        let longVersion = String(repeating: "a", count: 200)
        XCTAssertLessThanOrEqual(UpdateService.sanitizeVersionForFilename(longVersion).count, 64)
        
        // Empty
        XCTAssertEqual(UpdateService.sanitizeVersionForFilename(""), "unknown")
    }
    
    // MARK: - Skip Version
    
    func testSkipVersion() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                return (
                    makeGitHubReleaseJSON(tagName: "v0.2.3"),
                    makeHTTPResponse(url: url, statusCode: 200)
                )
            }
            return ("[]".data(using: .utf8)!, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        // First check: finds update
        await service.checkNow()
        XCTAssertTrue(service.hasUpdate)
        
        // Skip this version
        if case .updateAvailable(let release) = service.state {
            service.skipVersion(release)
        }
        
        XCTAssertTrue(store.isVersionIgnored("0.2.3"))
        XCTAssertEqual(service.state, .upToDate)
    }
    
    // MARK: - Snooze
    
    func testSnoozeUpdate() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                return (
                    makeGitHubReleaseJSON(tagName: "v0.2.3"),
                    makeHTTPResponse(url: url, statusCode: 200)
                )
            }
            return ("[]".data(using: .utf8)!, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        await service.checkNow()
        
        if case .updateAvailable(let release) = service.state {
            service.snoozeUpdate(release)
        }
        
        XCTAssertFalse(service.showBanner, "Banner should be hidden after snooze")
        XCTAssertTrue(store.isSnoozed(for: "0.2.3"))
    }
    
    // MARK: - Urgency / Escalation
    
    func testUrgencyLevels() {
        XCTAssertEqual(UpdateUrgency.from(daysSinceFirstSeen: 0), .low)
        XCTAssertEqual(UpdateUrgency.from(daysSinceFirstSeen: 1), .low)
        XCTAssertEqual(UpdateUrgency.from(daysSinceFirstSeen: 3), .low)
        
        XCTAssertEqual(UpdateUrgency.from(daysSinceFirstSeen: 4), .medium)
        XCTAssertEqual(UpdateUrgency.from(daysSinceFirstSeen: 7), .medium)
        XCTAssertEqual(UpdateUrgency.from(daysSinceFirstSeen: 10), .medium)
        
        XCTAssertEqual(UpdateUrgency.from(daysSinceFirstSeen: 11), .high)
        XCTAssertEqual(UpdateUrgency.from(daysSinceFirstSeen: 30), .high)
        XCTAssertEqual(UpdateUrgency.from(daysSinceFirstSeen: 100), .high)
    }
    
    func testUrgencyComparable() {
        XCTAssertTrue(UpdateUrgency.low < UpdateUrgency.medium)
        XCTAssertTrue(UpdateUrgency.medium < UpdateUrgency.high)
        XCTAssertTrue(UpdateUrgency.low < UpdateUrgency.high)
    }
    
    // MARK: - Menu Item Title
    
    func testMenuItemTitleForIdleState() {
        XCTAssertEqual(service.menuItemTitle, "Check for Updates...")
    }
    
    func testMenuItemTitleForUpdateAvailable() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                return (
                    makeGitHubReleaseJSON(tagName: "v0.2.3"),
                    makeHTTPResponse(url: url, statusCode: 200)
                )
            }
            return ("[]".data(using: .utf8)!, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        await service.checkNow()
        XCTAssertEqual(service.menuItemTitle, "Update Available (v0.2.3)")
    }
    
    // MARK: - Network Errors
    
    func testHandles404() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            return (
                Data(),
                makeHTTPResponse(url: url, statusCode: 404)
            )
        }
        
        await service.checkNow()
        XCTAssertEqual(service.state, .upToDate, "404 means no releases exist yet")
    }
    
    func testHandlesServerError() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            return (
                Data(),
                makeHTTPResponse(url: url, statusCode: 500)
            )
        }
        
        await service.checkNow()
        
        if case .error(let error) = service.state {
            if case .serverError(let code) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected serverError")
            }
        } else {
            XCTFail("Expected .error state")
        }
    }
    
    // MARK: - UpdateError Properties
    
    func testUpdateErrorRetryable() {
        XCTAssertTrue(UpdateError.networkUnavailable.isRetryable)
        XCTAssertTrue(UpdateError.rateLimited(retryAfter: 60).isRetryable)
        XCTAssertTrue(UpdateError.serverError(statusCode: 500).isRetryable)
        
        XCTAssertFalse(UpdateError.noCompatibleAsset.isRetryable)
        XCTAssertFalse(UpdateError.downloadCancelled.isRetryable)
        XCTAssertFalse(UpdateError.checksumMismatch.isRetryable)
        XCTAssertFalse(UpdateError.untrustedSource("evil.com").isRetryable)
    }
    
    func testUpdateErrorEquality() {
        XCTAssertEqual(UpdateError.networkUnavailable, UpdateError.networkUnavailable)
        XCTAssertEqual(UpdateError.serverError(statusCode: 500), UpdateError.serverError(statusCode: 500))
        XCTAssertNotEqual(UpdateError.serverError(statusCode: 500), UpdateError.serverError(statusCode: 503))
    }
    
    func testUpdateErrorDescriptions() {
        // All errors should have non-empty descriptions
        let errors: [UpdateError] = [
            .networkUnavailable,
            .rateLimited(retryAfter: 60),
            .serverError(statusCode: 500),
            .noCompatibleAsset,
            .downloadFailed("test"),
            .downloadCancelled,
            .checksumMismatch,
            .invalidResponse,
            .untrustedSource("evil.com"),
            .fileSystemError("test")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) has empty description")
        }
    }
    
    // MARK: - State Machine
    
    func testStateTransitions() async {
        // idle -> checking -> updateAvailable
        XCTAssertEqual(service.state, .idle)
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.path.contains("/releases/latest") {
                return (
                    makeGitHubReleaseJSON(tagName: "v0.2.3"),
                    makeHTTPResponse(url: url, statusCode: 200)
                )
            }
            return ("[]".data(using: .utf8)!, makeHTTPResponse(url: url, statusCode: 200))
        }
        
        await service.checkNow()
        
        if case .updateAvailable = service.state {
            // Expected
        } else {
            XCTFail("Expected updateAvailable")
        }
    }
    
    // MARK: - DownloadProgress
    
    func testDownloadProgressComputation() {
        let progress = DownloadProgress(bytesDownloaded: 25_000_000, totalBytes: 50_000_000)
        
        XCTAssertEqual(progress.fraction, 0.5)
        XCTAssertEqual(progress.percent, 50)
        XCTAssertTrue(progress.formattedProgress.contains("/"))
    }
    
    func testDownloadProgressZeroTotal() {
        let progress = DownloadProgress(bytesDownloaded: 0, totalBytes: 0)
        XCTAssertEqual(progress.fraction, 0)
        XCTAssertEqual(progress.percent, 0)
    }
    
    // MARK: - Failure Tracking
    
    func testFailureTrackingOnErrors() async {
        MockURLProtocol.requestHandler = { request in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }
        
        await service.checkNow()
        XCTAssertEqual(store.consecutiveFailures, 1)
    }
    
    func testSuccessResetsFailures() async {
        store.recordFailure()
        store.recordFailure()
        XCTAssertEqual(store.consecutiveFailures, 2)
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            return (
                makeGitHubReleaseJSON(tagName: "v0.1.7"),
                makeHTTPResponse(url: url, statusCode: 200)
            )
        }
        
        await service.checkNow()
        XCTAssertEqual(store.consecutiveFailures, 0)
    }
    
    // MARK: - Last Check Date
    
    func testLastCheckDateUpdated() async {
        XCTAssertNil(store.lastCheckDate)
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            return (
                makeGitHubReleaseJSON(tagName: "v0.1.7"),
                makeHTTPResponse(url: url, statusCode: 200)
            )
        }
        
        await service.checkNow()
        XCTAssertNotNil(store.lastCheckDate)
    }
}
