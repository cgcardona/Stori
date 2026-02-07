//
//  TestHelpers+Memory.swift
//  StoriTests
//
//  Memory testing helpers for detecting retain cycles
//

import XCTest

/// Assert that an object deallocates properly (no retain cycles)
///
/// This catches two common bugs:
/// 1. Retain cycles (timer/task captures self strongly)
/// 2. Missing cleanup (deinit never runs)
///
/// USAGE:
/// ```swift
/// func testTransportControllerDeallocates() {
///     assertDeallocates {
///         let controller = TransportController(...)
///         controller.play()
///         controller.stop()
///         return controller
///     }
/// }
/// ```
///
/// If this test fails, common causes:
/// - Timer handler captures `self` instead of `[weak self]`
/// - Task captures `self` instead of `[weak self]`
/// - SwiftUI @Observable retain cycle
/// - Missing cleanup in deinit
func assertDeallocates<T: AnyObject>(
    _ make: () -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    weak var weakRef: T?
    
    autoreleasepool {
        let obj = make()
        weakRef = obj
        // obj goes out of scope here - should deallocate if no retain cycles
    }
    
    // Give autoreleasepool a moment to drain (async cleanup)
    Thread.sleep(forTimeInterval: 0.1)
    
    XCTAssertNil(
        weakRef,
        "Object should deallocate after going out of scope (possible retain cycle)",
        file: file,
        line: line
    )
}

/// Assert that an object deallocates after async work completes
///
/// Use for objects that have async cleanup (Tasks, actors, etc.)
///
/// USAGE:
/// ```swift
/// func testAsyncServiceDeallocates() async {
///     await assertDeallocatesAsync {
///         let service = AsyncService()
///         await service.start()
///         await service.stop()
///         return service
///     }
/// }
/// ```
func assertDeallocatesAsync<T: AnyObject>(
    _ make: () async -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    weak var weakRef: T?
    
    do {
        let obj = await make()
        weakRef = obj
        // obj goes out of scope here
    }
    
    // Give async cleanup time to complete
    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
    
    XCTAssertNil(
        weakRef,
        "Object should deallocate after going out of scope (possible retain cycle or Task leak)",
        file: file,
        line: line
    )
}
