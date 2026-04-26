// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import SkipScript
// SKIP NOWARN

extension MiniAppModuleType {
    /// File system / storage module with default in-memory storage.
    public static let fileSystem = MiniAppModuleType(MiniAppFileSystemModule())

    /// File system / storage module with custom storage mode.
    public static func fileSystem(storageMode: MiniAppStorageMode) -> MiniAppModuleType {
        return MiniAppModuleType(MiniAppFileSystemModule(storageMode: storageMode))
    }
}

/// MiniApp module providing sandboxed key-value storage APIs in the Logic Layer.
///
/// Exposes `getStorageSync`, `setStorageSync`, `removeStorageSync`, `getStorageKeys`,
/// and `clearStorage` on the JSContext namespace. These APIs are only available to
/// app.js and page.js code (the Logic Layer), not to the WebView (View Layer).
public final class MiniAppFileSystemModule: MiniAppModule {
    /// The storage mode for this module instance.
    public let storageMode: MiniAppStorageMode

    public init(storageMode: MiniAppStorageMode = .inMemory) {
        self.storageMode = storageMode
        super.init()
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
}
#endif
