// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation

/// Base class for MiniApp API modules that extend the runtime with additional capabilities.
///
/// Each module provides three integration points:
/// - `bridgeScript()`: JavaScript injected into the WebView to expose client-side APIs
/// - `registerInRuntime()`: Registers native-backed APIs in the runtime's JSContext
/// - `handleBridgeMessage()`: Handles messages sent from the WebView bridge to native
///
/// Subclass this to create custom modules (e.g., Bluetooth, NFC, SQL, Sensors).
/// Uses an open class hierarchy rather than a protocol for Skip Lite transpilation compatibility.
open class MiniAppModule {
    public init() {}

    /// JavaScript code to inject into the WebView bridge script.
    ///
    /// The script has access to:
    /// - `_api`: the namespace object (e.g., `window.skip`)
    /// - `sendMessage(action, data, callback)`: posts a message to the native bridge
    /// - `_ns`: the namespace name string
    open func bridgeScript() -> String {
        return ""
    }

    /// Register APIs in the runtime's JSContext for app.js and page.js execution.
    ///
    /// Called during runtime initialization. Use `runtime.registerModuleFunction()`
    /// and `runtime.evaluateModuleScript()` to add APIs without directly accessing JSContext.
    open func registerInRuntime(_ runtime: MiniAppRuntime) {
    }

    /// Handle a bridge message sent from the WebView.
    ///
    /// - Parameters:
    ///   - action: The message action name (e.g., "setStorageSync", "fetch").
    ///   - data: The message data dictionary.
    ///   - callId: The callback identifier for sending responses.
    ///   - runtime: The MiniApp runtime instance.
    ///   - respond: Closure to send a response back to the WebView: `(callId, success, jsonDict)`.
    /// - Returns: `true` if this module handled the message, `false` to pass to the next module.
    open func handleBridgeMessage(action: String, data: [String: Any], callId: Int, runtime: MiniAppRuntime, respond: @escaping (Int, Bool, [String: Any]) -> Void) -> Bool {
        return false
    }
}

/// A typed wrapper around a `MiniAppModule` that enables ergonomic static constants.
///
/// Modules can extend this struct to provide convenience constants:
/// ```swift
/// extension MiniAppModuleType {
///     public static let myModule = MiniAppModuleType(MyCustomModule())
/// }
/// ```
///
/// Then used in MiniAppHostView initialization:
/// ```swift
/// MiniAppHostView(directoryURL: url, modules: [.fileSystem, .network, .myModule])
/// ```
public struct MiniAppModuleType: Sendable {
    // SKIP NOWARN
    nonisolated(unsafe) public let module: MiniAppModule

    public init(_ module: MiniAppModule) {
        self.module = module
    }
}
#endif
