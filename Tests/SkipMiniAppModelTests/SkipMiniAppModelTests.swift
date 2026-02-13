// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import XCTest
import OSLog
import Foundation
@testable import SkipMiniAppModel

let logger: Logger = Logger(subsystem: "SkipMiniAppModel", category: "Tests")

@available(macOS 13, *)
final class SkipMiniAppModelTests: XCTestCase {

    // MARK: - Manifest Parsing Tests

    func testParseMinimalManifest() throws {
        let json = """
        {
            "appID": "com.example.test",
            "appName": "Test App",
            "icons": [{"src": "icon.png", "sizes": "48x48"}],
            "versionName": "1.0.0",
            "minPlatformVersion": "1.0.0",
            "pages": ["pages/index/index"]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        XCTAssertEqual(manifest.appID, "com.example.test")
        XCTAssertEqual(manifest.appName, "Test App")
        XCTAssertEqual(manifest.versionName, "1.0.0")
        XCTAssertEqual(manifest.minPlatformVersion, "1.0.0")
        XCTAssertEqual(manifest.pages.count, 1)
        XCTAssertEqual(manifest.pages[0], "pages/index/index")
        XCTAssertEqual(manifest.icons.count, 1)
        XCTAssertEqual(manifest.icons[0].src, "icon.png")
        XCTAssertEqual(manifest.icons[0].sizes, "48x48")
        XCTAssertNil(manifest.shortName)
        XCTAssertNil(manifest.description)
        XCTAssertNil(manifest.versionCode)
        XCTAssertNil(manifest.window)
        XCTAssertNil(manifest.widgets)
        XCTAssertNil(manifest.reqPermissions)
    }

    func testParseFullManifest() throws {
        let json = """
        {
            "appID": "com.example.full",
            "appName": "Full Test App",
            "shortName": "Full",
            "description": "A fully configured MiniApp",
            "icons": [
                {"src": "icon-small.png", "sizes": "48x48"},
                {"src": "icon-large.png", "sizes": "192x192"}
            ],
            "versionName": "2.1.0",
            "versionCode": 5,
            "minPlatformVersion": "1.2.0",
            "pages": ["pages/index/index", "pages/detail/detail", "pages/settings/settings"],
            "dir": "ltr",
            "lang": "en-US",
            "window": {
                "navigationBarBackgroundColor": "#FF5733",
                "navigationBarTextStyle": "white",
                "navigationBarTitleText": "My App",
                "navigationStyle": "default",
                "backgroundColor": "#FFFFFF",
                "backgroundTextStyle": "dark",
                "enablePullDownRefresh": true,
                "onReachBottomDistance": 100,
                "orientation": "portrait",
                "fullscreen": false,
                "designWidth": 750,
                "autoDesignWidth": true
            },
            "widgets": [
                {"name": "Weather", "path": "widgets/weather/weather", "minPlatformVersion": "1.1.0"},
                {"name": "Calendar", "path": "widgets/calendar/calendar"}
            ],
            "req-permissions": [
                {"name": "location", "reason": "For navigation features"},
                {"name": "camera", "reason": "For photo capture"}
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        XCTAssertEqual(manifest.appID, "com.example.full")
        XCTAssertEqual(manifest.appName, "Full Test App")
        XCTAssertEqual(manifest.shortName, "Full")
        XCTAssertEqual(manifest.description, "A fully configured MiniApp")
        XCTAssertEqual(manifest.icons.count, 2)
        XCTAssertEqual(manifest.versionName, "2.1.0")
        XCTAssertEqual(manifest.versionCode, 5)
        XCTAssertEqual(manifest.minPlatformVersion, "1.2.0")
        XCTAssertEqual(manifest.pages.count, 3)
        XCTAssertEqual(manifest.dir, "ltr")
        XCTAssertEqual(manifest.lang, "en-US")
    }

    func testManifestWindowConfig() throws {
        let json = """
        {
            "appID": "com.example.win",
            "appName": "Window Test",
            "icons": [{"src": "i.png", "sizes": "48x48"}],
            "versionName": "1.0.0",
            "minPlatformVersion": "1.0.0",
            "pages": ["pages/index/index"],
            "window": {
                "navigationBarBackgroundColor": "#123456",
                "navigationBarTextStyle": "black",
                "navigationBarTitleText": "Custom Title",
                "navigationStyle": "custom",
                "backgroundColor": "#ABCDEF",
                "enablePullDownRefresh": true,
                "orientation": "landscape",
                "fullscreen": true,
                "designWidth": 1080
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)
        let window = try XCTUnwrap(manifest.window)

        XCTAssertEqual(window.navigationBarBackgroundColor, "#123456")
        XCTAssertEqual(window.navigationBarTextStyle, "black")
        XCTAssertEqual(window.navigationBarTitleText, "Custom Title")
        XCTAssertEqual(window.navigationStyle, "custom")
        XCTAssertEqual(window.backgroundColor, "#ABCDEF")
        XCTAssertEqual(window.enablePullDownRefresh, true)
        XCTAssertEqual(window.orientation, "landscape")
        XCTAssertEqual(window.fullscreen, true)
        XCTAssertEqual(window.designWidth, 1080)
    }

    func testManifestWidgets() throws {
        let json = """
        {
            "appID": "com.example.widgets",
            "appName": "Widget Test",
            "icons": [{"src": "i.png", "sizes": "48x48"}],
            "versionName": "1.0.0",
            "minPlatformVersion": "1.0.0",
            "pages": ["pages/index/index"],
            "widgets": [
                {"name": "Clock", "path": "widgets/clock/clock", "minPlatformVersion": "2.0.0"},
                {"name": "Notes", "path": "widgets/notes/notes"}
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)
        let widgets = try XCTUnwrap(manifest.widgets)

        XCTAssertEqual(widgets.count, 2)
        XCTAssertEqual(widgets[0].name, "Clock")
        XCTAssertEqual(widgets[0].path, "widgets/clock/clock")
        XCTAssertEqual(widgets[0].minPlatformVersion, "2.0.0")
        XCTAssertEqual(widgets[1].name, "Notes")
        XCTAssertNil(widgets[1].minPlatformVersion)
    }

    func testManifestPermissions() throws {
        let json = """
        {
            "appID": "com.example.perms",
            "appName": "Permission Test",
            "icons": [{"src": "i.png", "sizes": "48x48"}],
            "versionName": "1.0.0",
            "minPlatformVersion": "1.0.0",
            "pages": ["pages/index/index"],
            "req-permissions": [
                {"name": "location", "reason": "Navigation"},
                {"name": "camera"}
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)
        let perms = try XCTUnwrap(manifest.reqPermissions)

        XCTAssertEqual(perms.count, 2)
        XCTAssertEqual(perms[0].name, "location")
        XCTAssertEqual(perms[0].reason, "Navigation")
        XCTAssertEqual(perms[1].name, "camera")
        XCTAssertNil(perms[1].reason)
    }

    func testManifestEncodingRoundtrip() throws {
        let original = MiniAppManifest(
            appID: "com.example.roundtrip",
            appName: "Roundtrip Test",
            shortName: "RT",
            description: "Testing encode/decode roundtrip",
            icons: [MiniAppIcon(src: "icon.png", sizes: "64x64")],
            versionName: "3.0.0",
            versionCode: 10,
            minPlatformVersion: "2.0.0",
            pages: ["pages/home/home", "pages/about/about"],
            dir: "ltr",
            lang: "en",
            window: MiniAppWindow(
                navigationBarBackgroundColor: "#000000",
                navigationBarTextStyle: "white",
                orientation: "portrait"
            ),
            widgets: [MiniAppWidget(name: "Status", path: "widgets/status/status")],
            reqPermissions: [MiniAppPermission(name: "contacts", reason: "Sync")]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testManifestInitDefaults() throws {
        let manifest = MiniAppManifest(
            appID: "com.example.defaults",
            appName: "Defaults",
            versionName: "1.0.0",
            minPlatformVersion: "1.0.0"
        )

        XCTAssertEqual(manifest.appID, "com.example.defaults")
        XCTAssertEqual(manifest.icons.count, 0)
        XCTAssertEqual(manifest.pages.count, 0)
        XCTAssertNil(manifest.shortName)
        XCTAssertNil(manifest.window)
    }

    // MARK: - Package Tests

    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SkipMiniAppTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createSamplePackage(at path: String) throws -> MiniAppManifest {
        let manifest = MiniAppManifest(
            appID: "com.example.sample",
            appName: "Sample MiniApp",
            icons: [MiniAppIcon(src: "icon.png", sizes: "48x48")],
            versionName: "1.0.0",
            minPlatformVersion: "1.0.0",
            pages: ["pages/index/index"]
        )

        let builder = try MiniAppPackageBuilder(path: path)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js", string: "console.log('app started');", compression: 0)
        try builder.addEntry(path: "app.css", string: "body { margin: 0; }", compression: 0)
        try builder.addEntry(path: "pages/index/index.html", string: "<html><body>Hello</body></html>", compression: 0)
        try builder.addEntry(path: "pages/index/index.css", string: "h1 { color: blue; }", compression: 0)
        try builder.addEntry(path: "pages/index/index.js", string: "console.log('index page');", compression: 0)
        try builder.finalize()

        return manifest
    }

    func testReadManifestFromPackage() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("test.ma").path
        let expectedManifest = try createSamplePackage(at: pkgPath)

        let package = MiniAppPackage(path: pkgPath)
        let manifest = try package.readManifest()

        XCTAssertEqual(manifest.appID, expectedManifest.appID)
        XCTAssertEqual(manifest.appName, expectedManifest.appName)
        XCTAssertEqual(manifest.versionName, expectedManifest.versionName)
        XCTAssertEqual(manifest.pages, expectedManifest.pages)
    }

    func testListPackageEntries() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("test.ma").path
        let _ = try createSamplePackage(at: pkgPath)

        let package = MiniAppPackage(path: pkgPath)
        let entries = try package.listEntries()

        XCTAssertEqual(entries.count, 6)
        // Sort for deterministic checking
        let sorted = entries.sorted()
        XCTAssertEqual(sorted[0], "app.css")
        XCTAssertEqual(sorted[1], "app.js")
        XCTAssertEqual(sorted[2], "manifest.json")
        XCTAssertEqual(sorted[3], "pages/index/index.css")
        XCTAssertEqual(sorted[4], "pages/index/index.html")
        XCTAssertEqual(sorted[5], "pages/index/index.js")
    }

    func testReadPackageEntry() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("test.ma").path
        let _ = try createSamplePackage(at: pkgPath)

        let package = MiniAppPackage(path: pkgPath)

        let jsData = try XCTUnwrap(package.readAppJS())
        let jsString = try XCTUnwrap(String(data: jsData, encoding: .utf8))
        XCTAssertEqual(jsString, "console.log('app started');")

        let cssData = try XCTUnwrap(package.readAppCSS())
        let cssString = try XCTUnwrap(String(data: cssData, encoding: .utf8))
        XCTAssertEqual(cssString, "body { margin: 0; }")
    }

    func testReadPageResources() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("test.ma").path
        let _ = try createSamplePackage(at: pkgPath)

        let package = MiniAppPackage(path: pkgPath)

        let htmlData = try XCTUnwrap(package.readPageHTML(pagePath: "pages/index/index"))
        let htmlString = try XCTUnwrap(String(data: htmlData, encoding: .utf8))
        XCTAssertEqual(htmlString, "<html><body>Hello</body></html>")

        let cssData = try XCTUnwrap(package.readPageCSS(pagePath: "pages/index/index"))
        let cssString = try XCTUnwrap(String(data: cssData, encoding: .utf8))
        XCTAssertEqual(cssString, "h1 { color: blue; }")

        let jsData = try XCTUnwrap(package.readPageJS(pagePath: "pages/index/index"))
        let jsString = try XCTUnwrap(String(data: jsData, encoding: .utf8))
        XCTAssertEqual(jsString, "console.log('index page');")
    }

    func testReadMissingEntry() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("test.ma").path
        let _ = try createSamplePackage(at: pkgPath)

        let package = MiniAppPackage(path: pkgPath)
        let result = try package.readEntry(at: "nonexistent.txt")
        XCTAssertNil(result)
    }

    func testMissingManifestError() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("nomanifest.ma").path
        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addEntry(path: "app.js", string: "// no manifest", compression: 0)
        try builder.finalize()

        let package = MiniAppPackage(path: pkgPath)
        do {
            let _ = try package.readManifest()
            XCTFail("Expected error for missing manifest")
        } catch {
            // Expected: missing manifest error
            logger.log("Got expected error: \(error)")
        }
    }

    func testCannotOpenPackage() throws {
        let package = MiniAppPackage(path: "/nonexistent/path/test.ma")
        do {
            let _ = try package.readManifest()
            XCTFail("Expected error for nonexistent package")
        } catch {
            // Expected: cannot open package error
            logger.log("Got expected error: \(error)")
        }
    }

    func testExtractPackageToDirectory() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("test.ma").path
        let _ = try createSamplePackage(at: pkgPath)

        let extractDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let package = MiniAppPackage(path: pkgPath)
        try package.extractToDirectory(at: extractDir.path)

        // Verify extracted files exist
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: extractDir.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(fm.fileExists(atPath: extractDir.appendingPathComponent("app.js").path))
        XCTAssertTrue(fm.fileExists(atPath: extractDir.appendingPathComponent("app.css").path))
        XCTAssertTrue(fm.fileExists(atPath: extractDir.appendingPathComponent("pages/index/index.html").path))

        // Verify content
        let jsContent = try String(contentsOf: extractDir.appendingPathComponent("app.js"), encoding: .utf8)
        XCTAssertEqual(jsContent, "console.log('app started');")
    }

    func testPackageStaticProperties() throws {
        XCTAssertEqual(MiniAppPackage.mimeType, "application/miniapp-pkg+zip")
        XCTAssertEqual(MiniAppPackage.fileExtension, "ma")
        XCTAssertEqual(MiniAppPackage.manifestPath, "manifest.json")
        XCTAssertEqual(MiniAppPackage.appJSPath, "app.js")
        XCTAssertEqual(MiniAppPackage.appCSSPath, "app.css")
        XCTAssertEqual(MiniAppPackage.pagesDirectory, "pages/")
        XCTAssertEqual(MiniAppPackage.commonDirectory, "common/")
        XCTAssertEqual(MiniAppPackage.i18nDirectory, "i18n/")
    }

    func testManifestCaching() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("test.ma").path
        let _ = try createSamplePackage(at: pkgPath)

        let package = MiniAppPackage(path: pkgPath)
        let manifest1 = try package.readManifest()
        let manifest2 = try package.readManifest()

        XCTAssertEqual(manifest1, manifest2)
    }

    // MARK: - Lifecycle Tests

    func testGlobalLifecycleInitialState() throws {
        let lifecycle = MiniAppLifecycle()
        XCTAssertEqual(lifecycle.globalState, .launched)
        XCTAssertNil(lifecycle.currentError)
    }

    func testGlobalLifecycleTransitions() throws {
        let lifecycle = MiniAppLifecycle()

        XCTAssertEqual(lifecycle.globalState, .launched)

        lifecycle.show()
        XCTAssertEqual(lifecycle.globalState, .shown)

        lifecycle.hide()
        XCTAssertEqual(lifecycle.globalState, .hidden)

        lifecycle.show()
        XCTAssertEqual(lifecycle.globalState, .shown)

        lifecycle.hide()
        XCTAssertEqual(lifecycle.globalState, .hidden)

        lifecycle.unload()
        XCTAssertEqual(lifecycle.globalState, .unloaded)
    }

    func testGlobalLifecycleError() throws {
        let lifecycle = MiniAppLifecycle()

        lifecycle.fail(error: MiniAppError.resourceNotFound)

        XCTAssertEqual(lifecycle.globalState, .error)
        XCTAssertNotNil(lifecycle.currentError)

        // Can recover from error
        lifecycle.show()
        XCTAssertEqual(lifecycle.globalState, .shown)
    }

    func testGlobalLifecycleRelaunch() throws {
        let lifecycle = MiniAppLifecycle()

        lifecycle.show()
        lifecycle.hide()
        lifecycle.launch()

        XCTAssertEqual(lifecycle.globalState, .launched)
        XCTAssertNil(lifecycle.currentError)
    }

    func testPageLifecycleInitialState() throws {
        let page = MiniAppPageLifecycle()
        XCTAssertEqual(page.pageState, .loaded)
    }

    func testPageLifecycleTransitions() throws {
        let page = MiniAppPageLifecycle()

        XCTAssertEqual(page.pageState, .loaded)

        page.ready()
        XCTAssertEqual(page.pageState, .ready)

        page.show()
        XCTAssertEqual(page.pageState, .shown)

        page.hide()
        XCTAssertEqual(page.pageState, .hidden)

        page.show()
        XCTAssertEqual(page.pageState, .shown)

        page.unload()
        XCTAssertEqual(page.pageState, .unloaded)
    }

    func testPageLifecycleReload() throws {
        let page = MiniAppPageLifecycle()

        page.ready()
        page.show()
        page.hide()
        page.load()

        XCTAssertEqual(page.pageState, .loaded)
    }

    func testAllGlobalStates() throws {
        // Verify all five states are distinct
        let states: [MiniAppGlobalState] = [.launched, .shown, .hidden, .error, .unloaded]
        XCTAssertEqual(states.count, 5)
        XCTAssertNotEqual(MiniAppGlobalState.launched, MiniAppGlobalState.shown)
        XCTAssertNotEqual(MiniAppGlobalState.shown, MiniAppGlobalState.hidden)
        XCTAssertNotEqual(MiniAppGlobalState.hidden, MiniAppGlobalState.error)
        XCTAssertNotEqual(MiniAppGlobalState.error, MiniAppGlobalState.unloaded)
    }

    func testAllPageStates() throws {
        // Verify all five states are distinct
        let states: [MiniAppPageState] = [.loaded, .ready, .shown, .hidden, .unloaded]
        XCTAssertEqual(states.count, 5)
        XCTAssertNotEqual(MiniAppPageState.loaded, MiniAppPageState.ready)
        XCTAssertNotEqual(MiniAppPageState.ready, MiniAppPageState.shown)
        XCTAssertNotEqual(MiniAppPageState.shown, MiniAppPageState.hidden)
        XCTAssertNotEqual(MiniAppPageState.hidden, MiniAppPageState.unloaded)
    }

    func testGlobalStateRawValues() throws {
        XCTAssertEqual(MiniAppGlobalState.launched.rawValue, "launched")
        XCTAssertEqual(MiniAppGlobalState.shown.rawValue, "shown")
        XCTAssertEqual(MiniAppGlobalState.hidden.rawValue, "hidden")
        XCTAssertEqual(MiniAppGlobalState.error.rawValue, "error")
        XCTAssertEqual(MiniAppGlobalState.unloaded.rawValue, "unloaded")
    }

    func testPageStateRawValues() throws {
        XCTAssertEqual(MiniAppPageState.loaded.rawValue, "loaded")
        XCTAssertEqual(MiniAppPageState.ready.rawValue, "ready")
        XCTAssertEqual(MiniAppPageState.shown.rawValue, "shown")
        XCTAssertEqual(MiniAppPageState.hidden.rawValue, "hidden")
        XCTAssertEqual(MiniAppPageState.unloaded.rawValue, "unloaded")
    }

    // MARK: - URI Tests

    func testParseMiniAppURI() throws {
        let uri = try XCTUnwrap(MiniAppURI.parse("miniapp://example.com/com.example.app"))
        XCTAssertEqual(uri.appID, "com.example.app")
        XCTAssertEqual(uri.host, "example.com")
        XCTAssertNil(uri.version)
        XCTAssertNil(uri.path)
        XCTAssertNil(uri.query)
        XCTAssertNil(uri.fragment)
    }

    func testParseMiniAppURIWithVersion() throws {
        let uri = try XCTUnwrap(MiniAppURI.parse("miniapp://example.com/com.example.app;version=2.0.0"))
        XCTAssertEqual(uri.appID, "com.example.app")
        XCTAssertEqual(uri.version, "2.0.0")
        XCTAssertNil(uri.path)
    }

    func testParseMiniAppURIWithPath() throws {
        let uri = try XCTUnwrap(MiniAppURI.parse("miniapp://example.com/com.example.app/pages/index"))
        XCTAssertEqual(uri.appID, "com.example.app")
        XCTAssertEqual(uri.path, "pages/index")
    }

    func testParseMiniAppURIWithVersionAndPath() throws {
        let uri = try XCTUnwrap(MiniAppURI.parse("miniapp://example.com/com.example.app;version=1.0.0/pages/detail"))
        XCTAssertEqual(uri.appID, "com.example.app")
        XCTAssertEqual(uri.version, "1.0.0")
        XCTAssertEqual(uri.path, "pages/detail")
    }

    func testParseMiniAppURIWithQuery() throws {
        let uri = try XCTUnwrap(MiniAppURI.parse("miniapp://example.com/com.example.app/pages/search?q=hello"))
        XCTAssertEqual(uri.appID, "com.example.app")
        XCTAssertEqual(uri.path, "pages/search")
        XCTAssertEqual(uri.query, "q=hello")
    }

    func testParseMiniAppURIWithFragment() throws {
        let uri = try XCTUnwrap(MiniAppURI.parse("miniapp://example.com/com.example.app/pages/index#section1"))
        XCTAssertEqual(uri.appID, "com.example.app")
        XCTAssertEqual(uri.path, "pages/index")
        XCTAssertEqual(uri.fragment, "section1")
    }

    func testParseHTTPSMiniAppURI() throws {
        let uri = try XCTUnwrap(MiniAppURI.parse("https://platform.example.com/com.example.app;version=1.0.0/pages/index"))
        XCTAssertEqual(uri.appID, "com.example.app")
        XCTAssertEqual(uri.version, "1.0.0")
        XCTAssertEqual(uri.path, "pages/index")
        XCTAssertEqual(uri.host, "platform.example.com")
    }

    func testParseInvalidURIScheme() throws {
        let result = MiniAppURI.parse("ftp://example.com/com.example.app")
        XCTAssertNil(result)
    }

    func testParseInvalidURINoPath() throws {
        let result = MiniAppURI.parse("miniapp://example.com")
        XCTAssertNil(result)
    }

    func testParseMalformedURI() throws {
        let result = MiniAppURI.parse("not a uri at all")
        XCTAssertNil(result)
    }

    func testURIRoundtrip() throws {
        let original = MiniAppURI(
            appID: "com.example.roundtrip",
            version: "3.0.0",
            path: "pages/home",
            query: "tab=1",
            fragment: "top",
            host: "example.com"
        )

        let uriString = original.toURIString()
        let parsed = try XCTUnwrap(MiniAppURI.parse(uriString))

        XCTAssertEqual(parsed.appID, original.appID)
        XCTAssertEqual(parsed.version, original.version)
        XCTAssertEqual(parsed.path, original.path)
        XCTAssertEqual(parsed.query, original.query)
        XCTAssertEqual(parsed.fragment, original.fragment)
    }

    func testURIToString() throws {
        let uri = MiniAppURI(appID: "com.example.test", host: "example.com")
        XCTAssertEqual(uri.toURIString(), "miniapp://example.com/com.example.test")

        let uriWithVersion = MiniAppURI(appID: "com.example.test", version: "1.0.0", host: "example.com")
        XCTAssertEqual(uriWithVersion.toURIString(), "miniapp://example.com/com.example.test;version=1.0.0")
    }

    func testURIHashable() throws {
        let uri1 = MiniAppURI(appID: "com.example.a", version: "1.0.0")
        let uri2 = MiniAppURI(appID: "com.example.a", version: "1.0.0")
        let uri3 = MiniAppURI(appID: "com.example.b", version: "1.0.0")

        XCTAssertEqual(uri1, uri2)
        XCTAssertNotEqual(uri1, uri3)

        var set: Set<MiniAppURI> = []
        set.insert(uri1)
        set.insert(uri2)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Multi-page Package Test

    func testMultiPagePackage() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("multipage.ma").path
        let manifest = MiniAppManifest(
            appID: "com.example.multipage",
            appName: "Multi-Page App",
            icons: [MiniAppIcon(src: "icon.png", sizes: "48x48")],
            versionName: "1.0.0",
            minPlatformVersion: "1.0.0",
            pages: ["pages/home/home", "pages/settings/settings", "pages/about/about"]
        )

        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js", string: "// app", compression: 0)
        try builder.addEntry(path: "app.css", string: "/* app */", compression: 0)
        try builder.addEntry(path: "pages/home/home.html", string: "<html><body>Home</body></html>", compression: 0)
        try builder.addEntry(path: "pages/home/home.css", string: ".home {}", compression: 0)
        try builder.addEntry(path: "pages/home/home.js", string: "// home", compression: 0)
        try builder.addEntry(path: "pages/settings/settings.html", string: "<html><body>Settings</body></html>", compression: 0)
        try builder.addEntry(path: "pages/settings/settings.js", string: "// settings", compression: 0)
        try builder.addEntry(path: "pages/about/about.html", string: "<html><body>About</body></html>", compression: 0)
        try builder.finalize()

        let package = MiniAppPackage(path: pkgPath)
        let loaded = try package.readManifest()
        XCTAssertEqual(loaded.pages.count, 3)

        // Verify each page
        for pagePath in loaded.pages {
            let html = try package.readPageHTML(pagePath: pagePath)
            XCTAssertNotNil(html, "HTML should exist for page: \(pagePath)")
        }

        // Verify page content
        let homeHTML = try XCTUnwrap(package.readPageHTML(pagePath: "pages/home/home"))
        XCTAssertEqual(String(data: homeHTML, encoding: .utf8), "<html><body>Home</body></html>")

        let settingsHTML = try XCTUnwrap(package.readPageHTML(pagePath: "pages/settings/settings"))
        XCTAssertEqual(String(data: settingsHTML, encoding: .utf8), "<html><body>Settings</body></html>")
    }
}
