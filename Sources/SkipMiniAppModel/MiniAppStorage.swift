// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import OSLog

private let logger = Logger(subsystem: "SkipMiniApp", category: "Storage")

/// Configures how a MiniApp's key-value storage is persisted.
public enum MiniAppStorageMode {
    /// Storage lives only in memory and is lost when the runtime is deallocated.
    case inMemory
    /// Storage is persisted to a sandboxed directory on disk, scoped by app ID.
    /// The `baseDirectory` is the root under which per-app folders are created.
    case persistent(baseDirectory: URL)
}

/// Per-app sandboxed key-value storage for the MiniApp `miniapp.*StorageSync` APIs.
///
/// Each MiniApp identified by its `appId` gets an isolated storage namespace.
/// In persistent mode, data is written to `{baseDirectory}/{appId}/storage.json`.
/// Security: all keys and the app ID are validated to prevent path traversal.
public final class MiniAppStorage {
    /// The app ID this storage instance is scoped to.
    public let appId: String

    /// The storage mode (in-memory or persistent).
    public let mode: MiniAppStorageMode

    /// In-memory cache of the key-value pairs.
    private var data: [String: String] = [:]

    /// Whether the persistent store has been loaded into memory.
    private var loaded = false

    /// Initialize storage for a specific MiniApp.
    ///
    /// - Parameters:
    ///   - appId: The MiniApp's `app_id` from its manifest. Must be a valid reverse-domain identifier.
    ///   - mode: `.inMemory` or `.persistent(baseDirectory:)`.
    public init(appId: String, mode: MiniAppStorageMode = .inMemory) {
        self.appId = appId
        self.mode = mode
    }

    // MARK: - Public API

    /// Get a value for a key, or `nil` if not set.
    public func get(_ key: String) -> String? {
        ensureLoaded()
        return data[key]
    }

    /// Set a value for a key.
    public func set(_ key: String, value: String) {
        try? validateKey(key)
        ensureLoaded()
        data[key] = value
        persistIfNeeded()
    }

    /// Remove a key and its value.
    public func remove(_ key: String) {
        ensureLoaded()
        data.removeValue(forKey: key)
        persistIfNeeded()
    }

    /// Remove all stored data for this MiniApp.
    public func clear() {
        data.removeAll()
        persistIfNeeded()
    }

    /// All keys currently stored.
    public func keys() -> [String] {
        ensureLoaded()
        return Array(data.keys)
    }

    // MARK: - Storage directory API

    /// Returns the storage directory URL for a specific MiniApp, or `nil` for in-memory mode.
    ///
    /// This can be used by the host app to inspect or manage a MiniApp's persisted data.
    public var storageDirectoryURL: URL? {
        switch mode {
        case .inMemory:
            return nil
        case .persistent(let baseDirectory):
            return baseDirectory.appendingPathComponent(sanitizedAppId)
        }
    }

    /// Returns the storage directory for an arbitrary app ID under a base directory.
    ///
    /// Use this to locate another MiniApp's storage folder (e.g., for admin/cleanup purposes).
    /// Normal MiniApp code cannot access another app's storage through the JS APIs.
    public static func storageDirectoryURL(forAppId appId: String, baseDirectory: URL) -> URL {
        return baseDirectory.appendingPathComponent(sanitize(appId: appId))
    }

    // MARK: - Security

    /// Validate that a storage key does not contain path-separator characters or other
    /// potentially dangerous sequences that could be used for path traversal.
    public static func validateKey(_ key: String) throws {
        guard !key.isEmpty else {
            throw MiniAppStorageError.emptyKey
        }
        guard !key.contains("/") && !key.contains("\\") && !key.contains("..") else {
            throw MiniAppStorageError.invalidKey(key)
        }
    }

    /// Validate that an app ID is safe for use as a directory name.
    public static func validateAppId(_ appId: String) throws {
        guard !appId.isEmpty else {
            throw MiniAppStorageError.invalidAppId(appId)
        }
        guard !appId.contains("/") && !appId.contains("\\") && !appId.contains("..") else {
            throw MiniAppStorageError.invalidAppId(appId)
        }
    }

    // MARK: - Internal

    private func validateKey(_ key: String) throws {
        try MiniAppStorage.validateKey(key)
    }

    /// Sanitize an app ID for safe use as a directory name.
    private var sanitizedAppId: String {
        return MiniAppStorage.sanitize(appId: appId)
    }

    private static let safeChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"

    private static func sanitize(appId: String) -> String {
        // Replace any non-alphanumeric/dot/hyphen/underscore characters with underscores
        var safe = ""
        for c in appId {
            if safeChars.contains(String(c)) {
                safe += String(c)
            } else {
                safe += "_"
            }
        }
        // Remove any ".." sequences that could be used for path traversal
        while safe.contains("..") {
            safe = safe.replacingOccurrences(of: "..", with: "_")
        }
        // Prevent empty or dot-only names
        if safe.isEmpty || safe == "." {
            safe = "_invalid_"
        }
        return safe
    }

    private var storageFileURL: URL? {
        return storageDirectoryURL?.appendingPathComponent("storage.json")
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .inMemory:
            break
        case .persistent:
            loadFromDisk()
        }
    }

    private func loadFromDisk() {
        guard let fileURL = storageFileURL else { return }
        do {
            let fileData = try Data(contentsOf: fileURL)
            if let dict = try JSONSerialization.jsonObject(with: fileData) as? [String: String] {
                data = dict
            }
        } catch {
            // File doesn't exist yet or is corrupted — start with empty storage
            logger.info("No existing storage at \(fileURL.path): \(error.localizedDescription)")
        }
    }

    private func persistIfNeeded() {
        switch mode {
        case .inMemory:
            break
        case .persistent:
            saveToDisk()
        }
    }

    private func saveToDisk() {
        guard let dirURL = storageDirectoryURL, let fileURL = storageFileURL else { return }
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            try jsonData.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to persist storage: \(error.localizedDescription)")
        }
    }
}

/// Errors related to MiniApp storage operations.
public enum MiniAppStorageError: Error {
    case emptyKey
    case invalidKey(String)
    case invalidAppId(String)
}
#endif
