# SkipMiniApp

A [Skip](https://skip.dev) framework for loading and running [W3C MiniApp](https://www.w3.org/TR/miniapp-packaging/) packages on iOS and Android. It provides a JavaScript runtime for executing app logic, a WebView-based page renderer, lifecycle management following the [W3C MiniApp Lifecycle](https://www.w3.org/TR/miniapp-lifecycle/) specification, and a native bridge exposing storage, navigation, and networking APIs to page scripts.

> **Experimental**: This package is under active development and is not ready for production use. APIs are subject to change without notice.

## W3C MiniApp Specifications

This framework implements portions of the following W3C MiniApp specifications:

- [MiniApp Packaging](https://www.w3.org/TR/miniapp-packaging/) — `.ma` ZIP-based package format with manifest and resource layout
- [MiniApp Manifest](https://www.w3.org/TR/miniapp-manifest/) — JSON manifest schema for app metadata, pages, icons, and window configuration
- [MiniApp Lifecycle](https://www.w3.org/TR/miniapp-lifecycle/) — Global and per-page lifecycle states and events
- [MiniApp Addressing](https://www.w3.org/TR/miniapp-addressing/) — `miniapp://` URI scheme and HTTPS mapping

## Modules

The package contains two modules:

- **SkipMiniAppModel** — Platform-independent model layer: manifest parsing, package reading/building, JavaScript runtime, and lifecycle state machines.
- **SkipMiniApp** — SwiftUI view layer: `MiniAppView` loads a `.ma` package and renders pages in a WebView with bridge integration.

## Major Types

### SkipMiniApp

| Type | Description |
|------|-------------|
| `MiniAppView` | SwiftUI view that extracts a MiniApp package, starts the JavaScript runtime, and displays pages in a WebView with native bridge messaging. |

### SkipMiniAppModel

#### Package & Manifest

| Type | Description |
|------|-------------|
| `MiniAppPackage` | Reads W3C MiniApp `.ma` package files (ZIP containers) and provides access to the manifest, app script, page scripts, and other resources. |
| `MiniAppPackageBuilder` | Creates `.ma` package files programmatically. |
| `MiniAppManifest` | W3C MiniApp Manifest representation: app ID, name, version, pages, icons, window configuration, widgets, and permissions. |
| `MiniAppVersion` | Version information with an integer code and a display name. |
| `MiniAppPlatformVersion` | Minimum and target platform version requirements. |
| `MiniAppIcon` | Icon resource entry with source path, sizes, and label. |
| `MiniAppWindow` | Window display configuration: navigation bar style, background color, orientation, and fullscreen mode. |
| `MiniAppWidget` | Widget declaration with name, path, and minimum platform version. |
| `MiniAppPermission` | Requested permission with name and reason. |
| `MiniAppURI` | Parser and constructor for `miniapp://` URIs and HTTPS MiniApp URLs. |
| `MiniAppError` | Error type for package operations (missing manifest, invalid format, resource not found). |

#### Runtime & Lifecycle

| Type | Description |
|------|-------------|
| `MiniAppRuntime` | Core JavaScript runtime managing a `JSContext` for `app.js` execution, global bridge functions (`App()`, `Page()`, `console`, timers, `miniapp.*` APIs), page stack navigation, and lifecycle event dispatch. |
| `MiniAppNavigationCommand` | Navigation command issued by JavaScript via `miniapp.navigateTo()` or `miniapp.navigateBack()`. |
| `MiniAppNavigationAction` | Navigation action type: `.push` or `.pop`. |
| `MiniAppLifecycle` | Global application lifecycle state machine: launched, shown, hidden, error, unloaded. |
| `MiniAppPageLifecycle` | Per-page lifecycle state machine: loaded, ready, shown, hidden, unloaded. |
| `MiniAppGlobalState` | Enum of global lifecycle states. |
| `MiniAppPageState` | Enum of page lifecycle states. |

## Building

This project is a free Swift Package Manager module that uses the
[Skip](https://skip.dev) plugin to transpile Swift into Kotlin.

Building the module requires that Skip be installed using
[Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.
This will also install the necessary build prerequisites:
Kotlin, Gradle, and the Android build tools.

## Testing

The module can be tested using the standard `swift test` command
or by running the test target for the macOS destination in Xcode,
which will run the Swift tests as well as the transpiled
Kotlin JUnit tests in the Robolectric Android simulation environment.

Parity testing can be performed with `skip test`,
which will output a table of the test results for both platforms.

## License

This software is licensed under the
[GNU Lesser General Public License v3.0](https://spdx.org/licenses/LGPL-3.0-only.html),
with a [linking exception](https://spdx.org/licenses/LGPL-3.0-linking-exception.html)
to clarify that distribution to restricted environments (e.g., app stores) is permitted.
