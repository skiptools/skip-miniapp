// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

#if !SKIP_BRIDGE
import Foundation
import OSLog
import Observation
import SkipScript

private let logger = Logger(subsystem: "SkipMiniApp", category: "Runtime")

/// Holds the onLoad/onShow/onReady/onHide/onUnload JSValue callbacks for one page.
/// Internal — JSValue is not a bridgeable type.
class PageCallbackSet {
    var onLoad: JSValue?
    var onShow: JSValue?
    var onReady: JSValue?
    var onHide: JSValue?
    var onUnload: JSValue?

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
    /// The MiniApp package this runtime was created for.
    public let package: MiniAppPackage

    /// The manifest for this MiniApp.
    public let manifest: MiniAppManifest

    /// Lifecycle manager for global app state.
    public let lifecycle: MiniAppLifecycle

    /// Pending navigation command set by JS, observed by the view layer.
    public var pendingNavigation: MiniAppNavigationCommand?

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

    /// In-memory key-value storage for miniapp.getStorageSync/setStorageSync.
    private var storage: [String: String] = [:]

    /// Timer tracking for setTimeout/setInterval.
    private var nextTimerId: Int = 1
    private var activeTimers: Set<Int> = []
    private var intervalCallbacks: [Int: JSValue] = [:]

    /// Page lifecycle managers keyed by page path.
    private var pageLifecycles: [String: MiniAppPageLifecycle] = [:]

    // MARK: - Initialization

    /// Creates a new MiniAppRuntime with a JSContext and registers all global bridge functions.
    public init(package: MiniAppPackage, manifest: MiniAppManifest) {
        self.package = package
        self.manifest = manifest
        self.context = JSContext()
        self.lifecycle = MiniAppLifecycle()

        registerGlobals()
    }

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

    /// Register the global Page({...}) function that captures per-page lifecycle callbacks.
    private func registerPageFunction() {
        let runtime = self
        let fn = JSValue(newFunctionIn: context) { ctx, obj, args in
            if let options = args.first, options.isObject {
                let callbacks = PageCallbackSet()

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

                let pagePath = runtime.currentPagePath
                runtime.pageCallbacks[pagePath] = callbacks
            }
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
                let timerId = Int(idVal.toDouble())
                runtime.activeTimers.remove(timerId)
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
                let timerId = Int(idVal.toDouble())
                runtime.activeTimers.remove(timerId)
                runtime.intervalCallbacks.removeValue(forKey: timerId)
            }
            return JSValue(undefinedIn: ctx)
        }
        context.setObject(clearIntervalFn, forKeyedSubscript: "clearInterval")
    }

    /// Register the miniapp.* namespace with system info, storage, navigation, and request APIs.
    private func registerMiniAppNamespace() {
        let miniapp = JSValue(newObjectIn: context)
        let runtime = self

        // miniapp.getSystemInfo()
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

        // miniapp.getStorageSync(key)
        let getStorageSyncFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let key = args.first?.toString() else {
                return JSValue(undefinedIn: ctx)
            }
            if let value = runtime.storage[key] {
                return JSValue(string: value, in: ctx)
            }
            return JSValue(undefinedIn: ctx)
        }
        miniapp.setObject(getStorageSyncFn, forKeyedSubscript: "getStorageSync")

        // miniapp.setStorageSync(key, value)
        let setStorageSyncFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard args.count >= 2 else {
                return JSValue(undefinedIn: ctx)
            }
            let key = args[0].toString() ?? ""
            let value = args[1].toString() ?? ""
            runtime.storage[key] = value
            return JSValue(undefinedIn: ctx)
        }
        miniapp.setObject(setStorageSyncFn, forKeyedSubscript: "setStorageSync")

        // miniapp.removeStorageSync(key)
        let removeStorageSyncFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let key = args.first?.toString() else {
                return JSValue(undefinedIn: ctx)
            }
            runtime.storage.removeValue(forKey: key)
            return JSValue(undefinedIn: ctx)
        }
        miniapp.setObject(removeStorageSyncFn, forKeyedSubscript: "removeStorageSync")

        // miniapp.navigateTo({url, query})
        let navigateToFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            if let options = args.first, options.isObject {
                let urlVal = options.objectForKeyedSubscript("url")
                let queryVal = options.objectForKeyedSubscript("query")
                let url = urlVal.isUndefined ? "" : (urlVal.toString() ?? "")
                let query = queryVal.isUndefined ? "" : (queryVal.toString() ?? "")
                runtime.pendingNavigation = MiniAppNavigationCommand(
                    action: .push,
                    pagePath: url,
                    query: query
                )
            }
            return JSValue(undefinedIn: ctx)
        }
        miniapp.setObject(navigateToFn, forKeyedSubscript: "navigateTo")

        // miniapp.navigateBack()
        let navigateBackFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            if runtime.pageStack.count > 1 {
                runtime.pendingNavigation = MiniAppNavigationCommand(action: .pop)
            }
            return JSValue(undefinedIn: ctx)
        }
        miniapp.setObject(navigateBackFn, forKeyedSubscript: "navigateBack")

        // miniapp.request({url, method, header, success, fail, complete})
        let requestFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            guard let options = args.first, options.isObject else {
                return JSValue(undefinedIn: ctx)
            }
            let urlVal = options.objectForKeyedSubscript("url")
            let methodVal = options.objectForKeyedSubscript("method")
            let urlString = urlVal.isUndefined ? "" : (urlVal.toString() ?? "")
            let method = methodVal.isUndefined ? "GET" : (methodVal.toString() ?? "GET")

            let successCb = options.objectForKeyedSubscript("success")
            let failCb = options.objectForKeyedSubscript("fail")
            let completeCb = options.objectForKeyedSubscript("complete")

            guard let url = URL(string: urlString) else {
                if failCb.isFunction {
                    let errObj = JSValue(newObjectIn: ctx)
                    errObj.setObject(JSValue(string: "invalid url", in: ctx), forKeyedSubscript: "errMsg")
                    let _ = try? failCb.call(withArguments: [errObj])
                }
                if completeCb.isFunction {
                    let _ = try? completeCb.call(withArguments: [])
                }
                return JSValue(undefinedIn: ctx)
            }

            var request = URLRequest(url: url)
            request.httpMethod = method

            // Parse headers if provided
            let headerObj = options.objectForKeyedSubscript("header")
            if headerObj.isObject {
                if let headerDict = headerObj.toObject() as? [String: Any] {
                    for (key, value) in headerDict {
                        request.setValue(String(describing: value), forHTTPHeaderField: key)
                    }
                }
            }

            // Parse body if provided
            let bodyVal = options.objectForKeyedSubscript("data")
            if bodyVal.isString {
                request.httpBody = (bodyVal.toString() ?? "").data(using: .utf8)
            }

            // Fire async HTTP request
            nonisolated(unsafe) let reqSuccessCb = successCb
            nonisolated(unsafe) let reqFailCb = failCb
            nonisolated(unsafe) let reqCompleteCb = completeCb
            nonisolated(unsafe) let reqCtx = ctx
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        if reqFailCb.isFunction {
                            let errObj = JSValue(newObjectIn: reqCtx)
                            errObj.setObject(JSValue(string: error.localizedDescription, in: reqCtx), forKeyedSubscript: "errMsg")
                            let _ = try? reqFailCb.call(withArguments: [errObj])
                        }
                    } else {
                        if reqSuccessCb.isFunction {
                            let resultObj = JSValue(newObjectIn: reqCtx)
                            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
                            resultObj.setObject(JSValue(double: Double(statusCode), in: reqCtx), forKeyedSubscript: "statusCode")
                            if let data = data, let bodyString = String(data: data, encoding: .utf8) {
                                resultObj.setObject(JSValue(string: bodyString, in: reqCtx), forKeyedSubscript: "data")
                            } else {
                                resultObj.setObject(JSValue(string: "", in: reqCtx), forKeyedSubscript: "data")
                            }
                            let _ = try? reqSuccessCb.call(withArguments: [resultObj])
                        }
                    }
                    if reqCompleteCb.isFunction {
                        let _ = try? reqCompleteCb.call(withArguments: [])
                    }
                }
            }.resume()

            return JSValue(undefinedIn: ctx)
        }
        miniapp.setObject(requestFn, forKeyedSubscript: "request")

        context.setObject(miniapp, forKeyedSubscript: "miniapp")
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

        // Fire onLoad
        pageLifecycle.load()
        if let callbacks = pageCallbacks[pagePath], let onLoad = callbacks.onLoad {
            let options = JSValue(newObjectIn: context)
            options.setObject(JSValue(string: query, in: context), forKeyedSubscript: "query")
            let _ = try? onLoad.call(withArguments: [options])
        }
    }

    /// Fire the page onReady callback (first render complete).
    public func firePageReady(pagePath: String) {
        pageLifecycles[pagePath]?.ready()
        if let callbacks = pageCallbacks[pagePath], let onReady = callbacks.onReady {
            let _ = try? onReady.call(withArguments: [])
        }
    }

    /// Fire the page onShow callback.
    public func firePageShow(pagePath: String) {
        pageLifecycles[pagePath]?.show()
        if let callbacks = pageCallbacks[pagePath], let onShow = callbacks.onShow {
            let _ = try? onShow.call(withArguments: [])
        }
    }

    /// Fire the page onHide callback.
    public func firePageHide(pagePath: String) {
        pageLifecycles[pagePath]?.hide()
        if let callbacks = pageCallbacks[pagePath], let onHide = callbacks.onHide {
            let _ = try? onHide.call(withArguments: [])
        }
    }

    /// Fire the page onUnload callback.
    public func firePageUnload(pagePath: String) {
        pageLifecycles[pagePath]?.unload()
        if let callbacks = pageCallbacks[pagePath], let onUnload = callbacks.onUnload {
            let _ = try? onUnload.call(withArguments: [])
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
