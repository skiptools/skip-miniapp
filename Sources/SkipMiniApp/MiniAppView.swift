// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import SwiftUI
import SkipMiniAppModel

#if os(iOS) || SKIP
import SkipWeb

/// A SwiftUI view that loads and displays a MiniApp from a package file.
///
/// Extracts the package contents to a temporary directory, parses the manifest,
/// displays the start page in a WebView, and integrates MiniAppRuntime to manage
/// JavaScript execution, lifecycle events, and page-to-runtime bridging.
public struct MiniAppView: View {
    private let packagePath: String?
    private let directoryURL: URL?
    @State private var manifest: MiniAppManifest?
    @State private var runtime: MiniAppRuntime?
    @State private var startPageURL: URL?
    @State private var errorMessage: String?
    @State private var webViewState: WebViewState = WebViewState()
    @State private var navigator: WebViewNavigator = WebViewNavigator()
    @State private var extractDir: URL?

    /// Load a MiniApp from a `.ma` ZIP package file.
    public init(packagePath: String) {
        self.packagePath = packagePath
        self.directoryURL = nil
    }

    /// Load a MiniApp from an expanded directory (local file URL or bundle asset URL).
    ///
    /// The directory must contain a `manifest.json` and the files referenced by it.
    /// On Android, files are copied from the bundle to a temp directory so that the
    /// WebView can load them via file:// URLs.
    public init(directoryURL: URL) {
        self.packagePath = nil
        self.directoryURL = directoryURL
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

    /// JavaScript injected into each WebView page to provide the miniapp.* bridge API.
    ///
    /// Storage is pre-populated from the runtime's MiniAppStorage so that reads are
    /// synchronous. Writes update the local copy and post to the native bridge for
    /// persistence. `window.localStorage` is blocked to prevent unsandboxed access.
    private var bridgeUserScript: WebViewUserScript {
        // Serialize current storage state as JSON for injection
        var storageJSON = "{}"
        if let rt = runtime {
            var dict: [String: String] = [:]
            for key in rt.storage.keys() {
                if let value = rt.storage.get(key) {
                    dict[key] = value
                }
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let json = String(data: data, encoding: .utf8) {
                storageJSON = json
            }
        }

        let script = """
        (function() {
            // --- Block localStorage to prevent unsandboxed access ---
            var _blockedStorageError = 'localStorage is not available in MiniApps. Use miniapp.getStorageSync() / miniapp.setStorageSync() instead.';
            try {
                Object.defineProperty(window, 'localStorage', {
                    get: function() {
                        throw new Error(_blockedStorageError);
                    },
                    configurable: false
                });
            } catch(e) { /* may fail in some environments */ }

            // --- MiniApp bridge setup ---
            if (!window.miniapp) window.miniapp = {};
            var _callId = 0;
            var _callbacks = {};

            function sendMessage(action, data, callback) {
                var id = ++_callId;
                if (callback) { _callbacks[id] = callback; }
                try {
                    webkit.messageHandlers.miniappBridge.postMessage(
                        JSON.stringify({ callId: id, action: action, data: data })
                    );
                } catch(e) { /* bridge not available */ }
            }

            window._miniappBridgeResponse = function(callId, success, data) {
                var cb = _callbacks[callId];
                if (cb) {
                    cb(success, data);
                    delete _callbacks[callId];
                }
            };

            // --- Synchronous storage backed by a local JS object ---
            // Pre-populated from the native MiniAppStorage state at page load.
            // Writes are synchronous locally and async-persisted via the bridge.
            var _store = \(storageJSON);

            miniapp.getStorageSync = function(key) {
                return _store.hasOwnProperty(key) ? _store[key] : undefined;
            };
            miniapp.setStorageSync = function(key, value) {
                var v = String(value);
                _store[key] = v;
                sendMessage('setStorageSync', { key: key, value: v });
            };
            miniapp.removeStorageSync = function(key) {
                delete _store[key];
                sendMessage('removeStorageSync', { key: key });
            };
            miniapp.getStorageKeys = function() {
                return Object.keys(_store);
            };
            miniapp.clearStorage = function() {
                _store = {};
                sendMessage('clearStorage', {});
            };

            // --- Navigation ---
            miniapp.navigateTo = function(options) {
                sendMessage('navigateTo', { url: options.url || '', query: options.query || '' });
            };
            miniapp.navigateBack = function() {
                sendMessage('navigateBack', {});
            };

            // --- HTTP requests ---
            miniapp.request = function(options) {
                sendMessage('request', {
                    url: options.url || '',
                    method: options.method || 'GET',
                    header: options.header || {},
                    data: options.data || ''
                }, function(success, data) {
                    if (success && options.success) { options.success(data); }
                    if (!success && options.fail) { options.fail(data); }
                    if (options.complete) { options.complete(); }
                });
            };
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

        let rt = MiniAppRuntime(package: package, manifest: manifest)
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
        guard let bodyString = message.body as? String,
              let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let action = json["action"] as? String,
              let data = json["data"] as? [String: Any] else {
            return
        }
        let callId = json["callId"] as? Int ?? 0

        switch action {
        case "setStorageSync":
            if let key = data["key"] as? String, let value = data["value"] as? String {
                // Persist the write from the WebView's local JS store to MiniAppStorage
                runtime.storage.set(key, value: value)
            }
        case "removeStorageSync":
            if let key = data["key"] as? String {
                runtime.storage.remove(key)
            }
        case "clearStorage":
            runtime.storage.clear()
        case "navigateTo":
            if let url = data["url"] as? String {
                let query = data["query"] as? String ?? ""
                runtime.pendingNavigation = MiniAppNavigationCommand(action: .push, pagePath: url, query: query)
            }
        case "navigateBack":
            runtime.pendingNavigation = MiniAppNavigationCommand(action: .pop)
        default:
            break
        }
    }

    /// Send a response back to the WebView JavaScript bridge.
    private func sendBridgeResponse(callId: Int, success: Bool, data: String) {
        let js = "window._miniappBridgeResponse(\(callId), \(success), '\(data.replacingOccurrences(of: "'", with: "\\'"))')"
        Task { @MainActor in
            let _ = try? await navigator.evaluateJavaScript(js)
        }
    }
}

#endif // os(iOS) || SKIP

#endif // !SKIP_BRIDGE
