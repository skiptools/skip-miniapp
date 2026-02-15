// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
import Foundation
import SkipZip

/// Errors that can occur when working with MiniApp packages.
public enum MiniAppError: Error {
    case missingManifest
    case cannotOpenPackage
    case cannotCreatePackage
    case invalidManifest
    case resourceNotFound
}

/// Reads a W3C MiniApp package (.ma ZIP container) as defined in the MiniApp Packaging specification.
public class MiniAppPackage {
    /// The file path of the package.
    public let path: String

    /// MIME type for MiniApp packages.
    public static let mimeType = "application/miniapp-pkg+zip"

    /// Standard file extension for MiniApp packages.
    public static let fileExtension = "ma"

    /// Well-known entry paths within a MiniApp package.
    public static let manifestPath = "manifest.json"
    public static let appJSPath = "app.js"
    public static let appCSSPath = "app.css"
    public static let pagesDirectory = "pages/"
    public static let commonDirectory = "common/"
    public static let i18nDirectory = "i18n/"

    private var cachedManifest: MiniAppManifest?

    public init(path: String) {
        self.path = path
    }

    /// Read and parse the manifest from the package.
    public func readManifest() throws -> MiniAppManifest {
        if let cached = cachedManifest {
            return cached
        }
        guard let data = try readEntry(at: MiniAppPackage.manifestPath) else {
            throw MiniAppError.missingManifest
        }
        let manifest = try JSONDecoder().decode(MiniAppManifest.self, from: data)
        cachedManifest = manifest
        return manifest
    }

    /// Read a specific entry from the package by its path within the archive.
    public func readEntry(at entryPath: String) throws -> Data? {
        guard let reader = ZipReader(path: path) else {
            throw MiniAppError.cannotOpenPackage
        }
        defer { try? reader.close() }

        try reader.first()
        var hasMore = true
        while hasMore {
            if let name = try reader.currentEntryName {
                if name == entryPath {
                    return try reader.currentEntryData
                }
            }
            hasMore = try reader.next()
        }
        return nil
    }

    /// List all entry paths in the package.
    public func listEntries() throws -> [String] {
        guard let reader = ZipReader(path: path) else {
            throw MiniAppError.cannotOpenPackage
        }
        defer { try? reader.close() }

        var entries: [String] = []
        try reader.first()
        var hasMore = true
        while hasMore {
            if let name = try reader.currentEntryName {
                entries.append(name)
            }
            hasMore = try reader.next()
        }
        return entries
    }

    /// Read the global app.js content.
    public func readAppJS() throws -> Data? {
        return try readEntry(at: MiniAppPackage.appJSPath)
    }

    /// Read the global app.css content.
    public func readAppCSS() throws -> Data? {
        return try readEntry(at: MiniAppPackage.appCSSPath)
    }

    /// Read the HTML for a page route (as listed in manifest.pages).
    public func readPageHTML(pagePath: String) throws -> Data? {
        return try readEntry(at: pagePath + ".html")
    }

    /// Read the CSS for a page route.
    public func readPageCSS(pagePath: String) throws -> Data? {
        return try readEntry(at: pagePath + ".css")
    }

    /// Read the JS for a page route.
    public func readPageJS(pagePath: String) throws -> Data? {
        return try readEntry(at: pagePath + ".js")
    }

    /// Extract all package contents to a directory on disk.
    public func extractToDirectory(at directoryPath: String) throws {
        let fm = FileManager.default
        guard let reader = ZipReader(path: path) else {
            throw MiniAppError.cannotOpenPackage
        }
        defer { try? reader.close() }

        try reader.first()
        var hasMore = true
        while hasMore {
            if let name = try reader.currentEntryName {
                let isDir = try reader.currentEntryIsDirectory
                let destPath = directoryPath + "/" + name

                if isDir {
                    try fm.createDirectory(atPath: destPath, withIntermediateDirectories: true, attributes: nil)
                } else {
                    let parentURL = URL(fileURLWithPath: destPath).deletingLastPathComponent()
                    if !fm.fileExists(atPath: parentURL.path) {
                        try fm.createDirectory(atPath: parentURL.path, withIntermediateDirectories: true, attributes: nil)
                    }
                    if let data = try reader.currentEntryData {
                        fm.createFile(atPath: destPath, contents: data, attributes: nil)
                    }
                }
            }
            hasMore = try reader.next()
        }
    }
}

/// Builds a MiniApp package (.ma ZIP container).
public class MiniAppPackageBuilder {
    private let writer: ZipWriter

    public init(path: String) throws {
        guard let writer = ZipWriter(path: path, append: false) else {
            throw MiniAppError.cannotCreatePackage
        }
        self.writer = writer
    }

    /// Add a manifest to the package.
    public func addManifest(_ manifest: MiniAppManifest) throws {
        let data = try JSONEncoder().encode(manifest)
        try writer.add(path: MiniAppPackage.manifestPath, data: data, compression: 0)
    }

    /// Add an arbitrary entry to the package.
    public func addEntry(path: String, data: Data, compression: Int? = nil) throws {
        try writer.add(path: path, data: data, compression: compression)
    }

    /// Add a text entry to the package.
    public func addEntry(path: String, string: String, compression: Int? = nil) throws {
        guard let data = string.data(using: .utf8) else { return }
        try writer.add(path: path, data: data, compression: compression)
    }

    /// Finalize and close the package.
    public func finalize() throws {
        try writer.close()
    }
}
#endif
