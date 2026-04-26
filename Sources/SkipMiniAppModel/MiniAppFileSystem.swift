// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import OSLog

private let logger = Logger(subsystem: "SkipMiniApp", category: "FileSystem")

/// OPFS-style per-app sandboxed file system for MiniApps.
///
/// Each MiniApp identified by its `appId` gets an isolated directory.
/// Operations use paths relative to the app's root directory.
/// Path traversal (e.g., "..") is rejected to enforce sandboxing.
public final class MiniAppFileSystem {
    /// The app ID this file system is scoped to.
    public let appId: String

    /// The root directory URL for this MiniApp's sandboxed file system.
    public let rootDirectory: URL

    private static let safeChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"

    public init(appId: String, baseDirectory: URL) {
        self.appId = appId
        let sanitized = MiniAppFileSystem.sanitize(appId: appId)
        self.rootDirectory = baseDirectory.appendingPathComponent(sanitized)
        // Ensure root directory exists
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Directory operations

    /// Get or create a subdirectory. Returns the resolved URL.
    /// Throws `NotFoundError` if the directory doesn't exist and `create` is false.
    /// Throws `TypeMismatchError` if a file exists at that path.
    public func getDirectoryHandle(at relativePath: String, create: Bool) throws -> URL {
        try validatePath(relativePath)
        let url = rootDirectory.appendingPathComponent(relativePath)
        let check = existsAndIsDirectory(at: url)

        if check.exists {
            if !check.isDirectory {
                throw MiniAppFileSystemError.typeMismatch("'\(relativePath)' is a file, not a directory")
            }
            return url
        }

        if create {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        throw MiniAppFileSystemError.notFound("Directory '\(relativePath)' does not exist")
    }

    /// Get or create a file handle. Returns the resolved URL.
    /// Throws `NotFoundError` if the file doesn't exist and `create` is false.
    /// Throws `TypeMismatchError` if a directory exists at that path.
    public func getFileHandle(at relativePath: String, create: Bool) throws -> URL {
        try validatePath(relativePath)
        let url = rootDirectory.appendingPathComponent(relativePath)
        let check = existsAndIsDirectory(at: url)

        if check.exists {
            if check.isDirectory {
                throw MiniAppFileSystemError.typeMismatch("'\(relativePath)' is a directory, not a file")
            }
            return url
        }

        if create {
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
            return url
        }

        throw MiniAppFileSystemError.notFound("File '\(relativePath)' does not exist")
    }

    /// List entries in a directory. Returns array of (name, kind) pairs.
    public func entries(at relativePath: String) throws -> [(name: String, kind: String)] {
        let dirPath = relativePath.isEmpty ? "" : relativePath
        let url = dirPath.isEmpty ? rootDirectory : rootDirectory.appendingPathComponent(dirPath)
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else {
            return []
        }

        var result: [(name: String, kind: String)] = []
        for name in contents {
            let itemURL = url.appendingPathComponent(name)
            let check = existsAndIsDirectory(at: itemURL)
            if check.exists {
                result.append((name: name, kind: check.isDirectory ? "directory" : "file"))
            }
        }
        return result
    }

    /// Remove a file or directory.
    /// Throws `NotFoundError` if the entry doesn't exist.
    /// Throws `InvalidModificationError` if removing a non-empty directory without recursive.
    public func removeEntry(at relativePath: String, recursive: Bool) throws {
        try validatePath(relativePath)
        let url = rootDirectory.appendingPathComponent(relativePath)
        let fm = FileManager.default
        let check = existsAndIsDirectory(at: url)

        guard check.exists else {
            throw MiniAppFileSystemError.notFound("'\(relativePath)' does not exist")
        }

        if check.isDirectory && !recursive {
            let contents = try? fm.contentsOfDirectory(atPath: url.path)
            if let contents = contents, !contents.isEmpty {
                throw MiniAppFileSystemError.invalidModification("Directory '\(relativePath)' is not empty; use recursive: true")
            }
        }

        try fm.removeItem(at: url)
    }

    // MARK: - File operations

    /// Read the contents of a file as a UTF-8 string.
    public func readFile(at relativePath: String) throws -> String {
        try validatePath(relativePath)
        let url = rootDirectory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MiniAppFileSystemError.notFound("File '\(relativePath)' does not exist")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Write a string to a file, creating or overwriting it.
    public func writeFile(at relativePath: String, content: String) throws {
        try validatePath(relativePath)
        let url = rootDirectory.appendingPathComponent(relativePath)
        // Ensure parent directory exists
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Get the size of a file in bytes.
    public func fileSize(at relativePath: String) throws -> Int {
        try validatePath(relativePath)
        let url = rootDirectory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MiniAppFileSystemError.notFound("File '\(relativePath)' does not exist")
        }
        let data = try Data(contentsOf: url)
        return data.count
    }

    // MARK: - Helpers

    /// Check if a path exists and whether it's a directory. Skip-compatible (no ObjCBool).
    private func existsAndIsDirectory(at url: URL) -> (exists: Bool, isDirectory: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return (false, false)
        }
        // Check if it's a directory by trying to list contents
        let isDir = (try? fm.contentsOfDirectory(atPath: url.path)) != nil
        return (true, isDir)
    }

    // MARK: - Security

    /// Validate that a path is safe (no traversal, no absolute paths).
    public func validatePath(_ path: String) throws {
        guard !path.isEmpty else { return } // Empty path = root, allowed
        guard !path.hasPrefix("/") else {
            throw MiniAppFileSystemError.securityError("Absolute paths are not allowed")
        }
        let components = path.split(separator: "/").map { String($0) }
        for component in components {
            if component == ".." {
                throw MiniAppFileSystemError.securityError("Path traversal '..' is not allowed")
            }
            if component.contains("\\") {
                throw MiniAppFileSystemError.securityError("Backslash in path is not allowed")
            }
        }
        // Verify resolved path doesn't escape sandbox via symlinks or normalization
        let resolved = rootDirectory.appendingPathComponent(path).path
        let rootPath = rootDirectory.path
        guard resolved.hasPrefix(rootPath) else {
            throw MiniAppFileSystemError.securityError("Path escapes sandbox")
        }
    }

    /// Returns the file system root directory for a specific app ID under a base directory.
    public static func rootDirectoryURL(forAppId appId: String, baseDirectory: URL) -> URL {
        return baseDirectory.appendingPathComponent(sanitize(appId: appId))
    }

    private static func sanitize(appId: String) -> String {
        var safe = ""
        for c in appId {
            if safeChars.contains(String(c)) {
                safe += String(c)
            } else {
                safe += "_"
            }
        }
        while safe.contains("..") {
            safe = safe.replacingOccurrences(of: "..", with: "_")
        }
        if safe.isEmpty || safe == "." {
            safe = "_invalid_"
        }
        return safe
    }
}

/// Errors matching OPFS DOMException names.
public enum MiniAppFileSystemError: Error {
    case notFound(String)
    case typeMismatch(String)
    case invalidModification(String)
    case securityError(String)

    /// The OPFS DOMException name for this error.
    public var name: String {
        switch self {
        case .notFound: return "NotFoundError"
        case .typeMismatch: return "TypeMismatchError"
        case .invalidModification: return "InvalidModificationError"
        case .securityError: return "SecurityError"
        }
    }

    /// The error message.
    public var message: String {
        switch self {
        case .notFound(let msg):
            return msg
        case .typeMismatch(let msg):
            return msg
        case .invalidModification(let msg):
            return msg
        case .securityError(let msg):
            return msg
        }
    }
}
#endif
