// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

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
    private let packagePath: String
    @State private var manifest: MiniAppManifest?
    @State private var runtime: MiniAppRuntime?
    @State private var startPageURL: URL?
    @State private var errorMessage: String?
    @State private var webViewState: WebViewState = WebViewState()
    @State private var navigator: WebViewNavigator = WebViewNavigator()
    @State private var extractDir: URL?

    public init(packagePath: String) {
        self.packagePath = packagePath
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
    private var bridgeUserScript: WebViewUserScript {
        let script = """
        (function() {
            if (!window.miniapp) window.miniapp = {};
            var _callId = 0;
            var _callbacks = {};

            function sendMessage(action, data, callback) {
                var id = ++_callId;
                if (callback) { _callbacks[id] = callback; }
                webkit.messageHandlers.miniappBridge.postMessage(
                    JSON.stringify({ callId: id, action: action, data: data })
                );
            }

            window._miniappBridgeResponse = function(callId, success, data) {
                var cb = _callbacks[callId];
                if (cb) {
                    cb(success, data);
                    delete _callbacks[callId];
                }
            };

            miniapp.getStorageSync = function(key) {
                sendMessage('getStorageSync', { key: key });
            };
            miniapp.setStorageSync = function(key, value) {
                sendMessage('setStorageSync', { key: key, value: value });
            };
            miniapp.removeStorageSync = function(key) {
                sendMessage('removeStorageSync', { key: key });
            };
            miniapp.navigateTo = function(options) {
                sendMessage('navigateTo', { url: options.url || '', query: options.query || '' });
            };
            miniapp.navigateBack = function() {
                sendMessage('navigateBack', {});
            };
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
        return WebViewUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private func loadMiniApp() {
        do {
            let package = MiniAppPackage(path: packagePath)
            let m = try package.readManifest()

            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("miniapp")
                .appendingPathComponent(m.appId)

            // Clean and recreate extraction directory
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try package.extractToDirectory(at: dir.path)

            self.manifest = m
            self.extractDir = dir

            // Create and start runtime
            let rt = MiniAppRuntime(package: package, manifest: m)
            rt.start()
            rt.fireAppShow()

            // Load the first page
            if let firstPage = m.pages.first {
                rt.loadPage(pagePath: firstPage)
                self.startPageURL = dir.appendingPathComponent(firstPage + ".html")
            }

            self.runtime = rt
        } catch {
            self.errorMessage = String(describing: error)
        }
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
        case "getStorageSync":
            if let key = data["key"] as? String {
                let result = runtime.evaluateScript("miniapp.getStorageSync('\(key.replacingOccurrences(of: "'", with: "\\'"))')")
                let value = result ?? ""
                sendBridgeResponse(callId: callId, success: true, data: value)
            }
        case "setStorageSync":
            if let key = data["key"] as? String, let value = data["value"] as? String {
                let safeKey = key.replacingOccurrences(of: "'", with: "\\'")
                let safeVal = value.replacingOccurrences(of: "'", with: "\\'")
                runtime.evaluateScript("miniapp.setStorageSync('\(safeKey)', '\(safeVal)')")
            }
        case "removeStorageSync":
            if let key = data["key"] as? String {
                let safeKey = key.replacingOccurrences(of: "'", with: "\\'")
                runtime.evaluateScript("miniapp.removeStorageSync('\(safeKey)')")
            }
        case "navigateTo":
            if let url = data["url"] as? String {
                let query = data["query"] as? String ?? ""
                let safeUrl = url.replacingOccurrences(of: "'", with: "\\'")
                let safeQuery = query.replacingOccurrences(of: "'", with: "\\'")
                runtime.evaluateScript("miniapp.navigateTo({url: '\(safeUrl)', query: '\(safeQuery)'})")
            }
        case "navigateBack":
            runtime.evaluateScript("miniapp.navigateBack()")
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
