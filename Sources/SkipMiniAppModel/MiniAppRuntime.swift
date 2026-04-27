// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import OSLog
import Observation
import SkipScript

private let logger = Logger(subsystem: "SkipMiniApp", category: "Runtime")

/// A single log entry captured from `skip.log()` calls in a MiniApp.
public struct MiniAppLogEntry: Identifiable {
    public let id: Int
    public let timestamp: Date
    public let level: String
    public let message: String

    public init(id: Int, timestamp: Date = Date(), level: String = "info", message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

/// Holds lifecycle callbacks, custom event handlers, and the data object for one page.
/// Internal — JSValue is not a bridgeable type.
class PageCallbackSet {
    var onLoad: JSValue?
    var onShow: JSValue?
    var onReady: JSValue?
    var onHide: JSValue?
    var onUnload: JSValue?

    /// The page's data object in the JSContext (this.data).
    var data: JSValue?

    /// The full Page config object, used for calling custom handlers via `this.handlerName()`.
    var pageInstance: JSValue?

    /// Names of custom event handlers defined on this page.
    var handlerNames: [String] = []

    init() {}
}

/// Navigation command issued by JavaScript via miniapp.navigateTo/navigateBack.
public struct MiniAppNavigationCommand: Equatable {
    public var action: MiniAppNavigationAction
    public var pagePath: String
    public var query: String

    public init(action: MiniAppNavigationAction, pagePath: String = "", query: String = "") {
        self.action = action
        self.pagePath = pagePath
        self.query = query
    }
}

/// The type of navigation action.
public enum MiniAppNavigationAction: String, Equatable {
    case push
    case pop
}

/// Core runtime managing a JSContext for MiniApp app.js logic, lifecycle callbacks,
/// native bridge functions, and page stack navigation.
@Observable public class MiniAppRuntime {
    /// The MiniApp package reader this runtime was created for.
    public let package: MiniAppPackageReader

    /// The manifest for this MiniApp.
    public let manifest: MiniAppManifest

    /// Lifecycle manager for global app state.
    public let lifecycle: MiniAppLifecycle

    /// Pending navigation command set by JS, observed by the view layer.
    public var pendingNavigation: MiniAppNavigationCommand?

    /// Pending data update from setData(), observed by the view layer.
    /// Contains the JSON string of the full page data snapshot to push to the view.
    public var pendingDataUpdate: String?

    /// Per-page pending data updates keyed by page path.
    /// Used by the multi-page architecture where each page has its own WebView.
    public var pendingPageDataUpdates: [String: String] = [:]

    /// Current page stack (array of page paths).
    public var pageStack: [String] = []

    // MARK: - Internal State (not exposed publicly to avoid bridging JSValue)

    /// The JavaScript execution context for this MiniApp instance.
    let context: JSContext

    /// App-level lifecycle callbacks captured from App({...}) call.
    private var appOnLaunch: JSValue?
    private var appOnShow: JSValue?
    private var appOnHide: JSValue?
    private var appOnError: JSValue?

    /// Per-page lifecycle callbacks keyed by page path.
    private var pageCallbacks: [String: PageCallbackSet] = [:]

    /// The page path set before evaluating a page's JS so Page({...}) knows which page to register for.
    private var currentPagePath: String = ""

    /// The JavaScript namespace name for the bridge API (e.g. "miniapp" or "skip").
    public let namespace: String

    /// OPFS-style sandboxed file system for this MiniApp. Set by the FileSystemModule.
    public var fileSystem: MiniAppFileSystem?

    /// I18n module reference for the view layer to access translations. Set by MiniAppI18nModule.
    public var i18nModule: MiniAppI18nModule?

    /// Navigation module reference for tab/stack management. Set by MiniAppNavigationModule.
    public var navigationModule: MiniAppNavigationModule?

    /// Log entries captured from `skip.log()` calls, available for host UI.
    public var logEntries: [MiniAppLogEntry] = []

    /// Counter for generating unique log entry IDs.
    private var nextLogId: Int = 1

    /// Timer tracking for setTimeout/setInterval.
    private var nextTimerId: Int = 1
    private var activeTimers: Set<Int> = []
    private var intervalCallbacks: [Int: JSValue] = [:]

    /// Page lifecycle managers keyed by page path.
    private var pageLifecycles: [String: MiniAppPageLifecycle] = [:]

    // MARK: - Initialization

    /// The modules registered with this runtime.
    public let modules: [MiniAppModuleType]

    /// Creates a new MiniAppRuntime with a JSContext and registers all global bridge functions.
    ///
    /// - Parameters:
    ///   - package: Source for reading app.js and page JS files.
    ///   - manifest: The parsed MiniApp manifest.
    ///   - namespace: The JavaScript global name for the bridge API. Defaults to `"miniapp"`.
    ///   - modules: API modules to register. Each module provides JS bridge code, JSContext APIs, and message handlers.
    public init(package: MiniAppPackageReader, manifest: MiniAppManifest, namespace: String = "miniapp", modules: [MiniAppModuleType]? = nil) {
        self.package = package
        self.manifest = manifest
        self.namespace = namespace
        self.modules = modules ?? [MiniAppModuleType(MiniAppFileSystemModule()), MiniAppModuleType(MiniAppNetworkModule()), MiniAppModuleType(MiniAppLoggingModule())]
        self.context = JSContext()
        self.lifecycle = MiniAppLifecycle()

        registerGlobals()
    }

    /// Append a log entry to the runtime's log.
    public func addLogEntry(level: String = "info", message: String) {
        let entry = MiniAppLogEntry(id: nextLogId, level: level, message: message)
        nextLogId += 1
        logEntries.append(entry)
    }

    /// Update a single key in the current page's data without triggering a view push.
    /// Used for x-model two-way binding where the view already has the updated value.
    public func updatePageData(key: String, value: String) {
        guard let pagePath = currentPage,
              let callbacks = pageCallbacks[pagePath],
              let pageInstance = callbacks.pageInstance else { return }
        let safeKey = key.replacingOccurrences(of: "'", with: "\\'")
        let safeValue = value.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: "\\n")
        context.setObject(pageInstance, forKeyedSubscript: "__currentPage")
        context.evaluateScript("__currentPage.data['\(safeKey)'] = '\(safeValue)'")
    }

    /// Get the custom event handler names for the current page.
    /// These are methods on the Page config that aren't lifecycle callbacks or data/setData.
    public func pageHandlerNames() -> [String] {
        guard let pagePath = currentPage,
              let callbacks = pageCallbacks[pagePath],
              let pageInstance = callbacks.pageInstance else { return [] }

        // Enumerate keys on the page instance and filter to custom handler functions
        let skipList = "['data','setData','onLoad','onShow','onReady','onHide','onUnload']"
        context.setObject(pageInstance, forKeyedSubscript: "__tmpPage")
        guard let result = context.evaluateScript("""
        (function() {
            var keys = Object.keys(__tmpPage);
            var skipSet = \(skipList);
            var handlers = [];
            for (var i = 0; i < keys.length; i++) {
                if (skipSet.indexOf(keys[i]) === -1 && typeof __tmpPage[keys[i]] === 'function') {
                    handlers.push(keys[i]);
                }
            }
            return JSON.stringify(handlers);
        })()
        """) else { return [] }

        let jsonString = result.toString() ?? "[]"
        guard let jsonData = jsonString.data(using: .utf8),
              let names = try? JSONSerialization.jsonObject(with: jsonData) as? [String] else { return [] }
        return names
    }

    /// Get the initial data JSON for the current page (for the view layer's first render).
    public func initialDataJSON() -> String {
        guard let pagePath = currentPage,
              let callbacks = pageCallbacks[pagePath],
              let data = callbacks.data else { return "{}" }
        if let stringify = context.evaluateScript("JSON.stringify"),
           let result = try? stringify.call(withArguments: [data]) {
            return result.toString() ?? "{}"
        }
        return "{}"
    }

    /// Get the initial data JSON for a specific page path.
    public func initialDataJSON(forPage pagePath: String) -> String {
        guard let callbacks = pageCallbacks[pagePath],
              let data = callbacks.data else { return "{}" }
        if let stringify = context.evaluateScript("JSON.stringify"),
           let result = try? stringify.call(withArguments: [data]) {
            return result.toString() ?? "{}"
        }
        return "{}"
    }

    /// Get the custom event handler names for a specific page path.
    public func pageHandlerNames(forPage pagePath: String) -> [String] {
        guard let callbacks = pageCallbacks[pagePath],
              let pageInstance = callbacks.pageInstance else { return [] }

        let skipList = "['data','setData','onLoad','onShow','onReady','onHide','onUnload']"
        context.setObject(pageInstance, forKeyedSubscript: "__tmpPage")
        guard let result = context.evaluateScript("""
        (function() {
            var keys = Object.keys(__tmpPage);
            var skipSet = \(skipList);
            var handlers = [];
            for (var i = 0; i < keys.length; i++) {
                if (skipSet.indexOf(keys[i]) === -1 && typeof __tmpPage[keys[i]] === 'function') {
                    handlers.push(keys[i]);
                }
            }
            return JSON.stringify(handlers);
        })()
        """) else { return [] }

        let jsonString = result.toString() ?? "[]"
        guard let jsonData = jsonString.data(using: .utf8),
              let names = try? JSONSerialization.jsonObject(with: jsonData) as? [String] else { return [] }
        return names
    }

    /// Dispatch a view-layer event to a specific page's handler in the logic layer.
    public func dispatchEvent(handlerName: String, eventJSON: String, forPage pagePath: String) {
        guard let callbacks = pageCallbacks[pagePath],
              let pageInstance = callbacks.pageInstance else { return }

        let safeHandler = handlerName.replacingOccurrences(of: "'", with: "\\'")
        context.setObject(pageInstance, forKeyedSubscript: "__currentPage")
        let handler = context.evaluateScript("__currentPage['\(safeHandler)']")
        if let handler = handler, handler.isFunction {
            callOnPageInstance(handler, pagePath: pagePath, argsJSON: eventJSON)
        }
    }

    /// Call a function on the current page instance with the correct `this` binding.
    ///
    /// JSValue's `call(withArguments:)` loses the `this` context, so lifecycle callbacks
    /// and event handlers would fail when accessing `this.data` or `this.setData()`.
    /// This helper invokes the function via JavaScript's `fn.call(page, ...)`.
    ///
    /// - Parameters:
    ///   - callback: The JSValue function to call.
    ///   - pagePath: The page whose instance provides the `this` context.
    ///   - argsJSON: Optional JSON string of the argument to pass (parsed in JS).
    private func callOnPageInstance(_ callback: JSValue, pagePath: String, argsJSON: String? = nil) {
        guard let callbacks = pageCallbacks[pagePath],
              let pageInstance = callbacks.pageInstance else { return }

        context.setObject(pageInstance, forKeyedSubscript: "__currentPage")
        context.setObject(callback, forKeyedSubscript: "__currentCallback")

        if let argsJSON = argsJSON {
            let safe = argsJSON.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            context.evaluateScript("__currentCallback.call(__currentPage, JSON.parse('\(safe)'))")
        } else {
            context.evaluateScript("__currentCallback.call(__currentPage)")
        }
    }

    /// Dispatch a view-layer event to the logic layer's page handler.
    public func dispatchEvent(handlerName: String, eventJSON: String) {
        guard let pagePath = currentPage,
              let callbacks = pageCallbacks[pagePath],
              let pageInstance = callbacks.pageInstance else { return }

        let safeHandler = handlerName.replacingOccurrences(of: "'", with: "\\'")
        context.setObject(pageInstance, forKeyedSubscript: "__currentPage")
        let handler = context.evaluateScript("__currentPage['\(safeHandler)']")
        if let handler = handler, handler.isFunction {
            callOnPageInstance(handler, pagePath: pagePath, argsJSON: eventJSON)
        }
    }

    // MARK: - Module Helpers

    /// The JSContext for module registration. Internal to the framework.
    var jsContext: JSContext { return context }

    /// The namespace JSValue for module function registration. Set during registerMiniAppNamespace().
    var namespaceObject: JSValue?

    // MARK: - Global Registration

    private func registerGlobals() {
        registerAppFunction()
        registerPageFunction()
        registerConsole()
        registerTimers()
        registerMiniAppNamespace()
    }

    /// Register the global App({...}) function that captures lifecycle callbacks.
    private func registerAppFunction() {
        let runtime = self
        let fn = JSValue(newFunctionIn: context) { ctx, obj, args in
            if let options = args.first, options.isObject {
                let onLaunch = options.objectForKeyedSubscript("onLaunch")
                if onLaunch.isFunction { runtime.appOnLaunch = onLaunch }
                let onShow = options.objectForKeyedSubscript("onShow")
                if onShow.isFunction { runtime.appOnShow = onShow }
                let onHide = options.objectForKeyedSubscript("onHide")
                if onHide.isFunction { runtime.appOnHide = onHide }
                let onError = options.objectForKeyedSubscript("onError")
                if onError.isFunction { runtime.appOnError = onError }
            }
            return JSValue(undefinedIn: ctx)
        }
        context.setObject(fn, forKeyedSubscript: "App")
    }

    /// Register the global Page({...}) function that captures per-page lifecycle callbacks,
    /// initial data, custom event handlers, and installs setData() on the page instance.
    private func registerPageFunction() {
        let runtime = self
        let fn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let options = args.first, options.isObject else {
                return JSValue(undefinedIn: ctx)
            }
            let callbacks = PageCallbackSet()

            // Capture lifecycle callbacks
            let onLoad = options.objectForKeyedSubscript("onLoad")
            if onLoad.isFunction { callbacks.onLoad = onLoad }
            let onShow = options.objectForKeyedSubscript("onShow")
            if onShow.isFunction { callbacks.onShow = onShow }
            let onReady = options.objectForKeyedSubscript("onReady")
            if onReady.isFunction { callbacks.onReady = onReady }
            let onHide = options.objectForKeyedSubscript("onHide")
            if onHide.isFunction { callbacks.onHide = onHide }
            let onUnload = options.objectForKeyedSubscript("onUnload")
            if onUnload.isFunction { callbacks.onUnload = onUnload }

            // Deep-copy the initial data object via JSON round-trip in JS
            let dataVal = options.objectForKeyedSubscript("data")
            if dataVal.isObject {
                // Store data temporarily so we can JSON-clone it safely
                ctx.setObject(dataVal, forKeyedSubscript: "__tmpData")
                let cloned = ctx.evaluateScript("JSON.parse(JSON.stringify(__tmpData))")
                _ = ctx.evaluateScript("delete __tmpData")
                callbacks.data = cloned
            } else {
                callbacks.data = ctx.evaluateScript("({})")
            }

            // Store the options object as the page instance (it holds custom handler methods)
            callbacks.pageInstance = options

            // Give the page instance access to its data
            if let pageData = callbacks.data as? JSValue {
                options.setObject(pageData, forKeyedSubscript: "data")
            }

            // Install setData() on the page instance
            let setDataFn = JSValue(newFunctionIn: ctx) { ctx2, thisObj, setDataArgs in
                guard let patch = setDataArgs.first, patch.isObject else {
                    return JSValue(undefinedIn: ctx2)
                }
                // Merge patch into this.data using path-based keys
                // Use a JS helper to handle dot paths like "items[0].name"
                let _ = try? ctx2.evaluateScript("""
                (function(target, patch) {
                    var keys = Object.keys(patch);
                    for (var i = 0; i < keys.length; i++) {
                        var key = keys[i];
                        var val = patch[key];
                        if (key.indexOf('.') === -1 && key.indexOf('[') === -1) {
                            target[key] = val;
                        } else {
                            var parts = key.replace(/\\[/g, '.').replace(/\\]/g, '').split('.');
                            var obj = target;
                            for (var j = 0; j < parts.length - 1; j++) {
                                if (obj[parts[j]] === undefined) obj[parts[j]] = {};
                                obj = obj[parts[j]];
                            }
                            obj[parts[parts.length - 1]] = val;
                        }
                    }
                })
                """)?.call(withArguments: [callbacks.data ?? JSValue(newObjectIn: ctx2), patch])

                // Serialize the full page data (not just the patch) so that multiple
                // setData() calls within one handler all contribute to the final state.
                // The last setData() wins, but since all patches merge into this.data first,
                // the full serialization contains everything.
                if let stringify = ctx2.evaluateScript("JSON.stringify"),
                   let fullData = callbacks.data,
                   let result = try? stringify.call(withArguments: [fullData]),
                   let jsonStr = result.toString() as String? {
                    runtime.pendingDataUpdate = jsonStr
                    // Also update the per-page map for multi-page architecture
                    let pagePath = runtime.currentPagePath
                    runtime.pendingPageDataUpdates[pagePath] = jsonStr
                }

                // Call the optional callback (second arg)
                if setDataArgs.count > 1 {
                    let cb = setDataArgs[1]
                    if cb.isFunction {
                        let _ = try? cb.call(withArguments: [])
                    }
                }
                return JSValue(undefinedIn: ctx2)
            }
            options.setObject(setDataFn, forKeyedSubscript: "setData")

            let pagePath = runtime.currentPagePath
            runtime.pageCallbacks[pagePath] = callbacks

            return JSValue(undefinedIn: ctx)
        }
        context.setObject(fn, forKeyedSubscript: "Page")
    }

    /// Register console.log/warn/error/info/debug that route to OSLog.
    private func registerConsole() {
        let consoleObj = JSValue(newObjectIn: context)

        let logFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let message = args.map { $0.toString() ?? "" }.joined(separator: " ")
            logger.log("\(message)")
            return JSValue(undefinedIn: ctx)
        }
        consoleObj.setObject(logFn, forKeyedSubscript: "log")

        let warnFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let message = args.map { $0.toString() ?? "" }.joined(separator: " ")
            logger.warning("\(message)")
            return JSValue(undefinedIn: ctx)
        }
        consoleObj.setObject(warnFn, forKeyedSubscript: "warn")

        let errorFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let message = args.map { $0.toString() ?? "" }.joined(separator: " ")
            logger.error("\(message)")
            return JSValue(undefinedIn: ctx)
        }
        consoleObj.setObject(errorFn, forKeyedSubscript: "error")

        let infoFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let message = args.map { $0.toString() ?? "" }.joined(separator: " ")
            logger.info("\(message)")
            return JSValue(undefinedIn: ctx)
        }
        consoleObj.setObject(infoFn, forKeyedSubscript: "info")

        let debugFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let message = args.map { $0.toString() ?? "" }.joined(separator: " ")
            logger.debug("\(message)")
            return JSValue(undefinedIn: ctx)
        }
        consoleObj.setObject(debugFn, forKeyedSubscript: "debug")

        context.setObject(consoleObj, forKeyedSubscript: "console")
    }

    /// Schedule the next tick of a setInterval timer.
    private func scheduleInterval(timerId: Int, intervalSeconds: Double) {
        nonisolated(unsafe) let unsafeSelf = self
        DispatchQueue.main.asyncAfter(deadline: .now() + intervalSeconds) {
            if unsafeSelf.activeTimers.contains(timerId), let cb = unsafeSelf.intervalCallbacks[timerId] {
                let _ = try? cb.call(withArguments: [])
                unsafeSelf.scheduleInterval(timerId: timerId, intervalSeconds: intervalSeconds)
            }
        }
    }

    /// Register setTimeout/clearTimeout/setInterval/clearInterval using DispatchQueue.
    private func registerTimers() {
        let runtime = self

        let setTimeoutFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let callback = args.first, callback.isFunction else {
                return JSValue(double: 0, in: ctx)
            }
            let delay = args.count > 1 ? args[1].toDouble() : 0.0
            let timerId = runtime.nextTimerId
            runtime.nextTimerId += 1
            runtime.activeTimers.insert(timerId)

            let delaySeconds = max(delay / 1000.0, 0.0)
            nonisolated(unsafe) let timerRuntime = runtime
            nonisolated(unsafe) let timerCallback = callback
            DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) {
                if timerRuntime.activeTimers.contains(timerId) {
                    timerRuntime.activeTimers.remove(timerId)
                    let _ = try? timerCallback.call(withArguments: [])
                }
            }

            return JSValue(double: Double(timerId), in: ctx)
        }
        context.setObject(setTimeoutFn, forKeyedSubscript: "setTimeout")

        let clearTimeoutFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            if let idVal = args.first {
                let d = idVal.toDouble()
                if !d.isNaN && !d.isInfinite {
                    runtime.activeTimers.remove(Int(d))
                }
            }
            return JSValue(undefinedIn: ctx)
        }
        context.setObject(clearTimeoutFn, forKeyedSubscript: "clearTimeout")

        let setIntervalFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let callback = args.first, callback.isFunction else {
                return JSValue(double: 0, in: ctx)
            }
            let interval = args.count > 1 ? args[1].toDouble() : 0.0
            let timerId = runtime.nextTimerId
            runtime.nextTimerId += 1
            runtime.activeTimers.insert(timerId)

            let intervalSeconds = max(interval / 1000.0, 0.001)
            runtime.intervalCallbacks[timerId] = callback
            runtime.scheduleInterval(timerId: timerId, intervalSeconds: intervalSeconds)

            return JSValue(double: Double(timerId), in: ctx)
        }
        context.setObject(setIntervalFn, forKeyedSubscript: "setInterval")

        let clearIntervalFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            if let idVal = args.first {
                let d = idVal.toDouble()
                if !d.isNaN && !d.isInfinite {
                    let timerId = Int(d)
                    runtime.activeTimers.remove(timerId)
                    runtime.intervalCallbacks.removeValue(forKey: timerId)
                }
            }
            return JSValue(undefinedIn: ctx)
        }
        context.setObject(clearIntervalFn, forKeyedSubscript: "clearInterval")
    }

    /// Register the bridge namespace with core APIs (getSystemInfo, navigation) and delegate to modules.
    private func registerMiniAppNamespace() {
        let miniapp = JSValue(newObjectIn: context)
        let runtime = self

        // --- Core: getSystemInfo() ---
        let getSystemInfoFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let info = JSValue(newObjectIn: ctx)
            #if SKIP
            info.setObject(JSValue(string: "android", in: ctx), forKeyedSubscript: "platform")
            #else
            info.setObject(JSValue(string: "ios", in: ctx), forKeyedSubscript: "platform")
            #endif
            info.setObject(JSValue(string: runtime.manifest.appId, in: ctx), forKeyedSubscript: "appId")
            info.setObject(JSValue(string: runtime.manifest.version.name, in: ctx), forKeyedSubscript: "version")
            return info
        }
        miniapp.setObject(getSystemInfoFn, forKeyedSubscript: "getSystemInfo")

        // --- Core: navigateTo / navigateBack ---
        let navigateToFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            if let options = args.first, options.isObject {
                let urlVal = options.objectForKeyedSubscript("url")
                let queryVal = options.objectForKeyedSubscript("query")
                let url = urlVal.isUndefined ? "" : (urlVal.toString() ?? "")
                let query = queryVal.isUndefined ? "" : (queryVal.toString() ?? "")
                runtime.pendingNavigation = MiniAppNavigationCommand(action: .push, pagePath: url, query: query)
            }
            return JSValue(undefinedIn: ctx)
        }
        miniapp.setObject(navigateToFn, forKeyedSubscript: "navigateTo")

        let navigateBackFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            if runtime.pageStack.count > 1 {
                runtime.pendingNavigation = MiniAppNavigationCommand(action: .pop)
            }
            return JSValue(undefinedIn: ctx)
        }
        miniapp.setObject(navigateBackFn, forKeyedSubscript: "navigateBack")

        // --- Register module APIs ---
        self.namespaceObject = miniapp
        for moduleType in modules {
            moduleType.module.registerInRuntime(self)
        }

        context.setObject(miniapp, forKeyedSubscript: namespace)
        if namespace != "miniapp" {
            context.setObject(miniapp, forKeyedSubscript: "miniapp")
        }
    }

    // MARK: - Public API

    /// Evaluate app.js, fire onLaunch, and set the initial page stack.
    public func start(launchPath: String? = nil, query: String = "") {
        // Evaluate app.js from the package
        if let appJSData = try? package.readAppJS(),
           let appJS = String(data: appJSData, encoding: .utf8) {
            let _ = context.evaluateScript(appJS)
            if let exception = context.exception {
                logger.error("Error evaluating app.js: \(exception.toString() ?? "unknown error")")
            }
        }

        // Fire onLaunch
        lifecycle.launch()
        if let onLaunch = appOnLaunch {
            let launchOptions = JSValue(newObjectIn: context)
            launchOptions.setObject(JSValue(string: launchPath ?? "", in: context), forKeyedSubscript: "path")
            launchOptions.setObject(JSValue(string: query, in: context), forKeyedSubscript: "query")
            let _ = try? onLaunch.call(withArguments: [launchOptions])
        }

        // Set initial page from launch path or first manifest page
        let initialPage = launchPath ?? manifest.pages.first ?? ""
        if !initialPage.isEmpty {
            pageStack = [initialPage]
        }
    }

    /// Fire the global app onShow callback and transition lifecycle state.
    public func fireAppShow() {
        lifecycle.show()
        if let onShow = appOnShow {
            let _ = try? onShow.call(withArguments: [])
        }
    }

    /// Fire the global app onHide callback and transition lifecycle state.
    public func fireAppHide() {
        lifecycle.hide()
        if let onHide = appOnHide {
            let _ = try? onHide.call(withArguments: [])
        }
    }

    /// Fire the global app onError callback with an error message.
    public func fireAppError(_ message: String) {
        lifecycle.fail(error: MiniAppError.resourceNotFound)
        if let onError = appOnError {
            let _ = try? onError.call(withArguments: [JSValue(string: message, in: context)])
        }
    }

    /// Evaluate a page's JavaScript and fire the page onLoad callback.
    public func loadPage(pagePath: String, query: String = "") {
        currentPagePath = pagePath

        // Create page lifecycle
        let pageLifecycle = MiniAppPageLifecycle()
        pageLifecycles[pagePath] = pageLifecycle

        // Evaluate page JS from the package
        if let pageJSData = try? package.readPageJS(pagePath: pagePath),
           let pageJS = String(data: pageJSData, encoding: .utf8) {
            let _ = context.evaluateScript(pageJS)
            if let exception = context.exception {
                logger.error("Error evaluating page JS for \(pagePath): \(exception.toString() ?? "unknown error")")
            }
        }

        // Fire onLoad with the page instance as `this`
        pageLifecycle.load()
        if let callbacks = pageCallbacks[pagePath], let onLoad = callbacks.onLoad {
            let argsJSON = "{\"query\":\"\(query.replacingOccurrences(of: "\"", with: "\\\""))\"}"
            callOnPageInstance(onLoad, pagePath: pagePath, argsJSON: argsJSON)
        }
    }

    /// Fire the page onReady callback (first render complete).
    public func firePageReady(pagePath: String) {
        pageLifecycles[pagePath]?.ready()
        if let callbacks = pageCallbacks[pagePath], let onReady = callbacks.onReady {
            callOnPageInstance(onReady, pagePath: pagePath)
        }
    }

    /// Fire the page onShow callback.
    public func firePageShow(pagePath: String) {
        pageLifecycles[pagePath]?.show()
        if let callbacks = pageCallbacks[pagePath], let onShow = callbacks.onShow {
            callOnPageInstance(onShow, pagePath: pagePath)
        }
    }

    /// Fire the page onHide callback.
    public func firePageHide(pagePath: String) {
        pageLifecycles[pagePath]?.hide()
        if let callbacks = pageCallbacks[pagePath], let onHide = callbacks.onHide {
            callOnPageInstance(onHide, pagePath: pagePath)
        }
    }

    /// Fire the page onUnload callback.
    public func firePageUnload(pagePath: String) {
        pageLifecycles[pagePath]?.unload()
        if let callbacks = pageCallbacks[pagePath], let onUnload = callbacks.onUnload {
            callOnPageInstance(onUnload, pagePath: pagePath)
        }
        pageCallbacks.removeValue(forKey: pagePath)
        pageLifecycles.removeValue(forKey: pagePath)
    }

    /// Process a pending navigation command: update the page stack and fire lifecycle events.
    public func processNavigation(_ command: MiniAppNavigationCommand) {
        switch command.action {
        case .push:
            // Hide current page
            if let currentPage = pageStack.last {
                firePageHide(pagePath: currentPage)
            }
            // Push new page
            pageStack.append(command.pagePath)
            loadPage(pagePath: command.pagePath, query: command.query)

        case .pop:
            guard pageStack.count > 1 else { return }
            // Unload current page
            if let currentPage = pageStack.last {
                firePageHide(pagePath: currentPage)
                firePageUnload(pagePath: currentPage)
            }
            pageStack.removeLast()
            // Show the page underneath
            if let previousPage = pageStack.last {
                firePageShow(pagePath: previousPage)
            }
        }
        pendingNavigation = nil
    }

    /// Evaluate arbitrary JavaScript in the runtime context and return the result as a string.
    /// Returns nil if evaluation fails or the result is undefined.
    @discardableResult
    public func evaluateScript(_ script: String) -> String? {
        let result = context.evaluateScript(script)
        if let exception = context.exception {
            logger.error("Script evaluation error: \(exception.toString() ?? "unknown error")")
            return nil
        }
        guard let result = result else { return nil }
        if result.isUndefined { return nil }
        return result.toString() ?? nil
    }

    /// Evaluate JavaScript and return the result as a double, or nil.
    public func evaluateScriptAsDouble(_ script: String) -> Double? {
        let result = context.evaluateScript(script)
        if context.exception != nil { return nil }
        guard let result = result else { return nil }
        if result.isUndefined || result.isNull { return nil }
        return result.toDouble()
    }

    /// Evaluate JavaScript and return the result as a boolean, or nil.
    public func evaluateScriptAsBool(_ script: String) -> Bool? {
        let result = context.evaluateScript(script)
        if context.exception != nil { return nil }
        guard let result = result else { return nil }
        if result.isUndefined || result.isNull { return nil }
        return result.toBool()
    }

    /// Evaluate JavaScript and return true if the result is undefined.
    public func evaluateScriptIsUndefined(_ script: String) -> Bool {
        let result = context.evaluateScript(script)
        if context.exception != nil { return true }
        guard let result = result else { return true }
        return result.isUndefined
    }

    /// Get the current page path (top of the page stack).
    public var currentPage: String? {
        return pageStack.last
    }

    /// Get the page lifecycle for a given page path.
    public func pageLifecycle(for pagePath: String) -> MiniAppPageLifecycle? {
        return pageLifecycles[pagePath]
    }
}
#endif
