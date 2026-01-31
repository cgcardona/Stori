//
//  StoriTests.swift
//  StoriTests
//
//  Professional test suite for Stori
//  Provides comprehensive unit and integration testing for the DAW
//

import XCTest
@testable import Stori

/// Main test bundle entry point
/// Individual test classes are organized by module:
/// - Models/ - Data model tests
/// - Services/ - Business logic tests
/// - Audio/ - Audio engine tests
/// - Integration/ - Cross-component tests
final class StoriTests: XCTestCase {
    
    /// Verify test bundle is properly configured
    func testBundleConfiguration() {
        // Verify we can access the main bundle
        let bundle = Bundle(for: type(of: self))
        XCTAssertNotNil(bundle.bundleIdentifier)
    }
    
    /// Verify @testable import works
    func testModuleAccess() {
        // Basic smoke test - can we instantiate core types?
        let project = AudioProject(name: "Test Project")
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.tempo, 120.0)
    }
}
