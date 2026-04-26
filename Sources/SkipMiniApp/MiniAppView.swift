// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import SwiftUI
import SkipMiniAppModel

#if os(iOS) || SKIP
import SkipWeb

/// A SwiftUI view that hosts and displays a MiniApp from a package file or expanded directory.
///
/// Extracts the package contents to a temporary directory, parses the manifest,
/// displays the start page in a WebView, and integrates MiniAppRuntime to manage
/// JavaScript execution, lifecycle events, and page-to-runtime bridging.
public struct MiniAppHostView: View {
    private let packagePath: String?
    private let directoryURL: URL?
    private let namespace: String
    private let modules: [MiniAppModuleType]
    @State private var manifest: MiniAppManifest?
    @State private var runtime: MiniAppRuntime?
    @State private var startPageURL: URL?
    @State private var errorMessage: String?
    @State private var webViewState: WebViewState = WebViewState()
    @State private var navigator: WebViewNavigator = WebViewNavigator()
    @State private var extractDir: URL?

    /// Load a MiniApp from a `.ma` ZIP package file.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the `.ma` ZIP file.
    ///   - namespace: The JavaScript global name for the bridge API. Defaults to `""miniapp""`.
    ///   - modules: API modules to enable.
    public init(packagePath: String, namespace: String = "miniapp", modules: [MiniAppModuleType]) {
        self.packagePath = packagePath
        self.directoryURL = nil
        self.namespace = namespace
        self.modules = modules
    }

    /// Load a MiniApp from an expanded directory (local file URL or bundle asset URL).
    ///
    /// - Parameters:
    ///   - directoryURL: URL to the expanded MiniApp directory.
    ///   - namespace: The JavaScript global name for the bridge API. Defaults to `"miniapp"`.
    ///   - modules: API modules to enable. Defaults to all built-in modules.
    public init(directoryURL: URL, namespace: String = "miniapp", modules: [MiniAppModuleType]? = nil) {
        self.packagePath = nil
        self.directoryURL = directoryURL
        self.namespace = namespace
        self.modules = modules ?? [MiniAppModuleType(MiniAppFileSystemModule()), MiniAppModuleType(MiniAppNetworkModule()), MiniAppModuleType(MiniAppLoggingModule())]
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let manifest = manifest {
                if manifest.window?.navigationStyle != "custom" {
                    HStack {
                        Text(manifest.window?.navigationBarTitleText ?? manifest.name)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }

            if let errorMessage = errorMessage {
                VStack {
                    Text("Error loading MiniApp")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let url = startPageURL {
                WebView(
                    configuration: webViewConfiguration,
                    navigator: navigator,
                    url: url,
                    state: $webViewState,
                    onNavigationFinished: {
                        if let runtime = runtime, let pagePath = runtime.currentPage {
                            runtime.firePageReady(pagePath: pagePath)
                            runtime.firePageShow(pagePath: pagePath)
                        }
                    }
                )
            } else {
                ProgressView()
            }
        }
        .task {
            loadMiniApp()
        }
        .onAppear {
            if let runtime = runtime {
                runtime.fireAppShow()
                if let pagePath = runtime.currentPage {
                    runtime.firePageShow(pagePath: pagePath)
                }
            }
        }
        .onDisappear {
            if let runtime = runtime {
                if let pagePath = runtime.currentPage {
                    runtime.firePageHide(pagePath: pagePath)
                }
                runtime.fireAppHide()
            }
        }
        .onChange(of: runtime?.pendingNavigation) { _, newValue in
            if let command = newValue, let runtime = runtime {
                handleNavigation(command: command, runtime: runtime)
            }
        }
        .onChange(of: runtime?.pendingDataUpdate) { _, newValue in
            if let jsonPatch = newValue {
                pushDataToView(jsonPatch)
                runtime?.pendingDataUpdate = nil
            }
        }
    }

    /// WebView configuration with message handlers and bridge user script.
    private var webViewConfiguration: WebEngineConfiguration {
        let config = WebEngineConfiguration(
            userScripts: [bridgeUserScript],
            messageHandlers: ["miniappBridge": { message in
                await handleBridgeMessage(message)
            }]
        )
        return config
    }

    /// Alpine.js CSP build source, loaded from the framework bundle.
    private var alpineSource: String {
        guard let url = Bundle.module.url(forResource: "alpine-csp.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return "/* Alpine.js CSP build not found */"
        }
        return source
    }

    /// JavaScript injected into each WebView page for the View Layer.
    ///
    /// Uses Alpine.js (CSP build) for reactive rendering. The View Layer has NO
    /// access to host APIs (storage, fetch, log). It can only:
    /// 1. Display data via Alpine directives (`x-text`, `x-show`, `x-for`, etc.)
    /// 2. Send user events back to the Logic Layer via `handler('name')` calls
    /// 3. Two-way bind inputs via `x-model` + `model('key')` sync
    ///
    /// HTML templates use `x-data="page"` and reference `store.*` for data.
    private var bridgeUserScript: WebViewUserScript {
        let initialData = runtime?.initialDataJSON() ?? "{}"
        let handlerNames = runtime?.pageHandlerNames() ?? []
        let translationsJSON = runtime?.i18nModule?.translationsJSON() ?? "{}"
        let activeLocale = runtime?.i18nModule?.activeLocale ?? "en"

        // Generate handler function properties for the Alpine component.
        var handlerProps = ""
        for name in handlerNames {
            let safeName = name.replacingOccurrences(of: "'", with: "\\'")
            handlerProps += "                    \(name): function(detail) { window.$handler('\(safeName)', detail); },\n"
        }

        let bridgeScript = """
        // --- Bridge: event dispatch to Logic Layer ---
        window.$handler = function(name, detail) {
            try {
                webkit.messageHandlers.miniappBridge.postMessage({
                    action: '__event',
                    data: { type: 'tap', handler: name, detail: detail || {} }
                });
            } catch(e) {}
        };

        // --- Bridge: two-way model sync to Logic Layer ---
        window.$model = function(key, value) {
            try {
                webkit.messageHandlers.miniappBridge.postMessage({
                    action: '__model',
                    data: { key: key, value: String(value) }
                });
            } catch(e) {}
        };

        // --- Internationalization ---
        window.__i18nMessages = JSON.parse('\(Self.escapeJSString(translationsJSON))');
        window.__i18nLocale = '\(Self.escapeJSString(activeLocale))';
        window.__i18nTranslate = function(key, params) {
            var msg = window.__i18nMessages[key] || key;
            if (params) {
                var keys = Object.keys(params);
                for (var i = 0; i < keys.length; i++) {
                    var k = keys[i];
                    msg = msg.split('{' + k + '}').join(String(params[k]));
                }
            }
            return msg;
        };

        // --- Alpine initialization ---
        document.addEventListener('alpine:init', function() {
            // Register $t magic for localization in templates
            Alpine.magic('t', function() {
                return function(key, params) {
                    return window.__i18nTranslate(key, params);
                };
            });

            // Register the reactive page data store
            Alpine.store('page', \(initialData));

            // Register the page component used via x-data="page"
            Alpine.data('page', function() {
                return {
                    get store() { return Alpine.store('page'); },
                    // Dispatch an event to the Logic Layer by handler name
                    handler: function(name, detail) { window.$handler(name, detail); },
                    // Sync an x-model key to the Logic Layer
                    model: function(key) { window.$model(key, Alpine.store('page')[key]); },
                    // Pre-registered page handlers (generated from Page config keys).
                    // Allows @click="onSaveNote" instead of @click="handler('onSaveNote')".
        \(handlerProps)
                    init: function() {
                        // Auto-sync x-model inputs to the Logic Layer.
                        // Discovers all [x-model="store.KEY"] elements and adds native input
                        // listeners so the view-side change propagates without manual @input.
                        this.$nextTick(function() {
                            var els = document.querySelectorAll('[x-model]');
                            for (var i = 0; i < els.length; i++) {
                                (function(el) {
                                    var attr = el.getAttribute('x-model');
                                    if (attr && attr.indexOf('store.') === 0) {
                                        var key = attr.substring(6);
                                        el.addEventListener('input', function() {
                                            window.$model(key, el.value);
                                        });
                                    }
                                })(els[i]);
                            }
                        });
                    }
                };
            });
        });

        // --- setData bridge: Logic Layer → View Layer ---
        // Called from native via evaluateJavaScript when the Logic Layer calls setData().
        // Mutates Alpine's reactive store, which automatically triggers DOM updates.
        window.__miniappSetData = function(patch) {
            if (typeof Alpine === 'undefined') return;
            var store = Alpine.store('page');
            if (!store) return;
            var keys = Object.keys(patch);
            for (var i = 0; i < keys.length; i++) {
                var key = keys[i];
                var val = patch[key];
                if (key.indexOf('.') === -1 && key.indexOf('[') === -1) {
                    store[key] = val;
                } else {
                    var parts = key.replace(/\\[/g, '.').replace(/\\]/g, '').split('.');
                    var obj = store;
                    for (var j = 0; j < parts.length - 1; j++) {
                        if (obj[parts[j]] === undefined) obj[parts[j]] = {};
                        obj = obj[parts[j]];
                    }
                    obj[parts[parts.length - 1]] = val;
                }
            }
        };

        // --- Start Alpine after DOM is ready ---
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() { Alpine.start(); });
        } else {
            Alpine.start();
        }
        """

        // Assemble: Alpine source first, then bridge/store setup
        let fullScript = alpineSource + "\n" + bridgeScript
        return WebViewUserScript(source: fullScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    private func loadMiniApp() {
        do {
            if let directoryURL = directoryURL {
                try loadFromDirectory(directoryURL)
            } else if let packagePath = packagePath {
                try loadFromPackage(packagePath)
            }
        } catch {
            self.errorMessage = String(describing: error)
        }
    }

    private func loadFromPackage(_ path: String) throws {
        let package = MiniAppPackage(path: path)
        let m = try package.readManifest()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("miniapp")
            .appendingPathComponent(m.appId)

        // Clean and recreate extraction directory
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try package.extractToDirectory(at: dir.path)

        startRuntime(package: package, manifest: m, servingDir: dir)
    }

    private func loadFromDirectory(_ sourceURL: URL) throws {
        let dirPackage = MiniAppDirectoryPackage(rootURL: sourceURL)
        let m = try dirPackage.readManifest()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("miniapp")
            .appendingPathComponent(m.appId)

        // Clean and recreate serving directory
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Copy known files from the source directory to the temp serving directory.
        // Uses Data(contentsOf:) which works for both iOS file URLs and Android APK asset URLs.
        let filesToCopy = buildFileList(manifest: m)
        for relativePath in filesToCopy {
            let srcURL = sourceURL.appendingPathComponent(relativePath)
            guard let data = try? Data(contentsOf: srcURL), !data.isEmpty else { continue }
            let destURL = dir.appendingPathComponent(relativePath)
            let destDir = destURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: destURL.path, contents: data, attributes: nil)
        }

        startRuntime(package: dirPackage, manifest: m, servingDir: dir)
    }

    /// Build the list of files to copy from the source directory based on the manifest.
    private func buildFileList(manifest: MiniAppManifest) -> [String] {
        var files = ["manifest.json", "app.js", "app.css"]
        for pagePath in manifest.pages {
            files.append(pagePath + ".html")
            files.append(pagePath + ".js")
            files.append(pagePath + ".css")
        }
        return files
    }

    private func startRuntime(package: MiniAppPackageReader, manifest: MiniAppManifest, servingDir: URL) {
        self.manifest = manifest
        self.extractDir = servingDir

        let rt = MiniAppRuntime(package: package, manifest: manifest, namespace: namespace, modules: modules)
        rt.start()
        rt.fireAppShow()

        if let firstPage = manifest.pages.first {
            rt.loadPage(pagePath: firstPage)
            self.startPageURL = servingDir.appendingPathComponent(firstPage + ".html")
        }

        self.runtime = rt
    }

    /// Handle a navigation command from the JS runtime.
    private func handleNavigation(command: MiniAppNavigationCommand, runtime: MiniAppRuntime) {
        runtime.processNavigation(command)

        // Load the new page URL in the WebView
        if command.action == .push, let dir = extractDir {
            let pageURL = dir.appendingPathComponent(command.pagePath + ".html")
            navigator.load(url: pageURL)
        } else if command.action == .pop, let currentPage = runtime.currentPage, let dir = extractDir {
            let pageURL = dir.appendingPathComponent(currentPage + ".html")
            navigator.load(url: pageURL)
        }
    }

    /// Handle bridge messages from the WebView (View Layer).
    ///
    /// In the dual-thread model, the only message type from the view is `__event`,
    /// which dispatches user interactions (taps, input) to the Logic Layer's page handlers.
    @MainActor
    private func handleBridgeMessage(_ message: WebViewMessage) {
        guard let runtime = runtime else { return }

        let json: [String: Any]
        // SKIP NOWARN
        if let dict = message.body as? [String: Any] {
            json = dict
        } else if let bodyString = message.body as? String,
                  let bodyData = bodyString.data(using: .utf8),
                  // SKIP NOWARN
                  let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            json = parsed
        } else {
            return
        }

        // SKIP NOWARN
        guard let action = json["action"] as? String,
              // SKIP NOWARN
              let data = json["data"] as? [String: Any] else {
            return
        }

        switch action {
        case "__event":
            // Dispatch user event from View Layer to Logic Layer.
            if let handlerName = data["handler"] as? String {
                let eventType = data["type"] as? String ?? "tap"
                let detail = data["detail"] as? [String: Any] ?? [:]
                let fullEvent: [String: Any] = [
                    "type": eventType,
                    "detail": detail
                ]
                if let eventData = try? JSONSerialization.data(withJSONObject: fullEvent),
                   let eventJSON = String(data: eventData, encoding: .utf8) {
                    runtime.dispatchEvent(handlerName: handlerName, eventJSON: eventJSON)
                }
            }
        case "__model":
            // Two-way binding: Alpine x-model updated in view, sync to logic layer's data
            if let key = data["key"] as? String {
                let value = data["value"] as? String ?? ""
                runtime.updatePageData(key: key, value: value)
            }
        default:
            break
        }
    }

    /// Push a setData patch from the Logic Layer to the View Layer's WebView.
    private func pushDataToView(_ jsonPatch: String) {
        let escaped = jsonPatch.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = "window.__miniappSetData && window.__miniappSetData(JSON.parse('\(escaped)'))"
        Task { @MainActor in
            let _ = try? await navigator.evaluateJavaScript(js)
        }
    }

    /// Escape a string for safe embedding in a JavaScript single-quoted string.
    private static func escapeJSString(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

#endif // os(iOS) || SKIP

#endif // !SKIP_BRIDGE
