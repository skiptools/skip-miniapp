// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import SkipScript
// SKIP NOWARN

extension MiniAppModuleType {
    /// File system module with a temporary base directory (non-persistent).
    public static let fileSystem = MiniAppModuleType(MiniAppFileSystemModule())

    /// File system module with a persistent base directory.
    public static func fileSystem(baseDirectory: URL) -> MiniAppModuleType {
        return MiniAppModuleType(MiniAppFileSystemModule(baseDirectory: baseDirectory))
    }
}

/// MiniApp module providing an OPFS-style file system API in the Logic Layer.
///
/// Exposes `skip.fs.root` as a `FileSystemDirectoryHandle` with methods:
/// - `getFileHandle(name, {create})` → FileHandle with `.read()`, `.write()`, `.remove()`, `.size`
/// - `getDirectoryHandle(name, {create})` → DirectoryHandle (recursive)
/// - `entries()` → `[{name, kind}]`
/// - `removeEntry(name, {recursive})`
///
/// All operations are synchronous and sandboxed per MiniApp.
public final class MiniAppFileSystemModule: MiniAppModule {
    /// Base directory for app file systems. Defaults to temp directory.
    public let baseDirectory: URL

    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("MiniAppFS")
        super.init()
    }

    override public func registerInRuntime(_ runtime: MiniAppRuntime) {
        let context = runtime.jsContext
        guard let namespace = runtime.namespaceObject else { return }

        // Create the file system instance for this app
        let fs = MiniAppFileSystem(appId: runtime.manifest.appId, baseDirectory: baseDirectory)
        runtime.fileSystem = fs

        // Register native bridge functions (called from JS handle prototypes)
        registerNativeFunctions(context: context, fs: fs)

        // Register JS handle constructors and set skip.fs.root
        context.evaluateScript("""
        function __FSDirectoryHandle(path, name) {
            this.path = path;
            this.name = name;
            this.kind = 'directory';
        }
        __FSDirectoryHandle.prototype.getFileHandle = function(name, opts) {
            return __fsGetFileHandle(this.path, name, opts && opts.create ? true : false);
        };
        __FSDirectoryHandle.prototype.getDirectoryHandle = function(name, opts) {
            return __fsGetDirectoryHandle(this.path, name, opts && opts.create ? true : false);
        };
        __FSDirectoryHandle.prototype.entries = function() {
            return __fsEntries(this.path);
        };
        __FSDirectoryHandle.prototype.removeEntry = function(name, opts) {
            var childPath = this.path ? this.path + '/' + name : name;
            __fsRemoveEntry(childPath, opts && opts.recursive ? true : false);
        };

        function __FSFileHandle(path, name) {
            this.path = path;
            this.name = name;
            this.kind = 'file';
        }
        __FSFileHandle.prototype.read = function() {
            return __fsRead(this.path);
        };
        __FSFileHandle.prototype.write = function(data) {
            __fsWrite(this.path, String(data));
        };
        __FSFileHandle.prototype.remove = function() {
            __fsRemoveEntry(this.path, false);
        };
        Object.defineProperty(__FSFileHandle.prototype, 'size', {
            get: function() { return __fsSize(this.path); }
        });
        """)

        // Create the fs namespace object with the root handle
        let fsObj = JSValue(newObjectIn: context)
        if let rootHandle = context.evaluateScript("new __FSDirectoryHandle('', '')") {
            fsObj.setObject(rootHandle, forKeyedSubscript: "root")
        }
        namespace.setObject(fsObj, forKeyedSubscript: "fs")
    }

    private func registerNativeFunctions(context: JSContext, fs: MiniAppFileSystem) {
        // __fsGetFileHandle(dirPath, name, create) -> FileHandle
        let getFileHandleFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let dirPath = args.count > 0 ? (args[0].toString() ?? "") : ""
            let name = args.count > 1 ? (args[1].toString() ?? "") : ""
            let create = args.count > 2 ? args[2].toBool() : false
            let fullPath = dirPath.isEmpty ? name : dirPath + "/" + name

            do {
                let _ = try fs.getFileHandle(at: fullPath, create: create)
                return ctx.evaluateScript("new __FSFileHandle('\(Self.escapeJS(fullPath))', '\(Self.escapeJS(name))')") ?? JSValue(undefinedIn: ctx)
            } catch let error as MiniAppFileSystemError {
                Self.throwJSError(ctx: ctx, error: error)
                return JSValue(undefinedIn: ctx)
            } catch {
                Self.throwJSError(ctx: ctx, name: "Error", message: error.localizedDescription)
                return JSValue(undefinedIn: ctx)
            }
        }
        context.setObject(getFileHandleFn, forKeyedSubscript: "__fsGetFileHandle")

        // __fsGetDirectoryHandle(dirPath, name, create) -> DirectoryHandle
        let getDirHandleFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let dirPath = args.count > 0 ? (args[0].toString() ?? "") : ""
            let name = args.count > 1 ? (args[1].toString() ?? "") : ""
            let create = args.count > 2 ? args[2].toBool() : false
            let fullPath = dirPath.isEmpty ? name : dirPath + "/" + name

            do {
                let _ = try fs.getDirectoryHandle(at: fullPath, create: create)
                return ctx.evaluateScript("new __FSDirectoryHandle('\(Self.escapeJS(fullPath))', '\(Self.escapeJS(name))')") ?? JSValue(undefinedIn: ctx)
            } catch let error as MiniAppFileSystemError {
                Self.throwJSError(ctx: ctx, error: error)
                return JSValue(undefinedIn: ctx)
            } catch {
                Self.throwJSError(ctx: ctx, name: "Error", message: error.localizedDescription)
                return JSValue(undefinedIn: ctx)
            }
        }
        context.setObject(getDirHandleFn, forKeyedSubscript: "__fsGetDirectoryHandle")

        // __fsEntries(dirPath) -> [{name, kind}]
        let entriesFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let dirPath = args.count > 0 ? (args[0].toString() ?? "") : ""
            do {
                let items = try fs.entries(at: dirPath)
                var jsonItems: [[String: String]] = []
                for item in items {
                    jsonItems.append(["name": item.name, "kind": item.kind])
                }
                if let jsonData = try? JSONSerialization.data(withJSONObject: jsonItems),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    return ctx.evaluateScript("JSON.parse('\(Self.escapeJS(jsonStr))')") ?? JSValue(undefinedIn: ctx)
                }
                return ctx.evaluateScript("[]") ?? JSValue(undefinedIn: ctx)
            } catch {
                return ctx.evaluateScript("[]") ?? JSValue(undefinedIn: ctx)
            }
        }
        context.setObject(entriesFn, forKeyedSubscript: "__fsEntries")

        // __fsRemoveEntry(path, recursive)
        let removeEntryFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let path = args.count > 0 ? (args[0].toString() ?? "") : ""
            let recursive = args.count > 1 ? args[1].toBool() : false
            do {
                try fs.removeEntry(at: path, recursive: recursive)
            } catch let error as MiniAppFileSystemError {
                Self.throwJSError(ctx: ctx, error: error)
            } catch {
                Self.throwJSError(ctx: ctx, name: "Error", message: error.localizedDescription)
            }
            return JSValue(undefinedIn: ctx)
        }
        context.setObject(removeEntryFn, forKeyedSubscript: "__fsRemoveEntry")

        // __fsRead(path) -> string
        let readFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let path = args.count > 0 ? (args[0].toString() ?? "") : ""
            do {
                let content = try fs.readFile(at: path)
                return JSValue(string: content, in: ctx)
            } catch let error as MiniAppFileSystemError {
                Self.throwJSError(ctx: ctx, error: error)
                return JSValue(undefinedIn: ctx)
            } catch {
                Self.throwJSError(ctx: ctx, name: "Error", message: error.localizedDescription)
                return JSValue(undefinedIn: ctx)
            }
        }
        context.setObject(readFn, forKeyedSubscript: "__fsRead")

        // __fsWrite(path, content)
        let writeFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let path = args.count > 0 ? (args[0].toString() ?? "") : ""
            let content = args.count > 1 ? (args[1].toString() ?? "") : ""
            do {
                try fs.writeFile(at: path, content: content)
            } catch let error as MiniAppFileSystemError {
                Self.throwJSError(ctx: ctx, error: error)
            } catch {
                Self.throwJSError(ctx: ctx, name: "Error", message: error.localizedDescription)
            }
            return JSValue(undefinedIn: ctx)
        }
        context.setObject(writeFn, forKeyedSubscript: "__fsWrite")

        // __fsSize(path) -> number
        let sizeFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let path = args.count > 0 ? (args[0].toString() ?? "") : ""
            do {
                let size = try fs.fileSize(at: path)
                return JSValue(double: Double(size), in: ctx)
            } catch {
                return JSValue(double: 0, in: ctx)
            }
        }
        context.setObject(sizeFn, forKeyedSubscript: "__fsSize")
    }

    // MARK: - Helpers

    private static func escapeJS(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }

    private static func throwJSError(ctx: JSContext, error: MiniAppFileSystemError) {
        throwJSError(ctx: ctx, name: error.name, message: error.message)
    }

    private static func throwJSError(ctx: JSContext, name: String, message: String) {
        ctx.evaluateScript("(function() { var e = new Error('\(escapeJS(message))'); e.name = '\(escapeJS(name))'; throw e; })()")
    }
}
#endif
