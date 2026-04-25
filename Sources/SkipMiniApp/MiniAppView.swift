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

    /// JavaScript injected into each WebView page.
    ///
    /// Assembles the core bridge infrastructure plus each module's bridge script.
    private var bridgeUserScript: WebViewUserScript {
        // Pre-populate the storage state for the FileSystemModule if present
        var storageJSON = "{}"
        if let rt = runtime, let fsModule = modules.first(where: { $0.module is MiniAppFileSystemModule })?.module as? MiniAppFileSystemModule {
            storageJSON = fsModule.storageJSON(for: rt)
        }

        // Collect module bridge scripts
        var moduleScripts = ""
        for moduleType in modules {
            let script = moduleType.module.bridgeScript()
            if !script.isEmpty {
                moduleScripts += "\n" + script
            }
        }

        let ns = namespace
        let script = """
        (function() {
            var _ns = '\(ns)';

            // --- MiniApp bridge setup ---
            if (!window[_ns]) window[_ns] = {};
            var _api = window[_ns];
            var _callId = 0;
            var _callbacks = {};

            function sendMessage(action, data, callback) {
                var id = ++_callId;
                if (callback) { _callbacks[id] = callback; }
                try {
                    webkit.messageHandlers.miniappBridge.postMessage(
                        { callId: id, action: action, data: data }
                    );
                } catch(e) {}
            }

            window._miniappBridgeResponse = function(callId, success, data) {
                var cb = _callbacks[callId];
                if (cb) {
                    cb(success, data);
                    delete _callbacks[callId];
                }
            };

            // Pre-populated storage state for FileSystemModule
            var _store = \(storageJSON);

            // --- Core: Navigation ---
            _api.navigateTo = function(options) {
                sendMessage('navigateTo', { url: options.url || '', query: options.query || '' });
            };
            _api.navigateBack = function() {
                sendMessage('navigateBack', {});
            };

            // --- Module bridge scripts ---
            \(moduleScripts)

            // Also expose under the standard "miniapp" name for W3C compatibility
            if (_ns !== 'miniapp') {
                window.miniapp = _api;
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

    /// Handle bridge messages from the WebView's JavaScript.
    @MainActor
    private func handleBridgeMessage(_ message: WebViewMessage) {
        guard let runtime = runtime else { return }

        // On iOS, WKWebView auto-converts JS objects to NSDictionary.
        // On Android, SkipWeb's router parses the JSON into a dictionary.
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
        let callId = json["callId"] as? Int ?? 0

        // Core actions: navigation
        switch action {
        case "navigateTo":
            if let url = data["url"] as? String {
                let query = data["query"] as? String ?? ""
                runtime.pendingNavigation = MiniAppNavigationCommand(action: .push, pagePath: url, query: query)
            }
            return
        case "navigateBack":
            runtime.pendingNavigation = MiniAppNavigationCommand(action: .pop)
            return
        default:
            break
        }

        // Delegate to modules
        let respond: (Int, Bool, [String: Any]) -> Void = { callId, success, responseJSON in
            self.sendBridgeResponseJSON(callId: callId, success: success, json: responseJSON)
        }
        for moduleType in modules {
            if moduleType.module.handleBridgeMessage(action: action, data: data, callId: callId, runtime: runtime, respond: respond) {
                return
            }
        }
    }

    /// Send a string response back to the WebView JavaScript bridge.
    private func sendBridgeResponse(callId: Int, success: Bool, data: String) {
        let js = "window._miniappBridgeResponse(\(callId), \(success), '\(data.replacingOccurrences(of: "'", with: "\\'"))')"
        Task { @MainActor in
            let _ = try? await navigator.evaluateJavaScript(js)
        }
    }

    /// Send a JSON object response back to the WebView JavaScript bridge.
    private func sendBridgeResponseJSON(callId: Int, success: Bool, json: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        // Pass as a parsed object, not a string literal
        let js = "window._miniappBridgeResponse(\(callId), \(success), \(jsonString))"
        Task { @MainActor in
            let _ = try? await navigator.evaluateJavaScript(js)
        }
    }
}

#endif // os(iOS) || SKIP

#endif // !SKIP_BRIDGE
