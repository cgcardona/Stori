//
//  StoriUITestCase.swift
//  StoriUITests
//
//  Base class for all Stori UI tests.
//  Provides launch helpers, screenshot capture, and common assertions.
//

import XCTest

/// Base class for all Stori XCUITests.
///
/// Every test class that drives the Stori UI should subclass this.
/// It handles:
/// - Launching the app with a clean environment
/// - Capturing screenshots on failure
/// - Common element-lookup helpers
/// - Timeout configuration
///
/// Usage:
/// ```swift
/// final class TransportTests: StoriUITestCase {
///     func testPlayButton() throws {
///         tap("transport_play")
///         assertExists("transport_play", timeout: 2)
///     }
/// }
/// ```
class StoriUITestCase: XCTestCase {

    // MARK: - Properties

    /// The shared app instance. Launched fresh for every test method.
    var app: XCUIApplication!

    /// Default timeout for element expectations (seconds).
    /// Override in subclasses for slower CI runners.
    var defaultTimeout: TimeInterval { 10 }

    // MARK: - Lifecycle

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        app = XCUIApplication()

        // Pass launch arguments so the app can detect it's in UI-test mode
        app.launchArguments += [
            "-UITestMode", "YES",
            "-ApplePersistenceIgnoreState", "YES"  // Don't restore windows
        ]

        // Environment hints (the app can read these via ProcessInfo)
        app.launchEnvironment["STORI_UI_TEST"] = "1"
        app.launchEnvironment["STORI_SKIP_ONBOARDING"] = "1"

        app.launch()
        
        // In UI test mode, the app auto-creates a project on launch.
        // Wait for the transport controls to appear, indicating the app is fully initialized.
        let transportPlay = app.buttons["transport_play"]
        _ = transportPlay.waitForExistence(timeout: 10)
    }

    override func tearDown() {
        // Capture a screenshot on failure so CI artifacts are useful
        if let failure = testRun?.failureCount, failure > 0 {
            captureScreenshot(name: "FAILURE-\(name)")
        }
        app.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - Screenshot Helpers

    /// Capture a screenshot and attach it to the test report.
    func captureScreenshot(name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Element Lookup Helpers

    /// Find any element by accessibility identifier, searching all element types.
    func element(_ identifier: String) -> XCUIElement {
        // XCUITest queries are type-specific; search common types in priority order
        let queries: [XCUIElementQuery] = [
            app.buttons,
            app.staticTexts,
            app.textFields,
            app.sliders,
            app.toggles,
            app.popUpButtons,
            app.menuButtons,
            app.images,
            app.groups,
            app.otherElements
        ]

        for query in queries {
            let el = query[identifier]
            if el.exists {
                return el
            }
        }

        // Fallback: return from otherElements so the caller gets a non-nil
        // element whose `.exists` is false — standard XCUITest pattern.
        return app.otherElements[identifier]
    }

    /// Shortcut: find a button by identifier.
    func button(_ identifier: String) -> XCUIElement {
        app.buttons[identifier]
    }

    /// Shortcut: find a slider by identifier.
    func slider(_ identifier: String) -> XCUIElement {
        app.sliders[identifier]
    }

    /// Shortcut: find a text field by identifier.
    func textField(_ identifier: String) -> XCUIElement {
        app.textFields[identifier]
    }

    /// Shortcut: find a static text by identifier.
    func staticText(_ identifier: String) -> XCUIElement {
        app.staticTexts[identifier]
    }

    // MARK: - Tap Helpers

    /// Tap an element identified by its accessibility ID.
    /// Waits for the element to become hittable before tapping.
    @discardableResult
    func tap(_ identifier: String, timeout: TimeInterval? = nil) -> XCUIElement {
        let el = element(identifier)
        let t = timeout ?? defaultTimeout
        let exists = el.waitForExistence(timeout: t)
        XCTAssertTrue(exists, "Element '\(identifier)' did not appear within \(t)s")
        // On macOS, elements may exist but not be hittable if obscured.
        // Use coordinate tap as fallback.
        if el.isHittable {
            el.click()
        } else {
            el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        return el
    }

    // MARK: - Assertion Helpers

    /// Assert that an element with the given identifier exists within `timeout`.
    func assertExists(_ identifier: String, timeout: TimeInterval? = nil, message: String? = nil) {
        let el = element(identifier)
        let t = timeout ?? defaultTimeout
        let msg = message ?? "Expected element '\(identifier)' to exist"
        XCTAssertTrue(el.waitForExistence(timeout: t), msg)
    }

    /// Assert that an element does NOT exist after a brief wait.
    func assertNotExists(_ identifier: String, timeout: TimeInterval = 2) {
        let el = element(identifier)
        // Give a short window for the element to potentially disappear
        if el.exists {
            // Wait and re-check
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: el
            )
            let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
            XCTAssertEqual(result, .completed, "Element '\(identifier)' should not exist")
        }
    }

    /// Assert that an element is enabled.
    func assertEnabled(_ identifier: String, timeout: TimeInterval? = nil) {
        let el = element(identifier)
        let t = timeout ?? defaultTimeout
        XCTAssertTrue(el.waitForExistence(timeout: t), "Element '\(identifier)' not found")
        XCTAssertTrue(el.isEnabled, "Element '\(identifier)' should be enabled")
    }

    /// Assert that an element is disabled.
    func assertDisabled(_ identifier: String, timeout: TimeInterval? = nil) {
        let el = element(identifier)
        let t = timeout ?? defaultTimeout
        XCTAssertTrue(el.waitForExistence(timeout: t), "Element '\(identifier)' not found")
        XCTAssertFalse(el.isEnabled, "Element '\(identifier)' should be disabled")
    }

    /// Assert the value of an element's accessibility value.
    func assertValue(_ identifier: String, equals expected: String, timeout: TimeInterval? = nil) {
        let el = element(identifier)
        let t = timeout ?? defaultTimeout
        XCTAssertTrue(el.waitForExistence(timeout: t), "Element '\(identifier)' not found")
        XCTAssertEqual(el.value as? String, expected,
                       "Element '\(identifier)' value mismatch")
    }

    // MARK: - Wait Helpers

    /// Wait for an element to appear using XCTNSPredicateExpectation (no flaky sleeps).
    @discardableResult
    func waitForElement(_ identifier: String, timeout: TimeInterval? = nil) -> XCUIElement {
        let el = element(identifier)
        let t = timeout ?? defaultTimeout
        let predicate = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: el)
        let result = XCTWaiter.wait(for: [expectation], timeout: t)
        XCTAssertEqual(result, .completed, "Timed out waiting for '\(identifier)'")
        return el
    }

    /// Wait for a condition to become true, polling at intervals.
    func waitFor(
        _ description: String,
        timeout: TimeInterval? = nil,
        pollInterval: TimeInterval = 0.5,
        condition: () -> Bool
    ) {
        let t = timeout ?? defaultTimeout
        let deadline = Date().addingTimeInterval(t)
        while !condition() {
            XCTAssertTrue(Date() < deadline, "Timed out waiting for: \(description)")
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    // MARK: - Menu Helpers (macOS)

    /// Click a menu item via the app's menu bar.
    func clickMenuItem(_ menuName: String, item: String) {
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems[menuName].click()
        menuBar.menuItems[item].click()
    }

    /// Click a menu item with a submenu path.
    func clickMenuItem(_ menuName: String, items: String...) {
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems[menuName].click()
        for (index, item) in items.enumerated() {
            if index < items.count - 1 {
                menuBar.menuItems[item].hover()
            } else {
                menuBar.menuItems[item].click()
            }
        }
    }

    // MARK: - Keyboard Helpers

    /// Type a keyboard shortcut.
    func typeShortcut(_ key: String, modifiers: XCUIElement.KeyModifierFlags = []) {
        app.typeKey(key, modifierFlags: modifiers)
    }

    /// Type a special keyboard key (delete, return, escape, etc).
    func typeKey(_ key: XCUIKeyboardKey) {
        app.typeKey(key.rawValue, modifierFlags: [])
    }
}

// MARK: - XCUIKeyboardKey Extension

/// Keyboard key constants for typeKey() method.
extension XCUIKeyboardKey {
    static let delete = XCUIKeyboardKey.delete
    static let deleteForward = XCUIKeyboardKey(rawValue: "\u{F728}")
    static let escape = XCUIKeyboardKey(rawValue: "\u{001B}")
    static let `return` = XCUIKeyboardKey(rawValue: "\r")
    static let tab = XCUIKeyboardKey(rawValue: "\t")
}
