//
//  UserManagerTests.swift
//  StoriTests
//
//  Unit tests for UserManager – device/user ID and registration-related behavior.
//

import XCTest
@testable import Stori

@MainActor
final class UserManagerTests: XCTestCase {

    /// UUID string format: 8-4-4-4-12 hex (e.g. 550e8400-e29b-41d4-a716-446655440000)
    private static let uuidPattern = try! NSRegularExpression(
        pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    )

    private func isValidUUIDString(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..., in: s)
        return Self.uuidPattern.firstMatch(in: s, range: range) != nil
    }

    func testGetOrCreateUserIdReturnsValidUUIDFormat() async {
        let userId = UserManager.shared.getOrCreateUserId()
        XCTAssertTrue(isValidUUIDString(userId), "Expected UUID format, got: \(userId)")
    }

    func testGetOrCreateUserIdIsStableAcrossCalls() async {
        let first = UserManager.shared.getOrCreateUserId()
        let second = UserManager.shared.getOrCreateUserId()
        XCTAssertEqual(first, second, "Same install should return same device ID")
    }

    func testUserIdPropertyMatchesGetOrCreateUserId() async {
        let fromMethod = UserManager.shared.getOrCreateUserId()
        let fromProperty = UserManager.shared.userId
        XCTAssertEqual(fromProperty, fromMethod)
    }
}
