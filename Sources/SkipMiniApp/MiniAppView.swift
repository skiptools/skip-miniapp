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

    /// JavaScript injected into each WebView page for the View Layer.
    ///
    /// The View Layer has NO access to host APIs (storage, fetch, log). It can only:
    /// 1. Receive data updates via `window.__miniappSetData(patch)`
    /// 2. Send user events (taps, input) back to the Logic Layer via the bridge
    ///
    /// HTML elements use `data-bind="key"` for data display and
    /// `data-event-tap="handlerName"` / `data-event-input="handlerName"` for events.
    private var bridgeUserScript: WebViewUserScript {
        // Get initial page data from the runtime
        let initialData = runtime?.initialDataJSON() ?? "{}"

        let script = """
        (function() {
            // --- View Layer data store (on window so native evaluateJavaScript can access it) ---
            window._miniappData = \(initialData);
            var _data = window._miniappData;

            // Receive data patches from the Logic Layer (called by native bridge)
            window.__miniappSetData = function(patch) {
                var d = window._miniappData;
                if (!d) { window._miniappData = {}; d = window._miniappData; }
                // Path-based merge
                var keys = Object.keys(patch);
                for (var i = 0; i < keys.length; i++) {
                    var key = keys[i];
                    var val = patch[key];
                    if (key.indexOf('.') === -1 && key.indexOf('[') === -1) {
                        d[key] = val;
                    } else {
                        var parts = key.replace(/\\[/g, '.').replace(/\\]/g, '').split('.');
                        var obj = d;
                        for (var j = 0; j < parts.length - 1; j++) {
                            if (obj[parts[j]] === undefined) obj[parts[j]] = {};
                            obj = obj[parts[j]];
                        }
                        obj[parts[parts.length - 1]] = val;
                    }
                }
                _data = d;
                __renderData();
            };

            // Render data into bound DOM elements
            function __renderData() {
                var d = window._miniappData || {};
                document.querySelectorAll('[data-bind]').forEach(function(el) {
                    var key = el.getAttribute('data-bind');
                    var val = __resolveKey(d, key);
                    if (val === undefined || val === null) val = '';
                    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                        el.value = val;
                    } else if (typeof val === 'boolean') {
                        // For boolean bindings, toggle visibility or class
                        if (el.hasAttribute('data-bind-class')) {
                            var cls = el.getAttribute('data-bind-class');
                            if (val) el.classList.add(cls);
                            else el.classList.remove(cls);
                        } else {
                            el.textContent = String(val);
                        }
                    } else {
                        el.textContent = String(val);
                    }
                });
            }

            // Resolve a potentially dotted/bracketed key path
            function __resolveKey(obj, key) {
                if (key.indexOf('.') === -1 && key.indexOf('[') === -1) return obj[key];
                var parts = key.replace(/\\[/g, '.').replace(/\\]/g, '').split('.');
                var current = obj;
                for (var i = 0; i < parts.length; i++) {
                    if (current === undefined || current === null) return undefined;
                    current = current[parts[i]];
                }
                return current;
            }

            // --- Event system: View → Logic Layer ---
            function sendEvent(type, handler, detail) {
                try {
                    webkit.messageHandlers.miniappBridge.postMessage({
                        action: '__event',
                        data: { type: type, handler: handler, detail: detail || {} }
                    });
                } catch(e) {}
            }

            // Tap events via data-event-tap="handlerName"
            document.addEventListener('click', function(e) {
                var el = e.target.closest('[data-event-tap]');
                if (el) {
                    var handler = el.getAttribute('data-event-tap');
                    var dataset = {};
                    for (var attr in el.dataset) {
                        if (attr !== 'eventTap' && attr !== 'bind' && attr !== 'bindClass') {
                            dataset[attr] = el.dataset[attr];
                        }
                    }
                    sendEvent('tap', handler, { dataset: dataset });
                }
            });

            // Input events via data-event-input="handlerName"
            document.addEventListener('input', function(e) {
                var el = e.target.closest('[data-event-input]');
                if (el) {
                    var handler = el.getAttribute('data-event-input');
                    sendEvent('input', handler, { value: el.value });
                }
            });

            // Change events via data-event-change="handlerName"
            document.addEventListener('change', function(e) {
                var el = e.target.closest('[data-event-change]');
                if (el) {
                    var handler = el.getAttribute('data-event-change');
                    sendEvent('change', handler, { value: el.value, checked: el.checked });
                }
            });

            // Initial render with the data provided at page load
            document.addEventListener('DOMContentLoaded', function() {
                __renderData();
            });
            // Also render immediately in case DOM is already loaded
            if (document.readyState !== 'loading') {
                __renderData();
            }
        })();
        """
        return WebViewUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
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
            // Build a full event object with type, detail, and dataset (matching WeChat's event model).
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
}

#endif // os(iOS) || SKIP

#endif // !SKIP_BRIDGE
