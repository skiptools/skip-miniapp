// Copyright 2025-2026 Skip
// SPDX-License-Identifier: MPL-2.0

#if !SKIP_BRIDGE
import Foundation
import SkipScript
import SkipSQL
import SkipSQLCore
import SkipMiniAppModel

extension MiniAppModuleType {
    /// SQL module with a persistent database in the given base directory.
    public static func sql(baseDirectory: URL) -> MiniAppModuleType {
        return MiniAppModuleType(MiniAppSQLModule(baseDirectory: baseDirectory))
    }
}

/// MiniApp module providing SQLite database access in the Logic Layer.
///
/// Exposes `skip.db` with methods:
/// - `exec(sql, params?)` - Execute a statement; returns `{changes, lastInsertRowId}`
/// - `query(sql, params?)` - Execute a SELECT; returns array of row objects keyed by column name
///
/// Parameters are passed as a JS array and bound positionally (`?` placeholders).
/// Each miniapp gets its own sandboxed database file.
public final class MiniAppSQLModule: MiniAppModule {
    public let baseDirectory: URL
    private var databases: [String: SQLContext] = [:]

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        super.init()
    }

    /// Open or return the cached database for the given app ID.
    /// The app ID is sanitized to prevent path traversal.
    private func getOrCreateDatabase(for appId: String) throws -> SQLContext {
        if let db = databases[appId] {
            return db
        }
        let safeId = appId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
        let dir = baseDirectory.appendingPathComponent(safeId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("app.sqlite").path
        let flags: SQLContext.OpenFlags = [SQLContext.OpenFlags.readWrite, SQLContext.OpenFlags.create]
        let db = try SQLContext(path: path, flags: flags, configuration: SQLiteConfiguration.platform)
        db.foreignKeysEnabled = true
        databases[appId] = db
        return db
    }

    override public func registerInRuntime(_ runtime: MiniAppRuntime) {
        let context = runtime.jsContext
        guard let namespace = runtime.namespaceObject else { return }
        let sqlModule = self
        let appId = runtime.manifest.appId

        // __dbExec(sql, params?) -> { changes, lastInsertRowId }
        let execFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let sql = args.count > 0 ? (args[0].toString() ?? "") : ""
            let paramsVal: JSValue? = args.count > 1 ? args[1] : nil

            do {
                let db = try sqlModule.getOrCreateDatabase(for: appId)
                let params = MiniAppSQLModule.jsToSQLParams(paramsVal, ctx: ctx)
                try db.exec(sql: sql, parameters: params)
                let changes = db.changes
                let lastId = db.lastInsertRowID
                let result = JSValue(newObjectIn: ctx)
                result.setObject(JSValue(double: Double(changes), in: ctx), forKeyedSubscript: "changes")
                result.setObject(JSValue(double: Double(lastId), in: ctx), forKeyedSubscript: "lastInsertRowId")
                return result
            } catch {
                Self.throwJSError(ctx: ctx, message: "\(error)")
                return JSValue(undefinedIn: ctx)
            }
        }
        context.setObject(execFn, forKeyedSubscript: "__dbExec")

        // __dbQuery(sql, params?) -> [{col: val, ...}, ...]
        let queryFn = JSValue(newFunctionIn: context) { ctx, obj, args in
            let sql = args.count > 0 ? (args[0].toString() ?? "") : ""
            let paramsVal: JSValue? = args.count > 1 ? args[1] : nil

            do {
                let db = try sqlModule.getOrCreateDatabase(for: appId)
                let params = MiniAppSQLModule.jsToSQLParams(paramsVal, ctx: ctx)
                let stmt = try db.prepare(sql: sql)
                if !params.isEmpty {
                    try stmt.bind(parameters: params)
                }

                let colNames = stmt.columnNames
                ctx.evaluateScript("var __dbRows = []")
                while try stmt.next() {
                    let row = JSValue(newObjectIn: ctx)
                    for col in 0..<Int(stmt.columnCount) {
                        let name = colNames[col]
                        let val = stmt.value(at: Int32(col))
                        row.setObject(MiniAppSQLModule.sqlToJSValue(val, ctx: ctx), forKeyedSubscript: name)
                    }
                    ctx.setObject(row, forKeyedSubscript: "__dbRow")
                    ctx.evaluateScript("__dbRows.push(__dbRow)")
                }
                try stmt.close()
                let jsRows = ctx.evaluateScript("__dbRows")
                return jsRows ?? JSValue(undefinedIn: ctx)
            } catch {
                Self.throwJSError(ctx: ctx, message: "\(error)")
                return JSValue(undefinedIn: ctx)
            }
        }
        context.setObject(queryFn, forKeyedSubscript: "__dbQuery")

        // Create skip.db namespace
        let dbObj = JSValue(newObjectIn: context)
        dbObj.setObject(execFn, forKeyedSubscript: "exec")
        dbObj.setObject(queryFn, forKeyedSubscript: "query")
        namespace.setObject(dbObj, forKeyedSubscript: "db")
    }

    // MARK: - Helpers

    /// Convert a JS array of parameters to [SQLValue].
    private static func jsToSQLParams(_ jsVal: JSValue?, ctx: JSContext) -> [SQLValue] {
        guard let jsVal = jsVal, !jsVal.isUndefined, !jsVal.isNull else { return [] }
        ctx.setObject(jsVal, forKeyedSubscript: "__dbParams")
        let countVal = ctx.evaluateScript("__dbParams.length")
        let count = countVal != nil ? Int(countVal!.toDouble()) : 0
        var result: [SQLValue] = []
        for i in 0..<count {
            guard let item = ctx.evaluateScript("__dbParams[\(i)]") else {
                result.append(SQLValue.null)
                continue
            }
            if item.isUndefined || item.isNull {
                result.append(SQLValue.null)
            } else if item.isString {
                result.append(SQLValue.text(item.toString() ?? ""))
            } else if item.isBoolean {
                result.append(SQLValue.long(item.toBool() ? 1 : 0))
            } else if item.isNumber {
                let d = item.toDouble()
                let asLong = Int64(d)
                if d == Double(asLong) {
                    result.append(SQLValue.long(asLong))
                } else {
                    result.append(SQLValue.real(d))
                }
            } else {
                result.append(SQLValue.text(item.toString() ?? ""))
            }
        }
        return result
    }

    /// Convert a SQLValue to a JSValue.
    private static func sqlToJSValue(_ val: SQLValue, ctx: JSContext) -> JSValue {
        let t = val.type
        if t == SQLType.null {
            return JSValue(nullIn: ctx)
        } else if t == SQLType.long || t == SQLType.real {
            let numStr = val.description
            let result = ctx.evaluateScript("Number(\(numStr))")
            return result ?? JSValue(nullIn: ctx)
        } else {
            return JSValue(string: val.description, in: ctx)
        }
    }

    private static func escapeForJS(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }

    private static func throwJSError(ctx: JSContext, message: String) {
        ctx.evaluateScript("(function() { throw new Error('\(escapeForJS(message))'); })()")
    }
}
#endif
