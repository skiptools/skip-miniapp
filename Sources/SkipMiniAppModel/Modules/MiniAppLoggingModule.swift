// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import SkipScript

extension MiniAppModuleType {
    /// Logging module with default configuration (no callback).
    public static let logging = MiniAppModuleType(MiniAppLoggingModule())

    /// Logging module with a host callback for each log entry.
    public static func logging(onLog: @escaping (MiniAppLogEntry) -> Void) -> MiniAppModuleType {
        return MiniAppModuleType(MiniAppLoggingModule(onLog: onLog))
    }
}

/// MiniApp module providing `log()` in the Logic Layer with host-visible log browsing.
///
/// Log entries are appended to the runtime's `logEntries` array and optionally
/// forwarded to a host callback for real-time display.
/// Only available to app.js and page.js code (not the WebView).
public final class MiniAppLoggingModule: MiniAppModule {
    /// Optional callback invoked for each log entry.
    public let onLog: ((MiniAppLogEntry) -> Void)?

    public init(onLog: ((MiniAppLogEntry) -> Void)? = nil) {
        self.onLog = onLog
        super.init()
    }

    override public func registerInRuntime(_ runtime: MiniAppRuntime) {
        let context = runtime.jsContext
        guard let namespace = runtime.namespaceObject else { return }
        let logModule = self
        let logFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let helperFn = ctx.evaluateScript("""
            (function() {
                var parts = [];
                for (var i = 0; i < arguments.length; i++) {
                    var a = arguments[i];
                    parts.push(typeof a === 'object' ? JSON.stringify(a) : String(a));
                }
                return parts.join(' ');
            })
            """)
            let message = (try? helperFn?.call(withArguments: args))?.toString() ?? ""
            runtime.addLogEntry(level: "info", message: message)
            logModule.onLog?(runtime.logEntries[runtime.logEntries.count - 1])
            return JSValue(undefinedIn: ctx)
        }
        namespace.setObject(logFn, forKeyedSubscript: "log")
    }
}
#endif
