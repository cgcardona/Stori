//
//  ObjCExceptionBridge.swift
//  Stori
//
//  Swift-friendly wrapper around ObjCExceptionCatcher.
//  Converts Objective-C NSException into Swift Error so that
//  AVAudioEngine / AUAudioUnit operations that throw ObjC exceptions
//  can be handled gracefully instead of crashing the app.
//

import Foundation
import os.log

// MARK: - Error type

/// Error representing a caught Objective-C exception.
struct ObjCExceptionError: Error, LocalizedError {
    let underlyingError: NSError

    var errorDescription: String? {
        underlyingError.localizedDescription
    }
}

// MARK: - Bridge API

// Logger is Sendable — no nonisolated(unsafe) needed for module-scope let.
private let logger = Logger(subsystem: "com.tellurstori.stori", category: "ObjCBridge")

/// Executes `block` and catches any Objective-C `NSException`,
/// converting it into a Swift `ObjCExceptionError`.
///
/// Use this around AVAudioEngine / AUAudioUnit property accesses
/// that may throw `NSInternalInconsistencyException` instead of
/// returning a Swift `Error`.
///
/// - Parameter block: The closure to execute.
/// - Throws: `ObjCExceptionError` if an Objective-C exception was thrown.
nonisolated func tryObjC(_ block: () -> Void) throws {
    var error: NSError?
    let success = ObjCExceptionCatcherTryBlock(block, &error)
    if !success {
        let wrapped = ObjCExceptionError(underlyingError: error ?? NSError(
            domain: "com.tellurstori.ObjCException",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown Objective-C exception"]
        ))
        logger.error("Caught ObjC exception: \(wrapped.localizedDescription)")
        throw wrapped
    }
}

/// Executes `block`, catches any Objective-C `NSException`, and returns
/// the result. If an exception occurs, returns `nil` and logs the error.
///
/// - Parameter block: The closure whose return value is needed.
/// - Returns: The value returned by `block`, or `nil` if an ObjC exception occurred.
nonisolated func tryObjCResult<T>(_ block: () -> T?) -> T? {
    var result: T?
    var error: NSError?
    let success = ObjCExceptionCatcherTryBlock({
        result = block()
    }, &error)
    if !success {
        let description = error?.localizedDescription ?? "Unknown Objective-C exception"
        logger.error("Caught ObjC exception (returning nil): \(description)")
        return nil
    }
    return result
}
