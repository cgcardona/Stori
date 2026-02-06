//
//  SemanticVersionTests.swift
//  StoriTests
//
//  Comprehensive tests for semantic version parsing, comparison, and distance.
//

import XCTest
@testable import Stori

final class SemanticVersionTests: XCTestCase {
    
    // MARK: - Parsing
    
    func testParseSimpleVersion() {
        let v = SemanticVersion.parse("0.2.3")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 0)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
        XCTAssertNil(v?.prerelease)
    }
    
    func testParseVersionWithVPrefix() {
        let v = SemanticVersion.parse("v0.2.3")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 0)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
    }
    
    func testParseVersionWithUpperVPrefix() {
        let v = SemanticVersion.parse("V1.0.0")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
    }
    
    func testParsePrereleaseVersion() {
        let v = SemanticVersion.parse("v0.2.3-beta.1")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 0)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
        XCTAssertEqual(v?.prerelease, "beta.1")
        XCTAssertTrue(v?.isPrerelease ?? false)
    }
    
    func testParseAlphaVersion() {
        let v = SemanticVersion.parse("1.0.0-alpha")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.prerelease, "alpha")
    }
    
    func testParseRCVersion() {
        let v = SemanticVersion.parse("1.0.0-rc.2")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.prerelease, "rc.2")
    }
    
    func testParseTwoComponentVersion() {
        let v = SemanticVersion.parse("1.0")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 0)
        XCTAssertEqual(v?.patch, 0)
    }
    
    func testParseWhitespaceTrimming() {
        let v = SemanticVersion.parse("  v1.2.3  ")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
    }
    
    func testParseInvalidVersionReturnsNil() {
        XCTAssertNil(SemanticVersion.parse(""))
        XCTAssertNil(SemanticVersion.parse("abc"))
        XCTAssertNil(SemanticVersion.parse("v"))
        XCTAssertNil(SemanticVersion.parse("1"))
        XCTAssertNil(SemanticVersion.parse("1.a.3"))
    }
    
    // MARK: - Comparison
    
    func testBasicComparison() {
        let v1 = SemanticVersion.parse("0.1.7")!
        let v2 = SemanticVersion.parse("0.2.3")!
        
        XCTAssertTrue(v1 < v2)
        XCTAssertFalse(v2 < v1)
    }
    
    func testPatchComparison() {
        let v1 = SemanticVersion.parse("0.2.3")!
        let v2 = SemanticVersion.parse("0.2.10")!
        
        XCTAssertTrue(v1 < v2, "0.2.3 should be less than 0.2.10 (numeric, not lexicographic)")
        XCTAssertFalse(v2 < v1)
    }
    
    func testMajorComparison() {
        let v1 = SemanticVersion.parse("0.9.9")!
        let v2 = SemanticVersion.parse("1.0.0")!
        
        XCTAssertTrue(v1 < v2)
    }
    
    func testEqualVersions() {
        let v1 = SemanticVersion.parse("1.2.3")!
        let v2 = SemanticVersion.parse("v1.2.3")!
        
        XCTAssertEqual(v1, v2)
        XCTAssertFalse(v1 < v2)
        XCTAssertFalse(v2 < v1)
    }
    
    func testPrereleaseIsLessThanRelease() {
        let pre = SemanticVersion.parse("1.0.0-beta.1")!
        let release = SemanticVersion.parse("1.0.0")!
        
        XCTAssertTrue(pre < release, "Prerelease should be less than release with same version")
        XCTAssertFalse(release < pre)
    }
    
    func testPrereleaseComparison() {
        let alpha = SemanticVersion.parse("1.0.0-alpha")!
        let beta = SemanticVersion.parse("1.0.0-beta")!
        
        XCTAssertTrue(alpha < beta, "alpha < beta alphabetically")
    }
    
    func testNumericPrereleaseComparison() {
        let beta1 = SemanticVersion.parse("1.0.0-beta.1")!
        let beta2 = SemanticVersion.parse("1.0.0-beta.2")!
        let beta10 = SemanticVersion.parse("1.0.0-beta.10")!
        
        XCTAssertTrue(beta1 < beta2)
        XCTAssertTrue(beta2 < beta10, "beta.2 < beta.10 (numeric, not lexicographic)")
    }
    
    func testPrereleaseAlphaBeforeRCBeforeBeta() {
        // SemVer: alpha < beta < rc (alphabetical)
        let alpha = SemanticVersion.parse("1.0.0-alpha")!
        let beta = SemanticVersion.parse("1.0.0-beta")!
        let rc = SemanticVersion.parse("1.0.0-rc")!
        
        XCTAssertTrue(alpha < beta)
        XCTAssertTrue(beta < rc)
        XCTAssertTrue(alpha < rc)
    }
    
    func testDifferentPrereleaseAgainstHigherVersion() {
        let pre = SemanticVersion.parse("0.9.0-beta.1")!
        let release = SemanticVersion.parse("1.0.0")!
        
        XCTAssertTrue(pre < release)
    }
    
    // MARK: - Properties
    
    func testIsPrerelease() {
        XCTAssertFalse(SemanticVersion.parse("1.0.0")!.isPrerelease)
        XCTAssertTrue(SemanticVersion.parse("1.0.0-beta")!.isPrerelease)
        XCTAssertTrue(SemanticVersion.parse("1.0.0-alpha.1")!.isPrerelease)
    }
    
    func testDisplayString() {
        let v = SemanticVersion.parse("0.2.3")!
        XCTAssertEqual(v.displayString, "v0.2.3")
        
        let pre = SemanticVersion.parse("1.0.0-beta.1")!
        XCTAssertEqual(pre.displayString, "v1.0.0-beta.1")
    }
    
    func testRawString() {
        let v = SemanticVersion.parse("v0.2.3")!
        XCTAssertEqual(v.raw, "0.2.3", "Raw should not include 'v' prefix")
    }
    
    // MARK: - Distance
    
    func testDistanceSameVersion() {
        let v = SemanticVersion.parse("1.0.0")!
        let d = v.distance(to: v)
        XCTAssertEqual(d.majorDelta, 0)
        XCTAssertEqual(d.minorDelta, 0)
        XCTAssertEqual(d.patchDelta, 0)
        XCTAssertEqual(d.summary, "up to date")
    }
    
    func testDistancePatchBehind() {
        let v1 = SemanticVersion.parse("0.2.1")!
        let v2 = SemanticVersion.parse("0.2.3")!
        let d = v1.distance(to: v2)
        XCTAssertEqual(d.patchDelta, 2)
        XCTAssertFalse(d.isMajorBehind)
        XCTAssertFalse(d.isMinorBehind)
        XCTAssertTrue(d.summary.contains("2 patches behind"))
    }
    
    func testDistanceMinorBehind() {
        let v1 = SemanticVersion.parse("0.1.7")!
        let v2 = SemanticVersion.parse("0.3.0")!
        let d = v1.distance(to: v2)
        XCTAssertEqual(d.minorDelta, 2)
        XCTAssertTrue(d.isMinorBehind)
        XCTAssertFalse(d.isMajorBehind)
    }
    
    func testDistanceMajorBehind() {
        let v1 = SemanticVersion.parse("0.9.0")!
        let v2 = SemanticVersion.parse("2.0.0")!
        let d = v1.distance(to: v2)
        XCTAssertEqual(d.majorDelta, 2)
        XCTAssertTrue(d.isMajorBehind)
        XCTAssertTrue(d.isMinorBehind)
    }
    
    // MARK: - Codable
    
    func testCodableRoundTrip() throws {
        let v = SemanticVersion.parse("1.2.3-beta.4")!
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(SemanticVersion.self, from: data)
        XCTAssertEqual(v, decoded)
    }
    
    func testCodableFromString() throws {
        let json = "\"v0.2.3\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SemanticVersion.self, from: data)
        XCTAssertEqual(decoded.major, 0)
        XCTAssertEqual(decoded.minor, 2)
        XCTAssertEqual(decoded.patch, 3)
    }
    
    func testCodableInvalidStringThrows() {
        let json = "\"not-a-version\""
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(SemanticVersion.self, from: data))
    }
    
    // MARK: - Edge Cases
    
    func testLargeVersionNumbers() {
        let v1 = SemanticVersion.parse("100.200.300")!
        let v2 = SemanticVersion.parse("100.200.301")!
        XCTAssertTrue(v1 < v2)
    }
    
    func testZeroVersion() {
        let v = SemanticVersion.parse("0.0.0")!
        XCTAssertEqual(v.major, 0)
        XCTAssertEqual(v.minor, 0)
        XCTAssertEqual(v.patch, 0)
    }
    
    // MARK: - Real-World Version Comparisons
    
    func testRealWorldStoriVersions() {
        // Simulate the actual Stori upgrade path
        let versions = [
            "v0.1.4-beta",
            "v0.1.5",
            "v0.1.6",
            "v0.1.7",
            "v0.2.0",
            "v0.2.1",
            "v0.2.3",
        ].compactMap { SemanticVersion.parse($0) }
        
        // Verify they're in ascending order
        for i in 0..<(versions.count - 1) {
            XCTAssertTrue(versions[i] < versions[i + 1],
                         "\(versions[i].raw) should be < \(versions[i + 1].raw)")
        }
    }
    
    func testUserOnV017LatestV023() {
        let current = SemanticVersion.parse("0.1.7")!
        let latest = SemanticVersion.parse("v0.2.3")!
        
        XCTAssertTrue(current < latest)
        
        let distance = current.distance(to: latest)
        XCTAssertTrue(distance.isMinorBehind)
    }
}
