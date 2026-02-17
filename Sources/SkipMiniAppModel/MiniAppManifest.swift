// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

#if !SKIP_BRIDGE
import Foundation

/// W3C MiniApp Manifest as defined in the MiniApp Manifest specification.
/// See: https://www.w3.org/TR/miniapp-manifest/
public struct MiniAppManifest: Codable, Hashable {
    /// Unique application identifier using reverse domain notation.
    public var appId: String
    /// Descriptive name of the application.
    public var name: String
    /// Concise and easy-to-read name for a MiniApp.
    public var shortName: String?
    /// Textual description for the MiniApp.
    public var description: String?
    /// Images that serve as iconic representations.
    public var icons: [MiniAppIcon]
    /// Version information (code and name).
    public var version: MiniAppVersion
    /// Platform version requirements.
    public var platformVersion: MiniAppPlatformVersion
    /// Collection of pages that are part of a MiniApp.
    public var pages: [String]
    /// Base direction for the localizable members. Values: "ltr", "rtl", "auto".
    public var dir: String?
    /// Primary language tag (BCP47).
    public var lang: String?
    /// Preferred color scheme. Values: "auto", "light", "dark".
    public var colorScheme: String?
    /// Types of devices the MiniApp supports (e.g., "phone", "tablet", "tv", "car").
    public var deviceType: [String]?
    /// Look and feel of the MiniApp frame.
    public var window: MiniAppWindow?
    /// MiniApp widgets that are part of the MiniApp.
    public var widgets: [MiniAppWidget]?
    /// Requested system permissions.
    public var reqPermissions: [MiniAppPermission]?

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case name
        case shortName = "short_name"
        case description
        case icons
        case version
        case platformVersion = "platform_version"
        case pages
        case dir
        case lang
        case colorScheme = "color_scheme"
        case deviceType = "device_type"
        case window
        case widgets
        case reqPermissions = "req_permissions"
    }

    public init(
        appId: String,
        name: String,
        shortName: String? = nil,
        description: String? = nil,
        icons: [MiniAppIcon] = [],
        version: MiniAppVersion,
        platformVersion: MiniAppPlatformVersion,
        pages: [String] = [],
        dir: String? = nil,
        lang: String? = nil,
        colorScheme: String? = nil,
        deviceType: [String]? = nil,
        window: MiniAppWindow? = nil,
        widgets: [MiniAppWidget]? = nil,
        reqPermissions: [MiniAppPermission]? = nil
    ) {
        self.appId = appId
        self.name = name
        self.shortName = shortName
        self.description = description
        self.icons = icons
        self.version = version
        self.platformVersion = platformVersion
        self.pages = pages
        self.dir = dir
        self.lang = lang
        self.colorScheme = colorScheme
        self.deviceType = deviceType
        self.window = window
        self.widgets = widgets
        self.reqPermissions = reqPermissions
    }
}

/// Version resource for a MiniApp.
public struct MiniAppVersion: Codable, Hashable {
    /// Non-negative integer version code.
    public var code: Int
    /// Human-readable version string (e.g., "1.0.0").
    public var name: String

    public init(code: Int, name: String) {
        self.code = code
        self.name = name
    }
}

/// Platform version resource for a MiniApp.
public struct MiniAppPlatformVersion: Codable, Hashable {
    /// Minimum supported version of the MiniApp user agent.
    public var minCode: Int
    /// Target supported version of the MiniApp user agent.
    public var targetCode: Int?
    /// Release type (e.g., "Beta1", "Release").
    public var releaseType: String?

    enum CodingKeys: String, CodingKey {
        case minCode = "min_code"
        case targetCode = "target_code"
        case releaseType = "release_type"
    }

    public init(minCode: Int, targetCode: Int? = nil, releaseType: String? = nil) {
        self.minCode = minCode
        self.targetCode = targetCode
        self.releaseType = releaseType
    }
}

/// Image resource for a MiniApp icon.
public struct MiniAppIcon: Codable, Hashable {
    /// URL source of the icon image.
    public var src: String
    /// Sizes of the image (e.g., "48x48", "any").
    public var sizes: String?
    /// Accessible name of the image.
    public var label: String?

    public init(src: String, sizes: String? = nil, label: String? = nil) {
        self.src = src
        self.sizes = sizes
        self.label = label
    }
}

/// Window display configuration for a MiniApp.
public struct MiniAppWindow: Codable, Hashable {
    public var navigationBarBackgroundColor: String?
    public var navigationBarTextStyle: String?
    public var navigationBarTitleText: String?
    public var navigationStyle: String?
    public var backgroundColor: String?
    public var backgroundTextStyle: String?
    public var enablePullDownRefresh: Bool?
    public var onReachBottomDistance: Int?
    public var orientation: String?
    public var fullscreen: Bool?
    public var designWidth: Int?
    public var autoDesignWidth: Bool?

    enum CodingKeys: String, CodingKey {
        case navigationBarBackgroundColor = "navigation_bar_background_color"
        case navigationBarTextStyle = "navigation_bar_text_style"
        case navigationBarTitleText = "navigation_bar_title_text"
        case navigationStyle = "navigation_style"
        case backgroundColor = "background_color"
        case backgroundTextStyle = "background_text_style"
        case enablePullDownRefresh = "enable_pull_down_refresh"
        case onReachBottomDistance = "on_reach_bottom_distance"
        case orientation
        case fullscreen
        case designWidth = "design_width"
        case autoDesignWidth = "auto_design_width"
    }

    public init(
        navigationBarBackgroundColor: String? = nil,
        navigationBarTextStyle: String? = nil,
        navigationBarTitleText: String? = nil,
        navigationStyle: String? = nil,
        backgroundColor: String? = nil,
        backgroundTextStyle: String? = nil,
        enablePullDownRefresh: Bool? = nil,
        onReachBottomDistance: Int? = nil,
        orientation: String? = nil,
        fullscreen: Bool? = nil,
        designWidth: Int? = nil,
        autoDesignWidth: Bool? = nil
    ) {
        self.navigationBarBackgroundColor = navigationBarBackgroundColor
        self.navigationBarTextStyle = navigationBarTextStyle
        self.navigationBarTitleText = navigationBarTitleText
        self.navigationStyle = navigationStyle
        self.backgroundColor = backgroundColor
        self.backgroundTextStyle = backgroundTextStyle
        self.enablePullDownRefresh = enablePullDownRefresh
        self.onReachBottomDistance = onReachBottomDistance
        self.orientation = orientation
        self.fullscreen = fullscreen
        self.designWidth = designWidth
        self.autoDesignWidth = autoDesignWidth
    }
}

/// Widget definition in a MiniApp manifest.
public struct MiniAppWidget: Codable, Hashable {
    /// Title of the widget.
    public var name: String
    /// Corresponding page route of the widget.
    public var path: String
    /// Minimum platform version code supported for the widget.
    public var minCode: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case minCode = "min_code"
    }

    public init(name: String, path: String, minCode: Int? = nil) {
        self.name = name
        self.path = path
        self.minCode = minCode
    }
}

/// Permission requirement in a MiniApp manifest.
public struct MiniAppPermission: Codable, Hashable {
    /// Name of the feature requested.
    public var name: String
    /// Reason given to request the feature.
    public var reason: String?

    public init(name: String, reason: String? = nil) {
        self.name = name
        self.reason = reason
    }
}
#endif
