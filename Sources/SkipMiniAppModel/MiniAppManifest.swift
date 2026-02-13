// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import Foundation

/// W3C MiniApp Manifest as defined in the MiniApp Manifest specification.
public struct MiniAppManifest: Codable, Hashable {
    public var appID: String
    public var appName: String
    public var shortName: String?
    public var description: String?
    public var icons: [MiniAppIcon]
    public var versionName: String
    public var versionCode: Int?
    public var minPlatformVersion: String
    public var pages: [String]
    public var dir: String?
    public var lang: String?
    public var window: MiniAppWindow?
    public var widgets: [MiniAppWidget]?
    public var reqPermissions: [MiniAppPermission]?

    enum CodingKeys: String, CodingKey {
        case appID
        case appName
        case shortName
        case description
        case icons
        case versionName
        case versionCode
        case minPlatformVersion
        case pages
        case dir
        case lang
        case window
        case widgets
        case reqPermissions = "req-permissions"
    }

    public init(
        appID: String,
        appName: String,
        shortName: String? = nil,
        description: String? = nil,
        icons: [MiniAppIcon] = [],
        versionName: String,
        versionCode: Int? = nil,
        minPlatformVersion: String,
        pages: [String] = [],
        dir: String? = nil,
        lang: String? = nil,
        window: MiniAppWindow? = nil,
        widgets: [MiniAppWidget]? = nil,
        reqPermissions: [MiniAppPermission]? = nil
    ) {
        self.appID = appID
        self.appName = appName
        self.shortName = shortName
        self.description = description
        self.icons = icons
        self.versionName = versionName
        self.versionCode = versionCode
        self.minPlatformVersion = minPlatformVersion
        self.pages = pages
        self.dir = dir
        self.lang = lang
        self.window = window
        self.widgets = widgets
        self.reqPermissions = reqPermissions
    }
}

/// Icon resource for a MiniApp.
public struct MiniAppIcon: Codable, Hashable {
    public var src: String
    public var sizes: String

    public init(src: String, sizes: String) {
        self.src = src
        self.sizes = sizes
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
    public var name: String
    public var path: String
    public var minPlatformVersion: String?

    public init(name: String, path: String, minPlatformVersion: String? = nil) {
        self.name = name
        self.path = path
        self.minPlatformVersion = minPlatformVersion
    }
}

/// Permission requirement in a MiniApp manifest.
public struct MiniAppPermission: Codable, Hashable {
    public var name: String
    public var reason: String?

    public init(name: String, reason: String? = nil) {
        self.name = name
        self.reason = reason
    }
}
