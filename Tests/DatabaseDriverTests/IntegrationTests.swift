import XCTest
@testable import DatabaseDriver

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
                if out.contains("ready for connections") || out.contains("ready for connection"), out.contains("port: 3306") {
                    ready = true
                    break
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(ready, "MySQL container did not become ready in time")

        // Attempt full MySQL handshake via client
        let cfg = DatabaseConfig(host: "127.0.0.1", port: 3307, user: "root", password: "")
        let client = DatabaseClient(config: cfg)
        try client.connect()

        // Run simple DB commands
        try client.execute("CREATE DATABASE IF NOT EXISTS testdb")
        try client.execute("USE testdb")
        try client.execute("DROP TABLE IF EXISTS t")
        try client.execute("CREATE TABLE t(id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(64), nickname VARCHAR(64) NULL)")
        let insert = try client.execute("INSERT INTO t (name, nickname) VALUES ('alice', NULL)")
        XCTAssertEqual(insert.affectedRows, 1)
        XCTAssertGreaterThan(insert.lastInsertID, 0)

        let rows = try client.query("SELECT name FROM t WHERE name='alice'")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["name"], "alice")

        let result = try client.execute("SELECT id, name, nickname FROM t WHERE id=\(insert.lastInsertID)")
        XCTAssertTrue(result.isResultSet)
        XCTAssertEqual(result.columns.map(\.name), ["id", "name", "nickname"])
        XCTAssertEqual(result.rows.first?.string("name"), "alice")
        XCTAssertEqual(result.rows.first?["nickname"], .null)

        client.disconnect()
    }
}
