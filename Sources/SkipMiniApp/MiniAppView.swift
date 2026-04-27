// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import SwiftUI
import SkipMiniAppModel

#if os(iOS) || SKIP

import SkipWeb

/// A SwiftUI view that hosts and displays a MiniApp from a package file or expanded directory.
///
/// Manages a real SwiftUI TabView (when the manifest defines `tabBar`) with per-tab
/// NavigationStacks. Each page in the navigation stack gets its own WebView instance.
/// Implements all 5 WeChat navigation APIs via MiniAppNavigationModule.
public struct MiniAppHostView: View {
    private let packagePath: String?
    private let directoryURL: URL?
    private let namespace: String
    private let modules: [MiniAppModuleType]
    private let onDismiss: (() -> Void)?

    @State private var manifest: MiniAppManifest?
    @State private var runtime: MiniAppRuntime?
    @State private var errorMessage: String?
    @State private var extractDir: URL?
    @State private var activeTabIndex: Int = 0
    @State private var tabPaths: [[MiniAppPageRoute]] = []

    /// Load a MiniApp from a `.ma` ZIP package file.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the `.ma` ZIP file.
    ///   - namespace: The JavaScript global name for the bridge API. Defaults to `"miniapp"`.
    ///   - modules: API modules to enable.
    ///   - onDismiss: Called when the close button is tapped.
    public init(packagePath: String, namespace: String = "miniapp", modules: [MiniAppModuleType], onDismiss: (() -> Void)? = nil) {
        self.packagePath = packagePath
        self.directoryURL = nil
        self.namespace = namespace
        self.modules = modules
        self.onDismiss = onDismiss
    }

    /// Load a MiniApp from an expanded directory (local file URL or bundle asset URL).
    ///
    /// - Parameters:
    ///   - directoryURL: URL to the expanded MiniApp directory.
    ///   - namespace: The JavaScript global name for the bridge API. Defaults to `"miniapp"`.
    ///   - modules: API modules to enable. Defaults to all built-in modules.
    ///   - onDismiss: Called when the close button is tapped.
    public init(directoryURL: URL, namespace: String = "miniapp", modules: [MiniAppModuleType]? = nil, onDismiss: (() -> Void)? = nil) {
        self.packagePath = nil
        self.directoryURL = directoryURL
        self.namespace = namespace
        self.modules = modules ?? [MiniAppModuleType(MiniAppFileSystemModule()), MiniAppModuleType(MiniAppNetworkModule()), MiniAppModuleType(MiniAppLoggingModule())]
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = errorMessage {
                VStack {
                    Text("Error loading MiniApp")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let manifest = manifest, let runtime = runtime, let extractDir = extractDir {
                // Content: TabView or single NavigationStack
                if let tabBar = manifest.tabBar, tabBar.tabs.count >= 2 {
                    tabbedContent(tabBar: tabBar, manifest: manifest, runtime: runtime, servingDir: extractDir)
                } else {
                    singlePageContent(manifest: manifest, runtime: runtime, servingDir: extractDir)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            loadMiniApp()
        }
        .onChange(of: runtime?.navigationModule?.pendingAction) { _, newAction in
            if let action = newAction {
                handleNavigationAction(action)
                runtime?.navigationModule?.pendingAction = nil
            }
        }
    }

    // MARK: - Tabbed Content

    @ViewBuilder
    private func tabbedContent(tabBar: MiniAppTabBar, manifest: MiniAppManifest, runtime: MiniAppRuntime, servingDir: URL) -> some View {
        TabView(selection: $activeTabIndex) {
            ForEach(Array(tabBar.tabs.enumerated()), id: \.offset) { index, tab in
                tabNavigationStack(tabIndex: index, rootPage: tab.page, runtime: runtime, servingDir: servingDir)
                    .tabItem {
                        tabLabel(for: tab, index: index, runtime: runtime, servingDir: servingDir)
                    }
                    .tag(index)
            }
        }
        .onChange(of: activeTabIndex) { _, newIndex in
            runtime.navigationModule?.activeTabIndex = newIndex
        }
    }

    @ViewBuilder
    private func tabLabel(for tab: MiniAppTab, index: Int, runtime: MiniAppRuntime, servingDir: URL) -> some View {
        let title = localizedText(tab.text, runtime: runtime)
        if let icon = tab.icon, !icon.isEmpty {
            let iconURL = servingDir.appendingPathComponent(icon)
            Label {
                Text(title)
            } icon: {
                SVGIcon(url: iconURL, render: true)
            }
        } else {
            Label(title, systemImage: tabIconFallback(index: index))
        }
    }

    @ViewBuilder
    private func tabNavigationStack(tabIndex: Int, rootPage: String, runtime: MiniAppRuntime, servingDir: URL) -> some View {
        if tabIndex < tabPaths.count {
            NavigationStack(path: Binding(
                get: { tabPaths[tabIndex] },
                set: { tabPaths[tabIndex] = $0 }
            )) {
                MiniAppPageView(
                    pagePath: rootPage,
                    runtime: runtime,
                    servingDir: servingDir,
                    onDismiss: onDismiss
                )
                .navigationDestination(for: MiniAppPageRoute.self) { route in
                    MiniAppPageView(
                        pagePath: route.path,
                        query: route.query,
                        runtime: runtime,
                        servingDir: servingDir,
                        onDismiss: onDismiss
                    )
                }
            }
        }
    }

    // MARK: - Single Page Content (no tab bar)

    @ViewBuilder
    private func singlePageContent(manifest: MiniAppManifest, runtime: MiniAppRuntime, servingDir: URL) -> some View {
        if !tabPaths.isEmpty {
            NavigationStack(path: Binding(
                get: { tabPaths[0] },
                set: { tabPaths[0] = $0 }
            )) {
                if let firstPage = manifest.pages.first {
                    MiniAppPageView(
                        pagePath: firstPage,
                        runtime: runtime,
                        servingDir: servingDir,
                        onDismiss: onDismiss
                    )
                    .navigationDestination(for: MiniAppPageRoute.self) { route in
                        MiniAppPageView(
                            pagePath: route.path,
                            query: route.query,
                            runtime: runtime,
                            servingDir: servingDir,
                            onDismiss: onDismiss
                        )
                    }
                }
            }
        }
    }

    // MARK: - Navigation Actions

    private func handleNavigationAction(_ action: MiniAppNavAction) {
        guard let navModule = runtime?.navigationModule else { return }

        switch action {
        case .navigateTo(let url, let query):
            // Push page onto current tab's stack
            navModule.push(page: url)
            let route = MiniAppPageRoute(path: url, query: query)
            if activeTabIndex < tabPaths.count {
                tabPaths[activeTabIndex].append(route)
            }

        case .navigateBack(let delta):
            navModule.pop(delta: delta)
            if activeTabIndex < tabPaths.count {
                let removeCount = min(delta, tabPaths[activeTabIndex].count)
                if removeCount > 0 {
                    tabPaths[activeTabIndex].removeLast(removeCount)
                }
            }

        case .redirectTo(let url):
            navModule.replace(page: url)
            if activeTabIndex < tabPaths.count {
                let route = MiniAppPageRoute(path: url)
                if tabPaths[activeTabIndex].count > 0 {
                    tabPaths[activeTabIndex][tabPaths[activeTabIndex].count - 1] = route
                }
            }

        case .reLaunch(let url):
            navModule.reLaunch(page: url)
            // Clear all tab stacks
            for i in 0..<tabPaths.count {
                tabPaths[i] = []
            }
            // If not a tab root, push it onto the current tab
            if navModule.tabIndexForPage(url) == nil {
                tabPaths[navModule.activeTabIndex].append(MiniAppPageRoute(path: url))
            }
            activeTabIndex = navModule.activeTabIndex

        case .switchTab(let url):
            navModule.switchToTab(page: url)
            activeTabIndex = navModule.activeTabIndex
        }
    }

    // MARK: - Loading

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

        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

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

    private func buildFileList(manifest: MiniAppManifest) -> [String] {
        var files = ["manifest.json", "app.js", "app.css"]
        for pagePath in manifest.pages {
            files.append(pagePath + ".html")
            files.append(pagePath + ".js")
            files.append(pagePath + ".css")
        }
        // Include tab bar icon SVGs
        if let tabBar = manifest.tabBar {
            for tab in tabBar.tabs {
                if let icon = tab.icon, !icon.isEmpty {
                    files.append(icon)
                }
            }
        }
        return files
    }

    private func startRuntime(package: MiniAppPackageReader, manifest: MiniAppManifest, servingDir: URL) {
        self.manifest = manifest
        self.extractDir = servingDir

        // Ensure navigation module is included
        var allModules = modules
        if !allModules.contains(where: { $0.module is MiniAppNavigationModule }) {
            allModules.append(.navigation)
        }

        let rt = MiniAppRuntime(package: package, manifest: manifest, namespace: namespace, modules: allModules)
        rt.start()
        rt.fireAppShow()

        // Initialize tab paths to match navigation module's tab stacks
        if let navModule = rt.navigationModule {
            tabPaths = navModule.tabStacks.map { _ in [MiniAppPageRoute]() }
        } else {
            tabPaths = [[]]
        }

        // Pages load themselves via MiniAppPageView.onAppear
        self.runtime = rt
    }

    // MARK: - Helpers

    private func tabIconFallback(index: Int) -> String {
        let defaultIcons = ["house.fill", "list.bullet", "person.fill", "gear", "star.fill"]
        if index < defaultIcons.count {
            return defaultIcons[index]
        }
        return "\(index + 1).circle"
    }

    /// Translate text through the i18n module. If a translation exists for the key, use it;
    /// otherwise return the text as-is.
    private func localizedText(_ text: String, runtime: MiniAppRuntime) -> String {
        guard let i18n = runtime.i18nModule else { return text }
        let translated = i18n.translate(text)
        return translated
    }
}

// MARK: - MiniAppPageView

/// A SwiftUI view wrapping a single WebView for one MiniApp page.
///
/// Each page in the navigation stack gets its own instance of this view,
/// with its own WebView, Alpine.js state, and bridge connection. When the
/// view is popped from the navigation stack, the WebView is destroyed.
public struct MiniAppPageView: View {
    let pagePath: String
    let query: String
    let runtime: MiniAppRuntime
    let servingDir: URL
    let onDismiss: (() -> Void)?

    @State private var webViewState: WebViewState = WebViewState()
    @State private var navigator: WebViewNavigator = WebViewNavigator()
    @State private var pageReady: Bool = false
    @State private var pageJSLoaded: Bool = false

    public init(pagePath: String, query: String = "", runtime: MiniAppRuntime, servingDir: URL, onDismiss: (() -> Void)? = nil) {
        self.pagePath = pagePath
        self.query = query
        self.runtime = runtime
        self.servingDir = servingDir
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Group {
            if pageJSLoaded {
                WebView(
                    configuration: webViewConfiguration,
                    navigator: navigator,
                    url: pageURL,
                    state: $webViewState,
                    onNavigationFinished: {
                        if !pageReady {
                            pageReady = true
                            runtime.firePageReady(pagePath: pagePath)
                            runtime.firePageShow(pagePath: pagePath)
                        }
                    }
                )
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if !pageJSLoaded {
                // Load the page JS in the runtime (registers handlers, data, lifecycle)
                runtime.loadPage(pagePath: pagePath, query: query)
                pageJSLoaded = true
            } else if pageReady {
                runtime.firePageShow(pagePath: pagePath)
            }
        }
        .onDisappear {
            if pageReady {
                runtime.firePageHide(pagePath: pagePath)
            }
        }
        .onChange(of: runtime.pendingPageDataUpdates[pagePath]) { _, newValue in
            if let jsonPatch = newValue {
                pushDataToView(jsonPatch)
                runtime.pendingPageDataUpdates[pagePath] = nil
            }
        }
        // Also observe the legacy single-page pendingDataUpdate for backward compat
        .onChange(of: runtime.pendingDataUpdate) { _, newValue in
            if let jsonPatch = newValue, runtime.currentPage == pagePath {
                pushDataToView(jsonPatch)
                runtime.pendingDataUpdate = nil
            }
        }
        .toolbar {
            if let onDismiss = onDismiss {
                ToolbarItem(placement: .automatic) {
                    Button(action: onDismiss) {
                        Image("close-miniapp", bundle: .module)
                    }
                }
            }
        }
        .navigationTitle(pageTitle)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Resolve the navigation title for this page.
    /// Priority: JS-set title > tab text > empty.
    private var pageTitle: String {
        let i18n = runtime.i18nModule
        // Check if JS set a title for this page
        if let jsTitle = runtime.navigationModule?.pageTitles[pagePath], !jsTitle.isEmpty {
            return i18n?.translate(jsTitle) ?? jsTitle
        }
        // For tab root pages, use the tab's text
        if let tabBar = runtime.navigationModule?.tabBarConfig {
            for tab in tabBar.tabs {
                if tab.page == pagePath {
                    return i18n?.translate(tab.text) ?? tab.text
                }
            }
        }
        return ""
    }

    private var pageURL: URL {
        servingDir.appendingPathComponent(pagePath + ".html")
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

    /// JavaScript injected into this page's WebView for the View Layer.
    private var bridgeUserScript: WebViewUserScript {
        let initialData = runtime.initialDataJSON(forPage: pagePath)
        let handlerNames = runtime.pageHandlerNames(forPage: pagePath)
        let translationsJSON = runtime.i18nModule?.translationsJSON() ?? "{}"
        let activeLocale = runtime.i18nModule?.activeLocale ?? "en"

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
                    handler: function(name, detail) { window.$handler(name, detail); },
                    model: function(key) { window.$model(key, Alpine.store('page')[key]); },
        \(handlerProps)
                    init: function() {
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

        let fullScript = alpineSource + "\n" + bridgeScript
        return WebViewUserScript(source: fullScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    // MARK: - Bridge Message Handling

    @MainActor
    private func handleBridgeMessage(_ message: WebViewMessage) {
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
            if let handlerName = data["handler"] as? String {
                let eventType = data["type"] as? String ?? "tap"
                let detail = data["detail"] as? [String: Any] ?? [:]
                let fullEvent: [String: Any] = [
                    "type": eventType,
                    "detail": detail
                ]
                if let eventData = try? JSONSerialization.data(withJSONObject: fullEvent),
                   let eventJSON = String(data: eventData, encoding: .utf8) {
                    runtime.dispatchEvent(handlerName: handlerName, eventJSON: eventJSON, forPage: pagePath)
                }
            }
        case "__model":
            if let key = data["key"] as? String {
                let value = data["value"] as? String ?? ""
                runtime.updatePageData(key: key, value: value)
            }
        default:
            break
        }
    }

    /// Push a setData patch from the Logic Layer to this page's WebView.
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
