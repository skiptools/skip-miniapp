// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

#if !SKIP_BRIDGE
import Foundation

/// A parsed MiniApp URI per the W3C MiniApp Addressing specification.
///
/// Supports both `miniapp://` scheme URIs and HTTPS-based URIs.
/// Format: `miniapp://<host>/<appID>[;version=<version>][/<path>][?<query>][#<fragment>]`
public struct MiniAppURI: Hashable {
    /// The application identifier.
    public var appID: String

    /// Optional version specifier.
    public var version: String?

    /// Resource path within the MiniApp.
    public var path: String?

    /// Query string.
    public var query: String?

    /// Fragment identifier.
    public var fragment: String?

    /// The host component of the URI.
    public var host: String?

    public init(appID: String, version: String? = nil, path: String? = nil, query: String? = nil, fragment: String? = nil, host: String? = nil) {
        self.appID = appID
        self.version = version
        self.path = path
        self.query = query
        self.fragment = fragment
        self.host = host
    }

    /// Parse a MiniApp URI string into its components.
    /// Returns nil if the string is not a valid miniapp or https URI.
    public static func parse(_ uriString: String) -> MiniAppURI? {
        guard let url = URL(string: uriString) else { return nil }

        let scheme = url.scheme?.lowercased()
        guard scheme == "miniapp" || scheme == "https" else { return nil }

        let host = url.host

        // Get path components, filtering out the root "/"
        var pathComponents: [String] = []
        for component in url.pathComponents {
            if component != "/" {
                pathComponents.append(component)
            }
        }
        guard !pathComponents.isEmpty else { return nil }

        // First component is appID, possibly with ";version=X"
        var appIDPart = pathComponents[0]
        pathComponents.removeFirst()
        var version: String?

        if let semicolonRange = appIDPart.range(of: ";") {
            let params = String(appIDPart[semicolonRange.upperBound...])
            appIDPart = String(appIDPart[..<semicolonRange.lowerBound])
            if params.hasPrefix("version=") {
                version = String(params.dropFirst("version=".count))
            }
        }

        let resourcePath: String? = pathComponents.isEmpty ? nil : pathComponents.joined(separator: "/")

        return MiniAppURI(
            appID: appIDPart,
            version: version,
            path: resourcePath,
            query: url.query,
            fragment: url.fragment,
            host: host
        )
    }

    /// Convert this URI back to a string representation.
    public func toURIString(scheme: String = "miniapp", defaultHost: String = "localhost") -> String {
        var uri = scheme + "://" + (host ?? defaultHost) + "/" + appID
        if let version = version {
            uri += ";version=" + version
        }
        if let path = path {
            uri += "/" + path
        }
        if let query = query {
            uri += "?" + query
        }
        if let fragment = fragment {
            uri += "#" + fragment
        }
        return uri
    }
}
#endif
