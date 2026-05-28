import XCTest
@testable import DatabaseDriver

private final class ConcurrentQueryResults: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64] = []
    private var errors: [Error] = []

    func append(value: Int64) {
        self.lock.lock()
        self.values.append(value)
        self.lock.unlock()
    }

    func append(error: Error) {
        self.lock.lock()
        self.errors.append(error)
        self.lock.unlock()
    }

    func snapshot() -> (values: [Int64], errors: [Error]) {
        self.lock.lock()
        defer { self.lock.unlock() }
        return (self.values, self.errors)
    }
}

private struct CodablePerson: Codable, Equatable {
    let name: String
    let nickname: String?
    let enabled: Bool
    let birthday: DatabaseDate
    let payload: Data
}

private struct CodablePersonPatch: Encodable {
    let nickname: String?
}

private struct SchemaPerson: DatabaseSchemaRepresentable {
    let id: Int64
    let name: String
    let nickname: String?
    let enabled: Bool

    init() {
        self.id = 0
        self.name = ""
        self.nickname = nil
        self.enabled = false
    }
}

final class IntegrationTests: XCTestCase {
    func shell(_ args: [String]) throws -> (Int32, String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return (task.terminationStatus, (out + err).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testMySQLDockerIntegration() throws {
        // Only run integration test when explicitly enabled to avoid CI failures.
        if ProcessInfo.processInfo.environment["RUN_DOCKER_INTEGRATION"] != "1" {
            throw XCTSkip("Integration tests disabled. Set RUN_DOCKER_INTEGRATION=1 to enable.")
        }
        // Check Docker availability
        let which = try shell(["which", "docker"])
        if which.0 != 0 { throw XCTSkip("Docker CLI not found; skipping integration test") }

        // Run mysql container with empty root password allowed
        let run = try shell(["docker", "run", "-d", "-e", "MYSQL_ALLOW_EMPTY_PASSWORD=yes", "-p", "3307:3306", "mysql:9.7.0"])
        XCTAssertEqual(run.0, 0, "docker run failed: \(run.1)")
        let containerId = run.1
        defer {
            _ = try? shell(["docker", "rm", "-f", containerId])
        }

        // Wait for MySQL to accept connections by scanning container logs and attempting TCP connect
        let deadline = Date().addingTimeInterval(120)
        var ready = false
        while Date() < deadline {
            // check logs for readiness message
            let logs = try shell(["docker", "logs", containerId])
            if logs.0 == 0 {
                let out = logs.1.lowercased()
                if out.contains("ready for connections") || out.contains("ready for connection"), out.contains("port: 3306  mysql") {
                    ready = true
                    break
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(ready, "MySQL container did not become ready in time")

        // Attempt full MySQL handshake via client
        let cfg = DatabaseConfig(host: "127.0.0.1", port: 3307, user: "root", password: "")
        let connection = Connection(config: cfg)
        try connection.connect()

        // Run simple DB commands
        try connection.execute("CREATE DATABASE IF NOT EXISTS testdb")
        try connection.execute("USE testdb")
        try connection.execute("DROP TABLE IF EXISTS t")
        try connection.execute("""
        CREATE TABLE t(
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(64),
            nickname VARCHAR(64) NULL,
            signed_value BIGINT,
            unsigned_value BIGINT UNSIGNED,
            decimal_value DECIMAL(10, 2),
            double_value DOUBLE,
            enabled BOOL,
            birthday DATE,
            created_at DATETIME(6),
            elapsed TIME(6),
            payload BLOB
        )
        """)
        let insert = try connection.execute("""
        INSERT INTO t (name, nickname, signed_value, unsigned_value, decimal_value, double_value, enabled, birthday, created_at, elapsed, payload)
        VALUES ('alice', NULL, -42, 42, 1234.50, 3.5, TRUE, '2026-05-18', '2026-05-18 14:30:15.123456', '12:34:56.000001', X'6869')
        """)
        XCTAssertEqual(insert.affectedRows, 1)
        XCTAssertGreaterThan(insert.lastInsertID, 0)

        let rows = try connection.query("SELECT name FROM t WHERE name='alice'")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["name"], "alice")

        let result = try connection.execute("""
        SELECT id, name, nickname, signed_value, unsigned_value, decimal_value, double_value, enabled, birthday, created_at, elapsed, payload
        FROM t WHERE id=\(insert.lastInsertID)
        """)
        XCTAssertTrue(result.isResultSet)
        XCTAssertEqual(result.columns.map(\.name), ["id", "name", "nickname", "signed_value", "unsigned_value", "decimal_value", "double_value", "enabled", "birthday", "created_at", "elapsed", "payload"])
        XCTAssertEqual(result.columns.first { $0.name == "signed_value" }?.type, .bigInteger)
        XCTAssertEqual(result.columns.first { $0.name == "unsigned_value" }?.isUnsigned, true)

        let row = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(row.string("name"), "alice")
        XCTAssertEqual(row["nickname"], .null)
        XCTAssertEqual(row.integer("signed_value"), -42)
        XCTAssertEqual(row.unsignedInteger("unsigned_value"), 42)
        XCTAssertEqual(row["decimal_value"], .decimal("1234.50"))
        XCTAssertEqual(row.double("double_value"), 3.5)
        XCTAssertEqual(row.bool("enabled"), true)
        XCTAssertEqual(row["birthday"], .date(DatabaseDate(year: 2026, month: 5, day: 18)))
        XCTAssertEqual(row["created_at"], .dateTime(DatabaseDateTime(date: DatabaseDate(year: 2026, month: 5, day: 18), time: DatabaseTime(hours: 14, minutes: 30, seconds: 15, microseconds: 123456))))
        XCTAssertEqual(row["elapsed"], .time(DatabaseTime(hours: 12, minutes: 34, seconds: 56, microseconds: 1)))
        XCTAssertEqual(row.bytes("payload"), Data([0x68, 0x69]))

        let table = Table("t")
        let objectID = table.column("id", as: Int64.self)
        let objectName = table.column("name", as: String.self)
        let objectNickname = table.column("nickname", as: String?.self)
        let objectInsert = try connection.run(table.insert(objectName <- "bob", objectNickname <- "bobby"))
        XCTAssertEqual(objectInsert.affectedRows, 1)

        let objectRows = try connection.prepare(
            table
                .filter(objectID == Int64(objectInsert.lastInsertID))
                .select(objectName, objectNickname)
        )
        XCTAssertEqual(objectRows.first?.string("name"), "bob")
        XCTAssertEqual(objectRows.first?.string("nickname"), "bobby")

        let missingNickname: String? = nil
        let objectUpdate = try connection.run(table.update(objectNickname <- missingNickname).filter(objectID == Int64(objectInsert.lastInsertID)))
        XCTAssertEqual(objectUpdate.affectedRows, 1)

        let objectDelete = try connection.run(table.delete().filter(objectNickname == missingNickname))
        XCTAssertGreaterThanOrEqual(objectDelete.affectedRows, 1)

        let codableInsert = try connection.run(try table.insert(CodablePerson(
            name: "carol",
            nickname: "caz",
            enabled: true,
            birthday: DatabaseDate(year: 2026, month: 5, day: 19),
            payload: Data([0x63, 0x61])
        )))
        XCTAssertEqual(codableInsert.affectedRows, 1)

        let codableRows = try connection.prepare(
            table
                .filter(objectID == Int64(codableInsert.lastInsertID))
                .select(objectName, objectNickname, table.column("enabled", as: Bool.self), table.column("birthday", as: DatabaseDate.self), table.column("payload", as: Data.self)),
            as: CodablePerson.self
        )
        XCTAssertEqual(codableRows, [CodablePerson(name: "carol", nickname: "caz", enabled: true, birthday: DatabaseDate(year: 2026, month: 5, day: 19), payload: Data([0x63, 0x61]))])

        let codableUpdate = try connection.run(try table.update(CodablePersonPatch(nickname: nil)).filter(objectID == Int64(codableInsert.lastInsertID)))
        XCTAssertEqual(codableUpdate.affectedRows, 1)
        let decodedAfterUpdate = try connection.prepare(
            table
                .filter(objectID == Int64(codableInsert.lastInsertID))
                .select(objectName, objectNickname, table.column("enabled", as: Bool.self), table.column("birthday", as: DatabaseDate.self), table.column("payload", as: Data.self)),
            as: CodablePerson.self
        )
        XCTAssertEqual(decodedAfterUpdate.first?.nickname, nil)

        let schemaTable = Table("schema_api_users")
        let schemaID = schemaTable.column("id", as: Int64.self)
        let schemaEmail = schemaTable.column("email", as: String.self)
        let schemaName = schemaTable.column("name", as: String?.self)
        let schemaEnabled = schemaTable.column("enabled", as: Bool.self)
        try connection.run(schemaTable.drop(ifExists: true))
        try connection.run(schemaTable.create(ifNotExists: true) { definition in
            definition.column(schemaID, primaryKey: .autoIncrement)
            definition.column(schemaEmail, type: .varchar(255), unique: true)
            definition.column(schemaName)
            definition.column(schemaEnabled, defaultValue: true)
        })
        try connection.run(schemaTable.createIndex(schemaEmail, named: "schema_api_users_email_idx"))
        let schemaInsert = try connection.run(schemaTable.insert(schemaEmail <- "ddl@example.com", schemaName <- nil, schemaEnabled <- true))
        XCTAssertEqual(schemaInsert.affectedRows, 1)
        let schemaRows = try connection.prepare(schemaTable.filter(schemaID == Int64(schemaInsert.lastInsertID)).select(schemaEmail, schemaName, schemaEnabled))
        XCTAssertEqual(schemaRows.first?.string("email"), "ddl@example.com")
        XCTAssertEqual(schemaRows.first?["name"], .null)
        XCTAssertEqual(schemaRows.first?.bool("enabled"), true)
        try connection.run(schemaTable.dropIndex(schemaEmail, named: "schema_api_users_email_idx"))
        try connection.run(schemaTable.drop(ifExists: true))

        let reflectedTable = Table("schema_reflected_users")
        let reflectedID = reflectedTable.column("id", as: Int64.self)
        let reflectedName = reflectedTable.column("name", as: String.self)
        let reflectedNickname = reflectedTable.column("nickname", as: String?.self)
        let reflectedEnabled = reflectedTable.column("enabled", as: Bool.self)
        try connection.run(reflectedTable.drop(ifExists: true))
        try connection.run(reflectedTable.create(from: SchemaPerson.self, ifNotExists: true))
        let reflectedInsert = try connection.run(reflectedTable.insert(reflectedID <- 1, reflectedName <- "reflected", reflectedNickname <- nil, reflectedEnabled <- true))
        XCTAssertEqual(reflectedInsert.affectedRows, 1)
        let reflectedRows = try connection.prepare(reflectedTable.select(reflectedID, reflectedName, reflectedNickname, reflectedEnabled))
        XCTAssertEqual(reflectedRows.first?.integer("id"), 1)
        XCTAssertEqual(reflectedRows.first?.string("name"), "reflected")
        XCTAssertEqual(reflectedRows.first?["nickname"], .null)
        XCTAssertEqual(reflectedRows.first?.bool("enabled"), true)
        try connection.run(reflectedTable.drop(ifExists: true))

        let concurrentResults = ConcurrentQueryResults()
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            do {
                let concurrentResult = try connection.execute("SELECT \(index) AS value")
                let value = concurrentResult.rows.first?.integer("value")
                if let value {
                    concurrentResults.append(value: value)
                } else {
                    concurrentResults.append(error: ConnectionError.protocolError("missing concurrent value"))
                }
            } catch {
                concurrentResults.append(error: error)
            }
        }
        let snapshot = concurrentResults.snapshot()
        XCTAssertTrue(snapshot.errors.isEmpty, "Concurrent queries failed: \(snapshot.errors)")
        XCTAssertEqual(snapshot.values.sorted(), Array(0..<12).map(Int64.init))

        let pool = ConnectionPool(config: cfg, maxConnections: 3)
        defer { pool.close() }
        try pool.execute("USE testdb")
        let pooledResults = ConcurrentQueryResults()
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            do {
                let pooledResult = try pool.execute("SELECT \(index) AS value")
                if let value = pooledResult.rows.first?.integer("value") {
                    pooledResults.append(value: value)
                } else {
                    pooledResults.append(error: ConnectionError.protocolError("missing pooled value"))
                }
            } catch {
                pooledResults.append(error: error)
            }
        }
        let pooledSnapshot = pooledResults.snapshot()
        XCTAssertTrue(pooledSnapshot.errors.isEmpty, "Pooled queries failed: \(pooledSnapshot.errors)")
        XCTAssertEqual(pooledSnapshot.values.sorted(), Array(0..<12).map(Int64.init))

        XCTAssertThrowsError(try pool.execute("SELECT * FROM definitely_missing_table"))
        let afterSQLError = try pool.execute("SELECT 42 AS value")
        XCTAssertEqual(afterSQLError.rows.first?.integer("value"), 42)

        connection.disconnect()
    }
}
