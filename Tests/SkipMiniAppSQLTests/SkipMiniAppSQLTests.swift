// Copyright 2025-2026 Skip
// SPDX-License-Identifier: MPL-2.0

import XCTest
import Foundation
@testable import SkipMiniAppSQL
@testable import SkipMiniAppModel

@available(macOS 13, *)
final class SkipMiniAppSQLTests: XCTestCase {

    func testModuleTypeCreation() throws {
        #if !SKIP
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("sql-test-\(UUID().uuidString)")
        let moduleType = MiniAppModuleType.sql(baseDirectory: tmpDir)
        XCTAssertTrue(moduleType.module is MiniAppSQLModule)
        try? FileManager.default.removeItem(at: tmpDir)
        #endif
    }

    #if !SKIP

    // MARK: - CRUD via Runtime

    func testCreateTableAndInsert() throws {
        let env = try makeSQLRuntime()
        defer { env.cleanup() }

        env.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)', [])")
        let changes = env.runtime.evaluateScriptAsDouble("miniapp.db.exec(\"INSERT INTO t (name) VALUES ('Alice')\", []).changes")
        XCTAssertEqual(changes, 1.0)
        let lastId = env.runtime.evaluateScriptAsDouble("miniapp.db.exec(\"INSERT INTO t (name) VALUES ('Bob')\", []).lastInsertRowId")
        XCTAssertEqual(lastId, 2.0)
    }

    func testQueryReturnsRows() throws {
        let env = try makeSQLRuntime()
        defer { env.cleanup() }

        env.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE items (id INTEGER PRIMARY KEY, val TEXT)', [])")
        env.runtime.evaluateScript("miniapp.db.exec(\"INSERT INTO items (val) VALUES ('one')\", [])")
        env.runtime.evaluateScript("miniapp.db.exec(\"INSERT INTO items (val) VALUES ('two')\", [])")

        XCTAssertEqual(env.runtime.evaluateScriptAsDouble("miniapp.db.query('SELECT * FROM items ORDER BY id', []).length"), 2.0)
        XCTAssertEqual(env.runtime.evaluateScript("miniapp.db.query('SELECT * FROM items ORDER BY id', [])[0].val"), "one")
        XCTAssertEqual(env.runtime.evaluateScript("miniapp.db.query('SELECT * FROM items ORDER BY id', [])[1].val"), "two")
    }

    func testParameterBinding() throws {
        let env = try makeSQLRuntime()
        defer { env.cleanup() }

        env.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE p (id INTEGER PRIMARY KEY, name TEXT, score REAL)', [])")
        env.runtime.evaluateScript("miniapp.db.exec('INSERT INTO p (name, score) VALUES (?, ?)', ['Bob', 95.5])")

        XCTAssertEqual(env.runtime.evaluateScript("miniapp.db.query('SELECT name FROM p WHERE name = ?', ['Bob'])[0].name"), "Bob")
        XCTAssertEqual(env.runtime.evaluateScriptAsDouble("miniapp.db.query('SELECT score FROM p', [])[0].score"), 95.5)
    }

    func testNullParameters() throws {
        let env = try makeSQLRuntime()
        defer { env.cleanup() }

        env.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE n (id INTEGER PRIMARY KEY, val TEXT)', [])")
        env.runtime.evaluateScript("miniapp.db.exec('INSERT INTO n (val) VALUES (?)', [null])")

        // SQL NULL maps to JS null; evaluateScript converts null to the string "null"
        // or returns nil depending on the runtime's handling
        let val = env.runtime.evaluateScript("miniapp.db.query('SELECT val FROM n', [])[0].val")
        let isNullish = val == nil || val == "null"
        XCTAssertTrue(isNullish, "Expected null value but got: \(val ?? "nil")")
    }

    func testUpdateAndDelete() throws {
        let env = try makeSQLRuntime()
        defer { env.cleanup() }

        env.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE u (id INTEGER PRIMARY KEY, done INTEGER DEFAULT 0)', [])")
        env.runtime.evaluateScript("miniapp.db.exec('INSERT INTO u DEFAULT VALUES', [])")
        env.runtime.evaluateScript("miniapp.db.exec('INSERT INTO u DEFAULT VALUES', [])")

        XCTAssertEqual(env.runtime.evaluateScriptAsDouble("miniapp.db.exec('UPDATE u SET done = 1 WHERE id = 1', []).changes"), 1.0)
        XCTAssertEqual(env.runtime.evaluateScriptAsDouble("miniapp.db.query('SELECT done FROM u WHERE id = 1', [])[0].done"), 1.0)
        XCTAssertEqual(env.runtime.evaluateScriptAsDouble("miniapp.db.exec('DELETE FROM u WHERE id = 2', []).changes"), 1.0)
        XCTAssertEqual(env.runtime.evaluateScriptAsDouble("miniapp.db.query('SELECT COUNT(*) as cnt FROM u', [])[0].cnt"), 1.0)
    }

    func testEmptyQueryResult() throws {
        let env = try makeSQLRuntime()
        defer { env.cleanup() }

        env.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE e (id INTEGER PRIMARY KEY)', [])")
        XCTAssertEqual(env.runtime.evaluateScriptAsDouble("miniapp.db.query('SELECT * FROM e', []).length"), 0.0)
    }

    func testIntegerTypes() throws {
        let env = try makeSQLRuntime()
        defer { env.cleanup() }

        env.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE i (id INTEGER PRIMARY KEY, big INTEGER)', [])")
        env.runtime.evaluateScript("miniapp.db.exec('INSERT INTO i (big) VALUES (?)', [1000000])")
        XCTAssertEqual(env.runtime.evaluateScriptAsDouble("miniapp.db.query('SELECT big FROM i', [])[0].big"), 1000000.0)
    }

    func testMultipleInserts() throws {
        let env = try makeSQLRuntime()
        defer { env.cleanup() }

        env.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE m (id INTEGER PRIMARY KEY, val TEXT)', [])")
        env.runtime.evaluateScript("""
            for (var i = 0; i < 10; i++) {
                miniapp.db.exec('INSERT INTO m (val) VALUES (?)', ['item' + i]);
            }
        """)
        XCTAssertEqual(env.runtime.evaluateScriptAsDouble("miniapp.db.query('SELECT COUNT(*) as cnt FROM m', [])[0].cnt"), 10.0)
        XCTAssertEqual(env.runtime.evaluateScript("miniapp.db.query('SELECT val FROM m WHERE id = 5', [])[0].val"), "item4")
    }

    // MARK: - Error Handling

    func testInvalidSQLReturnsNil() throws {
        let env = try makeSQLRuntime()
        defer { env.cleanup() }

        // Invalid SQL triggers an exception; runtime.evaluateScript returns nil on exception
        let result = env.runtime.evaluateScript("miniapp.db.exec('NOT VALID SQL', [])")
        XCTAssertNil(result, "Invalid SQL should result in nil (exception set on context)")
    }

    // MARK: - Security Tests

    func testDatabaseSandboxing() throws {
        // Two runtimes with separate base dirs are completely isolated
        let env1 = try makeSQLRuntime(appId: "app.one")
        defer { env1.cleanup() }
        let env2 = try makeSQLRuntime(appId: "app.two")
        defer { env2.cleanup() }

        env1.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE shared (val TEXT)', [])")
        env1.runtime.evaluateScript("miniapp.db.exec(\"INSERT INTO shared (val) VALUES ('from-one')\", [])")

        // app.two should not have the 'shared' table — query returns nil (exception)
        let result = env2.runtime.evaluateScript("miniapp.db.query('SELECT * FROM shared', [])")
        XCTAssertNil(result, "app.two should not see app.one's tables")
    }

    func testPathTraversalPrevention() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("sql-security-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let maliciousId = "../../etc/passwd"
        let env = try makeSQLRuntime(appId: maliciousId, baseDir: tmpDir)
        defer { env.cleanup() }

        env.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE test (id INTEGER)', [])")

        let safeId = maliciousId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
        let dbFile = tmpDir.appendingPathComponent(safeId).appendingPathComponent("app.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbFile.path), "Database should be inside sandboxed directory")
    }

    func testSlashInAppIdSanitized() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("sql-slash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = try makeSQLRuntime(appId: "com/evil/path", baseDir: tmpDir)
        defer { env.cleanup() }
        env.runtime.evaluateScript("miniapp.db.exec('CREATE TABLE x (id INTEGER)', [])")

        let dbFile = tmpDir.appendingPathComponent("com_evil_path").appendingPathComponent("app.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbFile.path))
    }

    // MARK: - Helpers

    struct SQLRuntimeEnv {
        let runtime: MiniAppRuntime
        let tmpDir: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: tmpDir)
        }
    }

    func makeSQLRuntime(appId: String = "test.sql.app", baseDir: URL? = nil) throws -> SQLRuntimeEnv {
        let tmpDir = baseDir ?? FileManager.default.temporaryDirectory.appendingPathComponent("sql-rt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Build a minimal .ma package
        let pkgPath = tmpDir.appendingPathComponent("test.ma").path
        let manifest = MiniAppManifest(
            appId: appId,
            name: "SQL Test",
            icons: [],
            version: MiniAppVersion(code: 1, name: "1.0.0"),
            platformVersion: MiniAppPlatformVersion(minCode: 1),
            pages: ["pages/index/index"]
        )
        let builder = try MiniAppPackageBuilder(path: pkgPath)
        try builder.addManifest(manifest)
        try builder.addEntry(path: "app.js", string: "App({})", compression: 0)
        try builder.addEntry(path: "pages/index/index.html", string: "<html></html>", compression: 0)
        try builder.addEntry(path: "pages/index/index.js", string: "Page({})", compression: 0)
        try builder.finalize()

        let package = MiniAppPackage(path: pkgPath)
        let runtime = MiniAppRuntime(package: package, manifest: manifest, modules: [.sql(baseDirectory: tmpDir)])
        runtime.start()

        return SQLRuntimeEnv(runtime: runtime, tmpDir: tmpDir)
    }
    #endif
}
