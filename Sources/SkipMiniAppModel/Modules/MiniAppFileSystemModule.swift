// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import SkipScript

extension MiniAppModuleType {
    /// File system / storage module with default in-memory storage.
    public static let fileSystem = MiniAppModuleType(MiniAppFileSystemModule())

    /// File system / storage module with custom storage mode.
    public static func fileSystem(storageMode: MiniAppStorageMode) -> MiniAppModuleType {
        return MiniAppModuleType(MiniAppFileSystemModule(storageMode: storageMode))
    }
}

/// MiniApp module providing sandboxed key-value storage APIs.
///
/// Exposes `getStorageSync`, `setStorageSync`, `removeStorageSync`, `getStorageKeys`,
/// and `clearStorage` on the namespace. Also blocks `window.localStorage` in the WebView
/// to prevent unsandboxed access.
public final class MiniAppFileSystemModule: MiniAppModule {
    /// The storage mode for this module instance.
    public let storageMode: MiniAppStorageMode

    public init(storageMode: MiniAppStorageMode = .inMemory) {
        self.storageMode = storageMode
        super.init()
    }

    override public func bridgeScript() -> String {
        // Note: the _store JSON is injected at runtime by the host view, which calls
        // storageJSON() to get the serialized state. This script references the _store
        // variable that the host view defines before this module's script runs.
        return """
            // --- Block localStorage to prevent unsandboxed access ---
            var _blockedStorageError = 'localStorage is not available in MiniApps. Use ' + _ns + '.getStorageSync() / ' + _ns + '.setStorageSync() instead.';
            try {
                Object.defineProperty(window, 'localStorage', {
                    get: function() { throw new Error(_blockedStorageError); },
                    configurable: false
                });
            } catch(e) {}

            // --- Synchronous storage backed by a local JS object ---
            _api.getStorageSync = function(key) {
                return _store.hasOwnProperty(key) ? _store[key] : undefined;
            };
            _api.setStorageSync = function(key, value) {
                var v = String(value);
                _store[key] = v;
                sendMessage('setStorageSync', { key: key, value: v });
            };
            _api.removeStorageSync = function(key) {
                delete _store[key];
                sendMessage('removeStorageSync', { key: key });
            };
            _api.getStorageKeys = function() {
                return Object.keys(_store);
            };
            _api.clearStorage = function() {
                _store = {};
                sendMessage('clearStorage', {});
            };
        """
    }

    override public func registerInRuntime(_ runtime: MiniAppRuntime) {
        let context = runtime.jsContext
        guard let namespace = runtime.namespaceObject else { return }
        let getStorageSyncFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let key = args.first?.toString() else { return JSValue(undefinedIn: ctx) }
            if let value = runtime.storage.get(key) {
                return JSValue(string: value, in: ctx)
            }
            return JSValue(undefinedIn: ctx)
        }
        namespace.setObject(getStorageSyncFn, forKeyedSubscript: "getStorageSync")

        let setStorageSyncFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard args.count >= 2 else { return JSValue(undefinedIn: ctx) }
            let key = args[0].toString() ?? ""
            let value = args[1].toString() ?? ""
            runtime.storage.set(key, value: value)
            return JSValue(undefinedIn: ctx)
        }
        namespace.setObject(setStorageSyncFn, forKeyedSubscript: "setStorageSync")

        let removeStorageSyncFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let key = args.first?.toString() else { return JSValue(undefinedIn: ctx) }
            runtime.storage.remove(key)
            return JSValue(undefinedIn: ctx)
        }
        namespace.setObject(removeStorageSyncFn, forKeyedSubscript: "removeStorageSync")

        let getStorageKeysFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let keys = runtime.storage.keys()
            let jsonKeys = keys.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
            let arrayLiteral = "[" + jsonKeys.joined(separator: ",") + "]"
            return ctx.evaluateScript(arrayLiteral) ?? JSValue(undefinedIn: ctx)
        }
        namespace.setObject(getStorageKeysFn, forKeyedSubscript: "getStorageKeys")

        let clearStorageFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            runtime.storage.clear()
            return JSValue(undefinedIn: ctx)
        }
        namespace.setObject(clearStorageFn, forKeyedSubscript: "clearStorage")
    }

    override public func handleBridgeMessage(action: String, data: [String: Any], callId: Int, runtime: MiniAppRuntime, respond: @escaping (Int, Bool, [String: Any]) -> Void) -> Bool {
        switch action {
        case "setStorageSync":
            if let key = data["key"] as? String, let value = data["value"] as? String {
                runtime.storage.set(key, value: value)
            }
            return true
        case "removeStorageSync":
            if let key = data["key"] as? String {
                runtime.storage.remove(key)
            }
            return true
        case "clearStorage":
            runtime.storage.clear()
            return true
        default:
            return false
        }
    }

    /// Serialize the current storage state as a JSON string for injection into the bridge script.
    public func storageJSON(for runtime: MiniAppRuntime) -> String {
        var dict: [String: String] = [:]
        for key in runtime.storage.keys() {
            if let value = runtime.storage.get(key) {
                dict[key] = value
            }
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
           let json = String(data: jsonData, encoding: .utf8) {
            return json
        }
        return "{}"
    }
}
#endif
