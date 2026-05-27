// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import XCTest
import OSLog
import Foundation
@testable import SkipMiniApp
import SkipMiniAppModel

#if os(iOS) || SKIP
import SkipWeb

private let e2eLogger = Logger(subsystem: "SkipMiniApp", category: "EndToEndTests")

/// End-to-end test exercising the full MiniApp stack on a real WebView host:
/// HTML + Alpine.js + bridge user script (View Layer) round-tripping with
/// `app.js` + page JS + `MiniAppRuntime` running in JavaScriptCore (Logic Layer).
///
/// Requires `WKWebView` (iOS Simulator) or `android.webkit.WebView` (connected
/// Android emulator/device); skipped on macOS hosts and Robolectric. Designed
/// for the "Test iOS (connected)" and "Test ReactiveCircus Android emulator
/// (connected)" jobs in `skip-framework.yml`.
@available(macOS 13, *)
final class MiniAppEndToEndTests: XCTestCase {

    @MainActor func testWebViewToJSCoreRoundTrip() async throws {
        if isMacOS { throw XCTSkip("requires iOS Simulator host") }
        if isRobolectric { throw XCTSkip("requires connected Android emulator/device") }

        let root = try stageMiniApp()
        defer { try? FileManager.default.removeItem(at: root) }

        let pkg = MiniAppDirectoryPackage(rootURL: root)
        let runtime = MiniAppRuntime(package: pkg, manifest: try pkg.readManifest())
        runtime.start()
        runtime.fireAppShow()

        let pagePath = "pages/index/index"
        runtime.loadPage(pagePath: pagePath)

        // Reuse the production bridge wiring: same user script the SwiftUI
        // `MiniAppPageView` builds, same dispatcher into the runtime.
        let userScript = makeMiniAppBridgeUserScript(runtime: runtime, pagePath: pagePath)
        let config = WebEngineConfiguration(
            userScripts: [userScript],
            messageHandlers: ["miniappBridge": { message in
                await dispatchMiniAppBridgeMessage(message, runtime: runtime, pagePath: pagePath)
            }]
        )
        let engine = try await makeWebEngine(config: config, runtime: runtime, pagePath: pagePath, userScript: userScript)

        // Load from a file URL: Alpine.js refuses to initialize on an
        // `about:blank` origin (it needs a real origin to access browser APIs),
        // which mirrors how production loads pages via `MiniAppPageView.pageURL`.
        let pageFileURL = root.appendingPathComponent(pagePath + ".html")
        e2eLogger.log("loading page from \(pageFileURL.path)")
        #if SKIP
        // `awaitPageLoaded` stalls on the Android WebView; rely on the poll
        // loop below as the readiness signal.
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().runOnMainSync {
            engine.webView.loadUrl(pageFileURL.absoluteString)
        }
        #else
        try await engine.load(url: pageFileURL)
        #endif

        // The page's `x-init="handler('ping')"` fires after Alpine initializes,
        // dispatching through the bridge → runtime → `Page.ping()` →
        // `setData(...)` → `runtime.pendingPageDataUpdates`.
        let update = try await waitForCondition(timeoutSeconds: 30, description: "MiniApp bridge round-trip") {
            #if SKIP
            // Sync the read: the map is mutated on the Android main looper,
            // not on the test thread that drives the poll loop.
            var result: String? = nil
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().runOnMainSync {
                result = runtime.pendingPageDataUpdates[pagePath]
            }
            return result
            #else
            return runtime.pendingPageDataUpdates[pagePath]
            #endif
        }
        e2eLogger.log("received setData payload: \(update)")
        XCTAssertTrue(update.contains("\"pinged\":true"), "expected pinged=true in: \(update)")
        XCTAssertFalse(update.contains("\"count\":0"), "expected count>0 in: \(update)")
    }

    /// Create a fresh `WebEngine` backed by a platform WebView.
    ///
    /// On iOS we let `WebEngine` create its own `WKWebView` and install the
    /// configuration's scripts/handlers via `refreshMessageHandlers` /
    /// `updateUserScripts` — the same path the production SwiftUI `WebView`
    /// view follows.
    ///
    /// On Android SkipWeb's `setupWebView` (which installs the
    /// `webkit.messageHandlers` facade and document-start user scripts) only
    /// runs from a Compose host, so we replicate it inline using the public
    /// Android / SkipWeb APIs (`addJavascriptInterface`,
    /// `WebViewCompat.addDocumentStartJavaScript`).
    @MainActor private func makeWebEngine(config: WebEngineConfiguration,
                                          runtime: MiniAppRuntime,
                                          pagePath: String,
                                          userScript: WebViewUserScript) async throws -> WebEngine {
        #if SKIP
        // WebView construction must run on the Android main looper. Skip's
        // `@MainActor` maps to `Dispatchers.Main`, which under `runTest`'s
        // `TestDispatcher` is not the Android main thread — hop via
        // `runOnMainSync` instead.
        let instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        var created: WebEngine? = nil
        instrumentation.runOnMainSync {
            let ctx = instrumentation.targetContext
            config.context = ctx
            let webView = PlatformWebView(ctx)
            webView.settings.setJavaScriptEnabled(true)
            webView.settings.setAllowFileAccess(true)
            webView.settings.setAllowContentAccess(true)

            // Bind the JavascriptInterface that the facade script routes
            // `webkit.messageHandlers.<name>.postMessage(body)` calls into.
            webView.addJavascriptInterface(AndroidTestMessageBridge(runtime: runtime, pagePath: pagePath),
                                           "skipWebAndroidMessageHandler")

            let origins: kotlin.collections.MutableSet<String> = java.util.HashSet()
            origins.add("*")
            // Facade: verbatim copy of SkipWeb's private `androidScriptMessageFacadeScript()`.
            androidx.webkit.WebViewCompat.addDocumentStartJavaScript(webView, Self.androidFacadeScript, origins)
            // User script (Alpine.js + bridge JS), wrapped to defer to
            // DOMContentLoaded so it behaves like an `atDocumentEnd`
            // WKUserScript on iOS (SkipWeb's private wrapper does the same).
            let wrapped = """
            (function () {
              if (window.top !== window.self) { return; }
              var run = function () {
                \(userScript.source)
              };
              if (document.readyState === "loading") {
                document.addEventListener("DOMContentLoaded", run, { once: true });
              } else {
                run();
              }
            })();
            """
            androidx.webkit.WebViewCompat.addDocumentStartJavaScript(webView, wrapped, origins)
            created = WebEngine(configuration: config, webView: webView)
        }
        return try XCTUnwrap(created)
        #else
        let engine = WebEngine(configuration: config)
        engine.refreshMessageHandlers()
        engine.updateUserScripts()
        return engine
        #endif
    }

    /// Poll until the closure returns a non-nil value or the timeout elapses.
    ///
    /// Uses `Thread.sleep` on Android because the test runs under
    /// `kotlinx.coroutines.test.runTest`'s virtual-time dispatcher — `Task.sleep`
    /// returns instantly there and never gives the Android main looper real
    /// time to process WebView loads and message-handler callbacks.
    @MainActor private func waitForCondition<T>(timeoutSeconds: Int,
                                                description: String,
                                                condition: () -> T?) async throws -> T {
        let timeout = Int64(timeoutSeconds) * Int64(1_000_000_000)
        let interval = Int64(200_000_000) // 200 ms
        #if SKIP
        let start = System.nanoTime()
        while System.nanoTime() - start < timeout {
            if let value = condition() { return value }
            java.lang.Thread.sleep(interval / Int64(1_000_000))
        }
        #else
        var elapsed: Int64 = 0
        while elapsed < timeout {
            if let value = condition() { return value }
            try await Task.sleep(nanoseconds: UInt64(interval))
            elapsed += interval
        }
        #endif
        XCTFail("Timed out after \(timeoutSeconds)s waiting for \(description)")
        throw E2EError.timedOut
    }

    /// Stage a minimal MiniApp on disk: manifest, `app.js`, and a single page
    /// whose `x-init="handler('ping')"` fires the bridge as soon as Alpine
    /// initializes. The `ping` handler in the page JS calls `setData(...)`,
    /// which is what populates `runtime.pendingPageDataUpdates`.
    private func stageMiniApp() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("miniapp-e2e-\(UUID().uuidString)")
        let pagesDir = root.appendingPathComponent("pages/index")
        try FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)

        try """
        {
            "app_id": "org.example.e2e",
            "name": "E2E",
            "icons": [],
            "version": { "code": 1, "name": "1.0.0" },
            "platform_version": { "min_code": 1 },
            "pages": [ "pages/index/index" ]
        }
        """.write(to: root.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        try "App({ onLaunch: function() {} });"
            .write(to: root.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)

        try """
        Page({
            data: { count: 0, pinged: false },
            ping: function(e) { this.setData({ count: this.data.count + 1, pinged: true }); }
        });
        """.write(to: pagesDir.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)

        // `x-init` is restricted to simple expressions by Alpine's CSP build —
        // no function literals, arrow functions, or statements — so keep it to
        // a single method call against the data object's `handler`.
        try """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"></head>
        <body><div x-data="page" x-init="handler('ping')"></div></body>
        </html>
        """.write(to: pagesDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        return root
    }

    #if SKIP
    /// Copied verbatim from SkipWeb's private
    /// `WebEngine.androidScriptMessageFacadeScript()`: routes
    /// `webkit.messageHandlers.<name>.postMessage(body)` calls to the
    /// `skipWebAndroidMessageHandler` JavascriptInterface.
    private static let androidFacadeScript: String = """
    (function () {
      if (!window.webkit) window.webkit = {};
      window.webkit.messageHandlers = new Proxy(window.webkit.messageHandlers || {}, {
        get: function (target, name) {
          if (target && target[name]) { return target[name]; }
          return {
            postMessage: function (body) {
              var json = JSON.stringify(body);
              if (json === undefined) { json = "null"; }
              var src = ""; var mainFrame = false;
              try { src = window.location.href || ""; } catch (e) {}
              try { mainFrame = window.top === window.self; } catch (e) {}
              skipWebAndroidMessageHandler.postMessage(String(name), json, src, mainFrame);
            }
          };
        }
      });
    })();
    """
    #endif
}

private enum E2EError: Error { case timedOut }

#if SKIP
/// JavascriptInterface stand-in for SkipWeb's internal `MessageHandlerRouter`.
/// Must be `public final class` with `public` methods so Android's reflection
/// in `addJavascriptInterface` can reach the `@JavascriptInterface` method —
/// Kotlin `internal` is silently invisible to that lookup.
public final class AndroidTestMessageBridge {
    public let runtime: MiniAppRuntime
    public let pagePath: String
    public init(runtime: MiniAppRuntime, pagePath: String) {
        self.runtime = runtime
        self.pagePath = pagePath
    }

    // SKIP INSERT: @android.webkit.JavascriptInterface
    public func postMessage(_ name: String, _ bodyJSON: String, _ sourceURL: String, _ isMainFrame: Bool) {
        guard name == "miniappBridge",
              let bodyData = bodyJSON.data(using: .utf8),
              // SKIP NOWARN
              let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
            return
        }
        // `Task { @MainActor }` doesn't actually drive the Android main looper
        // under `runTest`; hop synchronously so the dispatch lands in test time.
        let runtime = self.runtime
        let pagePath = self.pagePath
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().runOnMainSync {
            dispatchMiniAppBridgeJSON(json, runtime: runtime, pagePath: pagePath)
        }
    }
}
#endif

#endif // os(iOS) || SKIP

#endif // !SKIP_BRIDGE
