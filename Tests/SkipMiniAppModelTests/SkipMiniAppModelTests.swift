// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

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
            "app_id": "com.example.test",
            "name": "Test App",
            "icons": [{"src": "icon.png", "sizes": "48x48"}],
            "version": {"code": 1, "name": "1.0.0"},
            "platform_version": {"min_code": 1},
            "pages": ["pages/index/index"]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        XCTAssertEqual(manifest.appId, "com.example.test")
        XCTAssertEqual(manifest.name, "Test App")
        XCTAssertEqual(manifest.version.code, 1)
        XCTAssertEqual(manifest.version.name, "1.0.0")
        XCTAssertEqual(manifest.platformVersion.minCode, 1)
        XCTAssertNil(manifest.platformVersion.targetCode)
        XCTAssertNil(manifest.platformVersion.releaseType)
        XCTAssertEqual(manifest.pages.count, 1)
        XCTAssertEqual(manifest.pages[0], "pages/index/index")
        XCTAssertEqual(manifest.icons.count, 1)
        XCTAssertEqual(manifest.icons[0].src, "icon.png")
        XCTAssertEqual(manifest.icons[0].sizes, "48x48")
        XCTAssertNil(manifest.icons[0].label)
        XCTAssertNil(manifest.shortName)
        XCTAssertNil(manifest.description)
        XCTAssertNil(manifest.colorScheme)
        XCTAssertNil(manifest.deviceType)
        XCTAssertNil(manifest.window)
        XCTAssertNil(manifest.widgets)
        XCTAssertNil(manifest.reqPermissions)
    }

    func testParseFullManifest() throws {
        let json = """
        {
            "app_id": "com.example.full",
            "name": "Full Test App",
            "short_name": "Full",
            "description": "A fully configured MiniApp",
            "icons": [
                {"src": "icon-small.png", "sizes": "48x48", "label": "Small icon"},
                {"src": "icon-large.png", "sizes": "192x192"}
            ],
            "version": {"code": 5, "name": "2.1.0"},
            "platform_version": {"min_code": 2, "target_code": 5, "release_type": "Release"},
            "pages": ["pages/index/index", "pages/detail/detail", "pages/settings/settings"],
            "dir": "ltr",
            "lang": "en-US",
            "color_scheme": "auto",
            "device_type": ["phone", "tablet"],
            "window": {
                "navigation_bar_background_color": "#FF5733",
                "navigation_bar_text_style": "white",
                "navigation_bar_title_text": "My App",
                "navigation_style": "default",
                "background_color": "#FFFFFF",
                "background_text_style": "dark",
                "enable_pull_down_refresh": true,
                "on_reach_bottom_distance": 100,
                "orientation": "portrait",
                "fullscreen": false,
                "design_width": 750,
                "auto_design_width": true
            },
            "widgets": [
                {"name": "Weather", "path": "widgets/weather/weather", "min_code": 3},
                {"name": "Calendar", "path": "widgets/calendar/calendar"}
            ],
            "req_permissions": [
                {"name": "location", "reason": "For navigation features"},
                {"name": "camera", "reason": "For photo capture"}
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        XCTAssertEqual(manifest.appId, "com.example.full")
        XCTAssertEqual(manifest.name, "Full Test App")
        XCTAssertEqual(manifest.shortName, "Full")
        XCTAssertEqual(manifest.description, "A fully configured MiniApp")
        XCTAssertEqual(manifest.icons.count, 2)
        XCTAssertEqual(manifest.icons[0].label, "Small icon")
        XCTAssertNil(manifest.icons[1].label)
        XCTAssertEqual(manifest.version.code, 5)
        XCTAssertEqual(manifest.version.name, "2.1.0")
        XCTAssertEqual(manifest.platformVersion.minCode, 2)
        XCTAssertEqual(manifest.platformVersion.targetCode, 5)
        XCTAssertEqual(manifest.platformVersion.releaseType, "Release")
        XCTAssertEqual(manifest.pages.count, 3)
        XCTAssertEqual(manifest.dir, "ltr")
        XCTAssertEqual(manifest.lang, "en-US")
        XCTAssertEqual(manifest.colorScheme, "auto")
        XCTAssertEqual(manifest.deviceType?.count, 2)
    }

    func testManifestWindowConfig() throws {
        let json = """
        {
            "app_id": "com.example.win",
            "name": "Window Test",
            "icons": [{"src": "i.png"}],
            "version": {"code": 1, "name": "1.0.0"},
            "platform_version": {"min_code": 1},
            "pages": ["pages/index/index"],
            "window": {
                "navigation_bar_background_color": "#123456",
                "navigation_bar_text_style": "black",
                "navigation_bar_title_text": "Custom Title",
                "navigation_style": "custom",
                "background_color": "#ABCDEF",
                "enable_pull_down_refresh": true,
                "orientation": "landscape",
                "fullscreen": true,
                "design_width": 1080
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
            "app_id": "com.example.widgets",
            "name": "Widget Test",
            "icons": [{"src": "i.png"}],
            "version": {"code": 1, "name": "1.0.0"},
            "platform_version": {"min_code": 1},
            "pages": ["pages/index/index"],
            "widgets": [
                {"name": "Clock", "path": "widgets/clock/clock", "min_code": 3},
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
        XCTAssertEqual(widgets[0].minCode, 3)
        XCTAssertEqual(widgets[1].name, "Notes")
        XCTAssertNil(widgets[1].minCode)
    }

    func testManifestPermissions() throws {
        let json = """
        {
            "app_id": "com.example.perms",
            "name": "Permission Test",
            "icons": [{"src": "i.png"}],
            "version": {"code": 1, "name": "1.0.0"},
            "platform_version": {"min_code": 1},
            "pages": ["pages/index/index"],
            "req_permissions": [
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
            appId: "com.example.roundtrip",
            name: "Roundtrip Test",
            shortName: "RT",
            description: "Testing encode/decode roundtrip",
            icons: [MiniAppIcon(src: "icon.png", sizes: "64x64")],
            version: MiniAppVersion(code: 10, name: "3.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 2, targetCode: 5, releaseType: "Release"),
            pages: ["pages/home/home", "pages/about/about"],
            dir: "ltr",
            lang: "en",
            colorScheme: "dark",
            deviceType: ["phone"],
            window: MiniAppWindow(
                navigationBarBackgroundColor: "#000000",
                navigationBarTextStyle: "white",
                orientation: "portrait"
            ),
            widgets: [MiniAppWidget(name: "Status", path: "widgets/status/status", minCode: 2)],
            reqPermissions: [MiniAppPermission(name: "contacts", reason: "Sync")]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testManifestInitDefaults() throws {
        let manifest = MiniAppManifest(
            appId: "com.example.defaults",
            name: "Defaults",
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1)
        )

        XCTAssertEqual(manifest.appId, "com.example.defaults")
        XCTAssertEqual(manifest.icons.count, 0)
        XCTAssertEqual(manifest.pages.count, 0)
        XCTAssertNil(manifest.shortName)
        XCTAssertNil(manifest.colorScheme)
        XCTAssertNil(manifest.deviceType)
        XCTAssertNil(manifest.window)
    }

    func testVersionResource() throws {
        let json = """
        {"code": 42, "name": "4.2.0"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let version = try JSONDecoder().decode(MiniAppVersion.self, from: data)
        XCTAssertEqual(version.code, 42)
        XCTAssertEqual(version.name, "4.2.0")
    }

    func testPlatformVersionResource() throws {
        let json = """
        {"min_code": 3, "target_code": 7, "release_type": "Beta1"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let pv = try JSONDecoder().decode(MiniAppPlatformVersion.self, from: data)
        XCTAssertEqual(pv.minCode, 3)
        XCTAssertEqual(pv.targetCode, 7)
        XCTAssertEqual(pv.releaseType, "Beta1")
    }

    func testPlatformVersionMinimalResource() throws {
        let json = """
        {"min_code": 1}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let pv = try JSONDecoder().decode(MiniAppPlatformVersion.self, from: data)
        XCTAssertEqual(pv.minCode, 1)
        XCTAssertNil(pv.targetCode)
        XCTAssertNil(pv.releaseType)
    }

    func testIconWithLabel() throws {
        let json = """
        {"src": "logo.png", "sizes": "120x120", "label": "App Logo"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let icon = try JSONDecoder().decode(MiniAppIcon.self, from: data)
        XCTAssertEqual(icon.src, "logo.png")
        XCTAssertEqual(icon.sizes, "120x120")
        XCTAssertEqual(icon.label, "App Logo")
    }

    func testIconMinimal() throws {
        let json = """
        {"src": "logo.png"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let icon = try JSONDecoder().decode(MiniAppIcon.self, from: data)
        XCTAssertEqual(icon.src, "logo.png")
        XCTAssertNil(icon.sizes)
        XCTAssertNil(icon.label)
    }

    func testManifestSnakeCaseJsonKeys() throws {
        // Verify that encoding produces the correct snake_case JSON keys
        let manifest = MiniAppManifest(
            appId: "com.example.keys",
            name: "Key Test",
            shortName: "KT",
            icons: [MiniAppIcon(src: "i.png")],
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1),
            pages: ["pages/index/index"],
            colorScheme: "light",
            deviceType: ["phone"],
            reqPermissions: [MiniAppPermission(name: "location")]
        )

        let data = try JSONEncoder().encode(manifest)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))

        // The JSON should use snake_case keys per the W3C spec
        XCTAssertTrue(jsonString.range(of: "\"app_id\"") != nil)
        XCTAssertTrue(jsonString.range(of: "\"short_name\"") != nil)
        XCTAssertTrue(jsonString.range(of: "\"platform_version\"") != nil)
        XCTAssertTrue(jsonString.range(of: "\"color_scheme\"") != nil)
        XCTAssertTrue(jsonString.range(of: "\"device_type\"") != nil)
        XCTAssertTrue(jsonString.range(of: "\"req_permissions\"") != nil)
    }

    func testWindowSnakeCaseJsonKeys() throws {
        let window = MiniAppWindow(
            navigationBarBackgroundColor: "#000000",
            enablePullDownRefresh: true,
            designWidth: 750,
            autoDesignWidth: false
        )

        let data = try JSONEncoder().encode(window)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(jsonString.range(of: "\"navigation_bar_background_color\"") != nil)
        XCTAssertTrue(jsonString.range(of: "\"enable_pull_down_refresh\"") != nil)
        XCTAssertTrue(jsonString.range(of: "\"design_width\"") != nil)
        XCTAssertTrue(jsonString.range(of: "\"auto_design_width\"") != nil)
    }

    // MARK: - Package Tests

    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SkipMiniAppTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createSamplePackage(at path: String) throws -> MiniAppManifest {
        let manifest = MiniAppManifest(
            appId: "com.example.sample",
            name: "Sample MiniApp",
            icons: [MiniAppIcon(src: "icon.png", sizes: "48x48")],
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1),
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

        XCTAssertEqual(manifest.appId, expectedManifest.appId)
        XCTAssertEqual(manifest.name, expectedManifest.name)
        XCTAssertEqual(manifest.version, expectedManifest.version)
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
            logger.log("Got expected error: \(error)")
        }
    }

    func testCannotOpenPackage() throws {
        let package = MiniAppPackage(path: "/nonexistent/path/test.ma")
        do {
            let _ = try package.readManifest()
            XCTFail("Expected error for nonexistent package")
        } catch {
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

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: extractDir.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(fm.fileExists(atPath: extractDir.appendingPathComponent("app.js").path))
        XCTAssertTrue(fm.fileExists(atPath: extractDir.appendingPathComponent("app.css").path))
        XCTAssertTrue(fm.fileExists(atPath: extractDir.appendingPathComponent("pages/index/index.html").path))

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
        let states: [MiniAppGlobalState] = [.launched, .shown, .hidden, .error, .unloaded]
        XCTAssertEqual(states.count, 5)
        XCTAssertNotEqual(MiniAppGlobalState.launched, MiniAppGlobalState.shown)
        XCTAssertNotEqual(MiniAppGlobalState.shown, MiniAppGlobalState.hidden)
        XCTAssertNotEqual(MiniAppGlobalState.hidden, MiniAppGlobalState.error)
        XCTAssertNotEqual(MiniAppGlobalState.error, MiniAppGlobalState.unloaded)
    }

    func testAllPageStates() throws {
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
            appId: "com.example.multipage",
            name: "Multi-Page App",
            icons: [MiniAppIcon(src: "icon.png", sizes: "48x48")],
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1),
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

        for pagePath in loaded.pages {
            let html = try package.readPageHTML(pagePath: pagePath)
            XCTAssertNotNil(html, "HTML should exist for page: \(pagePath)")
        }

        let homeHTML = try XCTUnwrap(package.readPageHTML(pagePath: "pages/home/home"))
        XCTAssertEqual(String(data: homeHTML, encoding: .utf8), "<html><body>Home</body></html>")

        let settingsHTML = try XCTUnwrap(package.readPageHTML(pagePath: "pages/settings/settings"))
        XCTAssertEqual(String(data: settingsHTML, encoding: .utf8), "<html><body>Settings</body></html>")
    }

    // MARK: - Runtime Tests

    /// Helper to create a MiniApp package with the given app.js and page entries for runtime testing.
    private func createRuntimePackage(appJS: String, pageEntries: [(path: String, js: String, html: String)] = []) throws -> (MiniAppPackage, MiniAppManifest) {
        let tempDir = try createTempDirectory()
        let pkgPath = tempDir.appendingPathComponent("runtime-test.ma").path

        let pages = pageEntries.isEmpty ? ["pages/index/index"] : pageEntries.map { $0.path }
        let manifest = MiniAppManifest(
            appId: "com.example.runtime",
            name: "Runtime Test",
            icons: [MiniAppIcon(src: "icon.png")],
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1),
            pages: pages
        )

        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js", string: appJS, compression: 0)

        if pageEntries.isEmpty {
            try builder.addEntry(path: "pages/index/index.html", string: "<html><body>Test</body></html>", compression: 0)
            try builder.addEntry(path: "pages/index/index.js", string: "Page({})", compression: 0)
        } else {
            for entry in pageEntries {
                try builder.addEntry(path: entry.path + ".html", string: entry.html, compression: 0)
                try builder.addEntry(path: entry.path + ".js", string: entry.js, compression: 0)
            }
        }

        try builder.finalize()

        let package = MiniAppPackage(path: pkgPath)
        return (package, manifest)
    }

    func testRuntimeAppCallbackRegistration() throws {
        let appJS = """
        var launched = false;
        var shown = false;
        var hidden = false;
        App({
            onLaunch: function(options) { launched = true; },
            onShow: function() { shown = true; },
            onHide: function() { hidden = true; }
        });
        """
        let (pkg, manifest) = try createRuntimePackage(appJS: appJS)
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest)

        // Before start, callbacks should not have fired
        XCTAssertEqual(runtime.evaluateScriptAsBool("typeof launched !== 'undefined' ? launched : false"), false)

        runtime.start()
        XCTAssertEqual(runtime.evaluateScriptAsBool("launched"), true)
        XCTAssertEqual(runtime.lifecycle.globalState, .launched)

        runtime.fireAppShow()
        XCTAssertEqual(runtime.evaluateScriptAsBool("shown"), true)
        XCTAssertEqual(runtime.lifecycle.globalState, .shown)

        runtime.fireAppHide()
        XCTAssertEqual(runtime.evaluateScriptAsBool("hidden"), true)
        XCTAssertEqual(runtime.lifecycle.globalState, .hidden)
    }

    func testRuntimePageLifecycle() throws {
        let pageJS = """
        var pageLoaded = false;
        var pageShown = false;
        var pageReady = false;
        var pageHidden = false;
        var pageUnloaded = false;
        Page({
            onLoad: function(options) { pageLoaded = true; },
            onShow: function() { pageShown = true; },
            onReady: function() { pageReady = true; },
            onHide: function() { pageHidden = true; },
            onUnload: function() { pageUnloaded = true; }
        });
        """
        let pagePath = "pages/index/index"
        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})", pageEntries: [
            (path: pagePath, js: pageJS, html: "<html><body>Test</body></html>")
        ])
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest)
        runtime.start()

        runtime.loadPage(pagePath: pagePath)
        XCTAssertEqual(runtime.evaluateScriptAsBool("pageLoaded"), true)

        runtime.firePageReady(pagePath: pagePath)
        XCTAssertEqual(runtime.evaluateScriptAsBool("pageReady"), true)

        runtime.firePageShow(pagePath: pagePath)
        XCTAssertEqual(runtime.evaluateScriptAsBool("pageShown"), true)

        runtime.firePageHide(pagePath: pagePath)
        XCTAssertEqual(runtime.evaluateScriptAsBool("pageHidden"), true)

        runtime.firePageUnload(pagePath: pagePath)
        XCTAssertEqual(runtime.evaluateScriptAsBool("pageUnloaded"), true)
    }

    func testRuntimeConsoleLog() throws {
        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})")
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest)
        runtime.start()

        // These should not crash
        runtime.evaluateScript("console.log('test message')")
        runtime.evaluateScript("console.warn('warning message')")
        runtime.evaluateScript("console.error('error message')")
        runtime.evaluateScript("console.info('info message')")
        runtime.evaluateScript("console.debug('debug message')")
        runtime.evaluateScript("console.log('multiple', 'arguments', 123)")
    }

    // MARK: - OPFS File System Tests

    func testFSCreateAndReadFile() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        let _ = try fs.getFileHandle(at: "hello.txt", create: true)
        try fs.writeFile(at: "hello.txt", content: "Hello, world!")
        let content = try fs.readFile(at: "hello.txt")
        XCTAssertEqual(content, "Hello, world!")
    }

    func testFSReadNonexistentFileThrows() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        do {
            let _ = try fs.getFileHandle(at: "missing.txt", create: false)
            XCTFail("Expected NotFoundError")
        } catch let error as MiniAppFileSystemError {
            XCTAssertEqual(error.name, "NotFoundError")
        }
    }

    func testFSCreateDirectory() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        let _ = try fs.getDirectoryHandle(at: "subdir", create: true)
        let entries = try fs.entries(at: "")
        XCTAssertTrue(entries.contains(where: { $0.name == "subdir" && $0.kind == "directory" }))
    }

    func testFSGetDirectoryWithoutCreateThrows() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        do {
            let _ = try fs.getDirectoryHandle(at: "nope", create: false)
            XCTFail("Expected NotFoundError")
        } catch let error as MiniAppFileSystemError {
            XCTAssertEqual(error.name, "NotFoundError")
        }
    }

    func testFSNestedDirectories() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        let _ = try fs.getDirectoryHandle(at: "a/b/c", create: true)
        let _ = try fs.getFileHandle(at: "a/b/c/deep.txt", create: true)
        try fs.writeFile(at: "a/b/c/deep.txt", content: "nested")
        XCTAssertEqual(try fs.readFile(at: "a/b/c/deep.txt"), "nested")
    }

    func testFSEntries() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        let _ = try fs.getFileHandle(at: "file1.txt", create: true)
        let _ = try fs.getFileHandle(at: "file2.txt", create: true)
        let _ = try fs.getDirectoryHandle(at: "dir1", create: true)

        let entries = try fs.entries(at: "")
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.contains(where: { $0.name == "file1.txt" && $0.kind == "file" }))
        XCTAssertTrue(entries.contains(where: { $0.name == "dir1" && $0.kind == "directory" }))
    }

    func testFSRemoveFile() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        let _ = try fs.getFileHandle(at: "temp.txt", create: true)
        try fs.removeEntry(at: "temp.txt", recursive: false)
        do {
            let _ = try fs.getFileHandle(at: "temp.txt", create: false)
            XCTFail("File should be deleted")
        } catch { }
    }

    func testFSRemoveNonEmptyDirWithoutRecursiveThrows() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        let _ = try fs.getDirectoryHandle(at: "dir", create: true)
        let _ = try fs.getFileHandle(at: "dir/file.txt", create: true)
        do {
            try fs.removeEntry(at: "dir", recursive: false)
            XCTFail("Expected InvalidModificationError")
        } catch let error as MiniAppFileSystemError {
            XCTAssertEqual(error.name, "InvalidModificationError")
        }
    }

    func testFSRemoveDirectoryRecursive() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        let _ = try fs.getDirectoryHandle(at: "dir", create: true)
        let _ = try fs.getFileHandle(at: "dir/file.txt", create: true)
        try fs.removeEntry(at: "dir", recursive: true)
        let entries = try fs.entries(at: "")
        XCTAssertFalse(entries.contains(where: { $0.name == "dir" }))
    }

    func testFSFileSize() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        let _ = try fs.getFileHandle(at: "sized.txt", create: true)
        try fs.writeFile(at: "sized.txt", content: "12345")
        let size = try fs.fileSize(at: "sized.txt")
        XCTAssertEqual(size, 5)
    }

    func testFSOverwriteFile() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        let _ = try fs.getFileHandle(at: "data.txt", create: true)
        try fs.writeFile(at: "data.txt", content: "first")
        try fs.writeFile(at: "data.txt", content: "second")
        XCTAssertEqual(try fs.readFile(at: "data.txt"), "second")
    }

    func testFSCrossAppIsolation() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fsA = MiniAppFileSystem(appId: "com.example.appA", baseDirectory: tempDir)
        let fsB = MiniAppFileSystem(appId: "com.example.appB", baseDirectory: tempDir)

        let _ = try fsA.getFileHandle(at: "secret.txt", create: true)
        try fsA.writeFile(at: "secret.txt", content: "alpha")

        // App B should NOT see App A's file
        do {
            let _ = try fsB.getFileHandle(at: "secret.txt", create: false)
            XCTFail("App B should not see App A's files")
        } catch { }
    }

    func testFSPathTraversalPrevention() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        do {
            try fs.validatePath("../escape")
            XCTFail("Expected SecurityError for path traversal")
        } catch let error as MiniAppFileSystemError {
            XCTAssertEqual(error.name, "SecurityError")
        }
        do {
            try fs.validatePath("/absolute")
            XCTFail("Expected SecurityError for absolute path")
        } catch let error as MiniAppFileSystemError {
            XCTAssertEqual(error.name, "SecurityError")
        }
    }

    func testFSTypeMismatchError() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fs = MiniAppFileSystem(appId: "com.example.fstest", baseDirectory: tempDir)
        let _ = try fs.getDirectoryHandle(at: "mydir", create: true)
        do {
            let _ = try fs.getFileHandle(at: "mydir", create: false)
            XCTFail("Expected TypeMismatchError")
        } catch let error as MiniAppFileSystemError {
            XCTAssertEqual(error.name, "TypeMismatchError")
        }
    }

    // MARK: - OPFS Runtime Integration Tests

    func testJSCreateAndReadFile() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})")
        let fsModule = MiniAppFileSystemModule(baseDirectory: tempDir)
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest, modules: [MiniAppModuleType(fsModule)])
        runtime.start()

        runtime.evaluateScript("miniapp.fs.root.getFileHandle('test.txt', {create: true}).write('hello from JS')")
        let result = runtime.evaluateScript("miniapp.fs.root.getFileHandle('test.txt').read()")
        XCTAssertEqual(result, "hello from JS")
    }

    func testJSDirectoryOperations() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})")
        let fsModule = MiniAppFileSystemModule(baseDirectory: tempDir)
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest, modules: [MiniAppModuleType(fsModule)])
        runtime.start()

        runtime.evaluateScript("miniapp.fs.root.getDirectoryHandle('docs', {create: true})")
        runtime.evaluateScript("miniapp.fs.root.getFileHandle('docs/readme.txt', {create: true}).write('readme')")

        let entriesJSON = runtime.evaluateScript("JSON.stringify(miniapp.fs.root.entries())")
        XCTAssertNotNil(entriesJSON)
        XCTAssertTrue(entriesJSON?.contains("docs") == true)
    }

    func testJSFileSize() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})")
        let fsModule = MiniAppFileSystemModule(baseDirectory: tempDir)
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest, modules: [MiniAppModuleType(fsModule)])
        runtime.start()

        runtime.evaluateScript("miniapp.fs.root.getFileHandle('sized.txt', {create: true}).write('12345')")
        let size = runtime.evaluateScriptAsDouble("miniapp.fs.root.getFileHandle('sized.txt').size")
        XCTAssertEqual(size, 5.0)
    }

    func testJSPersistenceAcrossInstances() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appJS = "App({})"
        let (pkg1, manifest1) = try createRuntimePackage(appJS: appJS)
        let fsModule1 = MiniAppFileSystemModule(baseDirectory: tempDir)
        let runtime1 = MiniAppRuntime(package: pkg1, manifest: manifest1, modules: [MiniAppModuleType(fsModule1)])
        runtime1.start()

        runtime1.evaluateScript("miniapp.fs.root.getFileHandle('persist.txt', {create: true}).write('survives')")

        // Create a new runtime with the same base directory
        let (pkg2, manifest2) = try createRuntimePackage(appJS: appJS)
        let fsModule2 = MiniAppFileSystemModule(baseDirectory: tempDir)
        let runtime2 = MiniAppRuntime(package: pkg2, manifest: manifest2, modules: [MiniAppModuleType(fsModule2)])
        runtime2.start()

        let result = runtime2.evaluateScript("miniapp.fs.root.getFileHandle('persist.txt').read()")
        XCTAssertEqual(result, "survives")
    }

    // MARK: - i18n Tests

    func testI18nTranslateBasicKey() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a miniapp with i18n files
        let pkgPath = tempDir.appendingPathComponent("i18n-test.ma").path
        let manifest = MiniAppManifest(
            appId: "com.example.i18n",
            name: "I18n Test",
            icons: [],
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1),
            pages: ["pages/index/index"],
            lang: "en"
        )
        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js", string: "App({})", compression: 0)
        try builder.addEntry(path: "pages/index/index.html", string: "<html></html>", compression: 0)
        try builder.addEntry(path: "pages/index/index.js", string: "Page({})", compression: 0)
        try builder.addEntry(path: "i18n/en.json", string: "{\"greeting\":\"Hello\",\"farewell\":\"Goodbye\"}", compression: 0)
        try builder.finalize()

        let package = MiniAppPackage(path: pkgPath)
        let i18nModule = MiniAppI18nModule()
        let runtime = MiniAppRuntime(package: package, manifest: manifest, modules: [MiniAppModuleType(i18nModule)])
        runtime.start()

        let result = runtime.evaluateScript("miniapp.i18n.t('greeting')")
        XCTAssertEqual(result, "Hello")

        let result2 = runtime.evaluateScript("miniapp.i18n.t('farewell')")
        XCTAssertEqual(result2, "Goodbye")
    }

    func testI18nMissingKeyReturnsKey() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("i18n-test.ma").path
        let manifest = MiniAppManifest(
            appId: "com.example.i18n",
            name: "I18n Test",
            icons: [],
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1),
            pages: ["pages/index/index"],
            lang: "en"
        )
        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js", string: "App({})", compression: 0)
        try builder.addEntry(path: "pages/index/index.html", string: "<html></html>", compression: 0)
        try builder.addEntry(path: "pages/index/index.js", string: "Page({})", compression: 0)
        try builder.addEntry(path: "i18n/en.json", string: "{\"known\":\"Known\"}", compression: 0)
        try builder.finalize()

        let package = MiniAppPackage(path: pkgPath)
        let i18nModule = MiniAppI18nModule()
        let runtime = MiniAppRuntime(package: package, manifest: manifest, modules: [MiniAppModuleType(i18nModule)])
        runtime.start()

        // Missing key returns the key itself
        let result = runtime.evaluateScript("miniapp.i18n.t('unknown.key')")
        XCTAssertEqual(result, "unknown.key")
    }

    func testI18nParameterSubstitution() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("i18n-test.ma").path
        let manifest = MiniAppManifest(
            appId: "com.example.i18n",
            name: "I18n Test",
            icons: [],
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1),
            pages: ["pages/index/index"],
            lang: "en"
        )
        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js", string: "App({})", compression: 0)
        try builder.addEntry(path: "pages/index/index.html", string: "<html></html>", compression: 0)
        try builder.addEntry(path: "pages/index/index.js", string: "Page({})", compression: 0)
        try builder.addEntry(path: "i18n/en.json", string: "{\"hello\":\"Hello, {name}!\",\"multi\":\"From {city} to {dest}\"}", compression: 0)
        try builder.finalize()

        let package = MiniAppPackage(path: pkgPath)
        let i18nModule = MiniAppI18nModule()
        let runtime = MiniAppRuntime(package: package, manifest: manifest, modules: [MiniAppModuleType(i18nModule)])
        runtime.start()

        let result = runtime.evaluateScript("miniapp.i18n.t('hello', {name: 'World'})")
        XCTAssertEqual(result, "Hello, World!")

        let result2 = runtime.evaluateScript("miniapp.i18n.t('multi', {city: 'NYC', dest: 'LA'})")
        XCTAssertEqual(result2, "From NYC to LA")
    }

    func testI18nPluralRules() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("i18n-test.ma").path
        let manifest = MiniAppManifest(
            appId: "com.example.i18n",
            name: "I18n Test",
            icons: [],
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1),
            pages: ["pages/index/index"],
            lang: "en"
        )
        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js", string: "App({})", compression: 0)
        try builder.addEntry(path: "pages/index/index.html", string: "<html></html>", compression: 0)
        try builder.addEntry(path: "pages/index/index.js", string: "Page({})", compression: 0)
        try builder.addEntry(path: "i18n/en.json", string: "{}", compression: 0)
        try builder.finalize()

        let package = MiniAppPackage(path: pkgPath)
        let i18nModule = MiniAppI18nModule()
        let runtime = MiniAppRuntime(package: package, manifest: manifest, modules: [MiniAppModuleType(i18nModule)])
        runtime.start()

        // Plural: 1 item, 5 items
        let one = runtime.evaluateScript("miniapp.i18n.plural(1, {one: '# item', other: '# items'})")
        XCTAssertEqual(one, "1 item")

        let many = runtime.evaluateScript("miniapp.i18n.plural(5, {one: '# item', other: '# items'})")
        XCTAssertEqual(many, "5 items")
    }

    func testI18nNumberFormat() throws {
        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})")
        let i18nModule = MiniAppI18nModule()
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest, modules: [MiniAppModuleType(i18nModule)])
        runtime.start()

        // Basic number formatting — should at least produce a string representation
        let result = runtime.evaluateScript("miniapp.i18n.n(1234.56)")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("1") == true) // At minimum contains digits
        XCTAssertTrue(result?.contains("234") == true)
    }

    func testI18nLocaleProperty() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pkgPath = tempDir.appendingPathComponent("i18n-test.ma").path
        let manifest = MiniAppManifest(
            appId: "com.example.i18n",
            name: "I18n Test",
            icons: [],
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1),
            pages: ["pages/index/index"],
            lang: "en"
        )
        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js", string: "App({})", compression: 0)
        try builder.addEntry(path: "pages/index/index.html", string: "<html></html>", compression: 0)
        try builder.addEntry(path: "pages/index/index.js", string: "Page({})", compression: 0)
        try builder.addEntry(path: "i18n/en.json", string: "{}", compression: 0)
        try builder.finalize()

        let package = MiniAppPackage(path: pkgPath)
        let i18nModule = MiniAppI18nModule()
        let runtime = MiniAppRuntime(package: package, manifest: manifest, modules: [MiniAppModuleType(i18nModule)])
        runtime.start()

        let locale = runtime.evaluateScript("miniapp.i18n.locale")
        XCTAssertNotNil(locale)
        // Should be "en" since we provided i18n/en.json and manifest.lang = "en"
        XCTAssertEqual(locale, "en")
    }

    func testManifestI18nParsing() throws {
        let json = """
        {
            "app_id": "com.example.i18n",
            "name": "Hello App",
            "icons": [{"src": "icon.png"}],
            "version": {"code": 1, "name": "1.0.0"},
            "platform_version": {"min_code": 1},
            "pages": ["pages/index/index"],
            "lang": "en",
            "i18n": {
                "zh-Hans": {
                    "name": "你好应用",
                    "short_name": "你好",
                    "description": "一个国际化应用"
                }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        XCTAssertEqual(manifest.name, "Hello App")
        XCTAssertEqual(manifest.lang, "en")
        XCTAssertNotNil(manifest.i18n)
        XCTAssertEqual(manifest.i18n?["zh-Hans"]?.name, "你好应用")
        XCTAssertEqual(manifest.i18n?["zh-Hans"]?.shortName, "你好")
        XCTAssertEqual(manifest.i18n?["zh-Hans"]?.description, "一个国际化应用")
    }

    func testRuntimeNavigationCommand() throws {
        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})")
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest)
        runtime.start()

        XCTAssertNil(runtime.pendingNavigation)

        runtime.evaluateScript("miniapp.navigateTo({url: 'pages/detail/detail', query: 'id=42'})")

        XCTAssertNotNil(runtime.pendingNavigation)
        XCTAssertEqual(runtime.pendingNavigation?.action, .push)
        XCTAssertEqual(runtime.pendingNavigation?.pagePath, "pages/detail/detail")
        XCTAssertEqual(runtime.pendingNavigation?.query, "id=42")
    }

    func testRuntimeSystemInfo() throws {
        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})")
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest)
        runtime.start()

        let jsonString = runtime.evaluateScript("JSON.stringify(miniapp.getSystemInfo())") ?? ""
        let data = jsonString.data(using: .utf8) ?? Data()
        let info = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #if SKIP
        XCTAssertEqual(info?["platform"] as? String, "android")
        #else
        XCTAssertEqual(info?["platform"] as? String, "ios")
        #endif
        XCTAssertEqual(info?["appId"] as? String, "com.example.runtime")
        XCTAssertEqual(info?["version"] as? String, "1.0.0")
    }

    func testRuntimeTimers() throws {
        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})")
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest)
        runtime.start()

        // Test that setTimeout returns a timer ID
        let timerId = runtime.evaluateScriptAsDouble("setTimeout(function() {}, 1000)")
        XCTAssertNotNil(timerId)
        XCTAssertTrue((timerId ?? 0.0) > 0.0)

        // Test clearTimeout doesn't crash
        runtime.evaluateScript("clearTimeout(\(Int(timerId ?? 0.0)))")

        // Test setInterval returns a timer ID
        let intervalId = runtime.evaluateScriptAsDouble("setInterval(function() {}, 1000)")
        XCTAssertNotNil(intervalId)
        XCTAssertTrue((intervalId ?? 0.0) > 0.0)

        // Test clearInterval doesn't crash
        runtime.evaluateScript("clearInterval(\(Int(intervalId ?? 0.0)))")
    }

    func testRuntimeMultiPageNavigation() throws {
        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})", pageEntries: [
            (path: "pages/home/home", js: "Page({ onShow: function() { }, onHide: function() { } })", html: "<html><body>Home</body></html>"),
            (path: "pages/detail/detail", js: "Page({ onLoad: function() { }, onHide: function() { } })", html: "<html><body>Detail</body></html>"),
            (path: "pages/settings/settings", js: "Page({})", html: "<html><body>Settings</body></html>")
        ])
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest)
        runtime.start()

        // Load initial page
        runtime.loadPage(pagePath: "pages/home/home")
        XCTAssertEqual(runtime.pageStack, ["pages/home/home"])
        XCTAssertEqual(runtime.currentPage, "pages/home/home")

        // Push detail page
        let pushCommand = MiniAppNavigationCommand(action: .push, pagePath: "pages/detail/detail", query: "id=1")
        runtime.processNavigation(pushCommand)
        XCTAssertEqual(runtime.pageStack, ["pages/home/home", "pages/detail/detail"])
        XCTAssertEqual(runtime.currentPage, "pages/detail/detail")

        // Push settings page
        let pushCommand2 = MiniAppNavigationCommand(action: .push, pagePath: "pages/settings/settings")
        runtime.processNavigation(pushCommand2)
        XCTAssertEqual(runtime.pageStack.count, 3)
        XCTAssertEqual(runtime.currentPage, "pages/settings/settings")

        // Pop back to detail
        let popCommand = MiniAppNavigationCommand(action: .pop)
        runtime.processNavigation(popCommand)
        XCTAssertEqual(runtime.pageStack.count, 2)
        XCTAssertEqual(runtime.currentPage, "pages/detail/detail")

        // Pop back to home
        let popCommand2 = MiniAppNavigationCommand(action: .pop)
        runtime.processNavigation(popCommand2)
        XCTAssertEqual(runtime.pageStack.count, 1)
        XCTAssertEqual(runtime.currentPage, "pages/home/home")

        // Pop on single page should be a no-op
        let popCommand3 = MiniAppNavigationCommand(action: .pop)
        runtime.processNavigation(popCommand3)
        XCTAssertEqual(runtime.pageStack.count, 1)
        XCTAssertEqual(runtime.currentPage, "pages/home/home")
    }

    func testRuntimeAppError() throws {
        let appJS = """
        var errorMessage = '';
        App({
            onError: function(msg) { errorMessage = msg; }
        });
        """
        let (pkg, manifest) = try createRuntimePackage(appJS: appJS)
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest)
        runtime.start()

        runtime.fireAppError("something went wrong")

        XCTAssertEqual(runtime.lifecycle.globalState, .error)
        let result = runtime.evaluateScript("errorMessage")
        XCTAssertEqual(result, "something went wrong")
    }

    func testRuntimeEvaluateScript() throws {
        let (pkg, manifest) = try createRuntimePackage(appJS: "App({})")
        let runtime = MiniAppRuntime(package: pkg, manifest: manifest)
        runtime.start()

        // Test basic arithmetic
        let result = runtime.evaluateScriptAsDouble("1 + 2 + 3")
        XCTAssertEqual(result, 6.0)

        // Test string operations
        let result2 = runtime.evaluateScript("'hello' + ' ' + 'world'")
        XCTAssertEqual(result2, "hello world")

        // Test that global state persists
        runtime.evaluateScript("var testGlobal = 42")
        let result3 = runtime.evaluateScriptAsDouble("testGlobal")
        XCTAssertEqual(result3, 42.0)
    }

    // MARK: - Expanded MiniApp Resource Tests
    //
    // These tests load from the miniapp-samples/ copy-resource directory which preserves the
    // W3C-compliant directory structure (manifest.json, pages/, common/, i18n/). SPM's
    // .copy() is used because .process() flattens filenames and conflicts on duplicate
    // names like manifest.json across multiple mini-apps.
    //
    // On Android, resources inside an APK are not accessible via FileManager. All
    // existence checks use Data(contentsOf:) on URLs instead of fm.fileExists().

    /// Resolve the root URL for a specific expanded MiniApp within the miniapp-samples
    /// copy-resource directory. Uses a known resource file (TestData.json) to locate the
    /// bundle's resource base URL, then appends the miniapp-samples path.
    private func miniAppURL(_ name: String) throws -> URL {
        // Locate the miniapp-samples copy-resource relative to a known processed resource.
        // On macOS (SPM), processed resources are at the bundle root alongside miniapp-samples/:
        //   .../SkipMiniAppModelTests_SkipMiniAppModelTests.bundle/TestData.json
        //   .../SkipMiniAppModelTests_SkipMiniAppModelTests.bundle/miniapp-samples/...
        // On Android (Gradle), processed resources are in a Resources/ subdirectory
        // under the module package path, while copy resources are siblings:
        //   .../skip/mini/app/model/Resources/TestData.json
        //   .../skip/mini/app/model/miniapp-samples/...
        let anchor = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"),
                                   "TestData.json not found in bundle")
        var base = anchor.deletingLastPathComponent()
        let probe = base.appendingPathComponent("miniapp-samples").appendingPathComponent(name)
        // Probe for any known file to confirm this is the right level
        if !resourceExists(at: probe.appendingPathComponent("app.js"))
            && !resourceExists(at: probe.appendingPathComponent("manifest.json")) {
            // Go up one more level (Android layout: resources are in Resources/ subdir)
            base = base.deletingLastPathComponent()
        }
        return base.appendingPathComponent("miniapp-samples").appendingPathComponent(name)
    }

    /// Check whether a resource URL is loadable (works for both disk files and APK assets).
    private func resourceExists(at url: URL) -> Bool {
        return (try? Data(contentsOf: url))?.isEmpty == false
    }

    // MARK: Structure validation

    func testExpandedMinimalStructure() throws {
        let root = try miniAppURL("minimal.ma")

        // Required files per W3C MiniApp Packaging spec
        XCTAssertTrue(resourceExists(at: root.appendingPathComponent("manifest.json")),
                      "manifest.json is required")
        XCTAssertTrue(resourceExists(at: root.appendingPathComponent("app.js")),
                      "app.js is required")
        XCTAssertTrue(resourceExists(at: root.appendingPathComponent("app.css")),
                      "app.css is required")
        XCTAssertTrue(resourceExists(at: root.appendingPathComponent("pages/index/index.html")),
                      "At least one page HTML is required")
    }

    func testExpandedMultipageStructure() throws {
        let root = try miniAppURL("multipage.ma")

        // Core files
        XCTAssertTrue(resourceExists(at: root.appendingPathComponent("manifest.json")))
        XCTAssertTrue(resourceExists(at: root.appendingPathComponent("app.js")))
        XCTAssertTrue(resourceExists(at: root.appendingPathComponent("app.css")))

        // All three pages
        for page in ["index", "detail", "settings"] {
            XCTAssertTrue(resourceExists(at: root.appendingPathComponent("pages/\(page)/\(page).html")),
                          "\(page).html should exist")
            XCTAssertTrue(resourceExists(at: root.appendingPathComponent("pages/\(page)/\(page).js")),
                          "\(page).js should exist")
        }
    }

    func testExpandedInvalidNoManifest() throws {
        let root = try miniAppURL("invalid-no-manifest.ma")

        XCTAssertFalse(resourceExists(at: root.appendingPathComponent("manifest.json")),
                       "This test app intentionally lacks a manifest")
        XCTAssertTrue(resourceExists(at: root.appendingPathComponent("app.js")))
    }

    // MARK: Manifest loading from expanded directory

    func testLoadManifestFromExpandedMinimal() throws {
        let manifestURL = try miniAppURL("minimal.ma").appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        XCTAssertEqual(manifest.appId, "org.example.minimal")
        XCTAssertEqual(manifest.name, "Minimal MiniApp")
        XCTAssertEqual(manifest.version.code, 1)
        XCTAssertEqual(manifest.version.name, "1.0.0")
        XCTAssertEqual(manifest.platformVersion.minCode, 1)
        XCTAssertEqual(manifest.pages, ["pages/index/index"])
        XCTAssertEqual(manifest.icons.count, 1)
        XCTAssertNil(manifest.shortName)
        XCTAssertNil(manifest.description)
        XCTAssertNil(manifest.window)
        XCTAssertNil(manifest.widgets)
        XCTAssertNil(manifest.reqPermissions)
    }

    func testLoadManifestFromExpandedHello() throws {
        let manifestURL = try miniAppURL("hello.ma").appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        XCTAssertEqual(manifest.appId, "org.example.hello")
        XCTAssertEqual(manifest.name, "Hello MiniApp")
        XCTAssertEqual(manifest.shortName, "Hello")
        XCTAssertEqual(manifest.description, "A simple hello world MiniApp with lifecycle hooks")
        XCTAssertEqual(manifest.version.code, 2)
        XCTAssertEqual(manifest.version.name, "1.1.0")
        XCTAssertEqual(manifest.platformVersion.minCode, 1)
        XCTAssertEqual(manifest.platformVersion.targetCode, 2)
        XCTAssertEqual(manifest.platformVersion.releaseType, "Release")
        XCTAssertEqual(manifest.dir, "ltr")
        XCTAssertEqual(manifest.lang, "en-US")
        XCTAssertEqual(manifest.colorScheme, "auto")

        let window = try XCTUnwrap(manifest.window)
        XCTAssertEqual(window.navigationBarTitleText, "Hello World")
        XCTAssertEqual(window.navigationBarBackgroundColor, "#4A90D9")
        XCTAssertEqual(window.navigationBarTextStyle, "white")
        XCTAssertEqual(window.backgroundColor, "#F5F5F5")
        XCTAssertEqual(window.orientation, "portrait")
        XCTAssertEqual(window.fullscreen, false)
    }

    func testLoadManifestFromExpandedMultipage() throws {
        let manifestURL = try miniAppURL("multipage.ma").appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        XCTAssertEqual(manifest.appId, "org.example.multipage")
        XCTAssertEqual(manifest.name, "Multi-Page MiniApp")
        XCTAssertEqual(manifest.shortName, "MultiPage")
        XCTAssertEqual(manifest.pages.count, 3)
        XCTAssertEqual(manifest.pages[0], "pages/index/index")
        XCTAssertEqual(manifest.pages[1], "pages/detail/detail")
        XCTAssertEqual(manifest.pages[2], "pages/settings/settings")
        XCTAssertEqual(manifest.icons.count, 2)
        XCTAssertEqual(manifest.icons[0].label, "Small icon")
        XCTAssertEqual(manifest.deviceType, ["phone", "tablet"])

        let widgets = try XCTUnwrap(manifest.widgets)
        XCTAssertEqual(widgets.count, 1)
        XCTAssertEqual(widgets[0].name, "Quick Notes")
        XCTAssertEqual(widgets[0].minCode, 3)

        let perms = try XCTUnwrap(manifest.reqPermissions)
        XCTAssertEqual(perms.count, 2)
        XCTAssertEqual(perms[0].name, "system.permission.LOCATION")
        XCTAssertEqual(perms[1].name, "system.permission.CAMERA")

        let window = try XCTUnwrap(manifest.window)
        XCTAssertEqual(window.enablePullDownRefresh, true)
        XCTAssertEqual(window.onReachBottomDistance, 50)
        XCTAssertEqual(window.designWidth, 750)
        XCTAssertEqual(window.autoDesignWidth, false)
    }

    func testLoadManifestFromExpandedBadManifest() throws {
        let manifestURL = try miniAppURL("invalid-bad-manifest.ma").appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)

        do {
            let _ = try JSONDecoder().decode(MiniAppManifest.self, from: data)
            XCTFail("Decoding a manifest missing required fields should throw")
        } catch {
            logger.log("Got expected decode error: \(error)")
        }
    }

    // MARK: Page content introspection

    func testReadPageHTMLFromExpanded() throws {
        let root = try miniAppURL("hello.ma")
        let htmlURL = root.appendingPathComponent("pages/index/index.html")
        let html = try String(contentsOf: htmlURL, encoding: .utf8)

        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<h1>Hello, MiniApp!</h1>"))
        XCTAssertTrue(html.contains("<meta charset=\"utf-8\">"))
    }

    func testReadPageJSFromExpanded() throws {
        let root = try miniAppURL("hello.ma")
        let jsURL = root.appendingPathComponent("pages/index/index.js")
        let js = try String(contentsOf: jsURL, encoding: .utf8)

        XCTAssertTrue(js.contains("Page("))
        XCTAssertTrue(js.contains("onLoad"))
        XCTAssertTrue(js.contains("onShow"))
    }

    func testReadAppJSFromExpanded() throws {
        let root = try miniAppURL("hello.ma")
        let jsURL = root.appendingPathComponent("app.js")
        let js = try String(contentsOf: jsURL, encoding: .utf8)

        XCTAssertTrue(js.contains("App("))
        XCTAssertTrue(js.contains("onLaunch"))
        XCTAssertTrue(js.contains("onShow"))
        XCTAssertTrue(js.contains("onHide"))
    }

    // MARK: i18n resource loading

    func testLoadI18nResources() throws {
        let root = try miniAppURL("multipage.ma")

        let enURL = root.appendingPathComponent("i18n/en-US.json")
        let enData = try Data(contentsOf: enURL)
        let en = try JSONSerialization.jsonObject(with: enData) as? [String: String]
        XCTAssertEqual(en?["app.title"], "Multi-Page MiniApp")
        XCTAssertEqual(en?["home.welcome"], "Welcome")
        XCTAssertEqual(en?["settings.language"], "Language")

        let zhURL = root.appendingPathComponent("i18n/zh-Hans.json")
        let zhData = try Data(contentsOf: zhURL)
        let zh = try JSONSerialization.jsonObject(with: zhData) as? [String: String]
        XCTAssertNotNil(zh?["app.title"])
        XCTAssertNotNil(zh?["home.welcome"])
    }

    // MARK: Cross-reference manifest pages with file system

    func testManifestPagesMatchResources() throws {
        let root = try miniAppURL("multipage.ma")
        let manifestURL = root.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        // Every page listed in the manifest must have a loadable .html resource
        for pagePath in manifest.pages {
            let htmlURL = root.appendingPathComponent(pagePath + ".html")
            XCTAssertTrue(resourceExists(at: htmlURL),
                          "Page \(pagePath) listed in manifest but \(pagePath).html not loadable")
        }
    }

    func testManifestIconsReferenceExistingResources() throws {
        let root = try miniAppURL("multipage.ma")
        let manifestURL = root.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)

        for icon in manifest.icons {
            let iconURL = root.appendingPathComponent(icon.src)
            XCTAssertTrue(resourceExists(at: iconURL),
                          "Icon \(icon.src) referenced in manifest but not loadable")
        }
    }

    // MARK: Encoding roundtrip from expanded resource

    func testManifestRoundtripFromExpandedResource() throws {
        let manifestURL = try miniAppURL("multipage.ma").appendingPathComponent("manifest.json")
        let originalData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: originalData)

        // Re-encode and decode; result should be equal
        let reencoded = try JSONEncoder().encode(manifest)
        let roundtripped = try JSONDecoder().decode(MiniAppManifest.self, from: reencoded)
        XCTAssertEqual(manifest, roundtripped)
    }

    // MARK: Build .ma package from expanded directory

    func testBuildPackageFromExpandedMinimal() throws {
        let root = try miniAppURL("minimal.ma")
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Read manifest from expanded directory
        let manifestData = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: manifestData)

        // Build a .ma package from the expanded files
        let pkgPath = tempDir.appendingPathComponent("built.ma").path
        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js",
                             data: try Data(contentsOf: root.appendingPathComponent("app.js")),
                             compression: 0)
        try builder.addEntry(path: "app.css",
                             data: try Data(contentsOf: root.appendingPathComponent("app.css")),
                             compression: 0)
        try builder.addEntry(path: "pages/index/index.html",
                             data: try Data(contentsOf: root.appendingPathComponent("pages/index/index.html")),
                             compression: 0)
        try builder.finalize()

        // Verify the built package can be read back
        let package = MiniAppPackage(path: pkgPath)
        let loaded = try package.readManifest()
        XCTAssertEqual(loaded.appId, "org.example.minimal")
        XCTAssertEqual(loaded.pages, ["pages/index/index"])

        let entries = try package.listEntries()
        XCTAssertTrue(entries.contains("manifest.json"))
        XCTAssertTrue(entries.contains("app.js"))
        XCTAssertTrue(entries.contains("app.css"))
        XCTAssertTrue(entries.contains("pages/index/index.html"))
    }

    func testBuildPackageFromExpandedMultipage() throws {
        let root = try miniAppURL("multipage.ma")
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestData = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: manifestData)

        let pkgPath = tempDir.appendingPathComponent("multipage-built.ma").path
        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js",
                             data: try Data(contentsOf: root.appendingPathComponent("app.js")),
                             compression: 0)
        try builder.addEntry(path: "app.css",
                             data: try Data(contentsOf: root.appendingPathComponent("app.css")),
                             compression: 0)

        // Add all page files
        for pageName in ["index", "detail", "settings"] {
            let pageDir = root.appendingPathComponent("pages/\(pageName)")
            let htmlURL = pageDir.appendingPathComponent("\(pageName).html")
            try builder.addEntry(path: "pages/\(pageName)/\(pageName).html",
                                 data: try Data(contentsOf: htmlURL),
                                 compression: 0)
            let jsURL = pageDir.appendingPathComponent("\(pageName).js")
            if let jsData = try? Data(contentsOf: jsURL), !jsData.isEmpty {
                try builder.addEntry(path: "pages/\(pageName)/\(pageName).js",
                                     data: jsData,
                                     compression: 0)
            }
        }
        try builder.finalize()

        // Verify the built package
        let package = MiniAppPackage(path: pkgPath)
        let loaded = try package.readManifest()
        XCTAssertEqual(loaded.pages.count, 3)

        for pagePath in loaded.pages {
            let html = try package.readPageHTML(pagePath: pagePath)
            XCTAssertNotNil(html, "Page \(pagePath) HTML should be readable from built package")
        }
    }
}
