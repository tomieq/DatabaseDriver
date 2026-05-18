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
        let out = String(data: outData, encoding: .utf8) ?? ""
        return (task.terminationStatus, out.trimmingCharacters(in: .whitespacesAndNewlines))
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
            try? shell(["docker", "rm", "-f", containerId])
        }

        // Wait for MySQL to accept connections by scanning container logs and attempting TCP connect
        let deadline = Date().addingTimeInterval(120)
        var ready = false
        while Date() < deadline {
            // check logs for readiness message
            let logs = try shell(["docker", "logs", containerId])
            if logs.0 == 0 {
                let out = logs.1.lowercased()
                if out.contains("ready for connections") || out.contains("ready for connection") {
                    ready = true
                    break
                }
            }
            // also try TCP connect to forwarded port
            do {
                let sock = try NetworkSocket()
                try sock.connect(host: "127.0.0.1", port: 3307)
                try? sock.close()
                ready = true
                break
            } catch {
                // not ready yet
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(ready, "MySQL container did not become ready in time")

        // Attempt full MySQL handshake via client
        let cfg = DatabaseConfig(host: "127.0.0.1", port: 3307, user: "root", password: "")
        let client = DatabaseClient(config: cfg)
        try client.connect()

        // Run simple DB commands
        try client.query("CREATE DATABASE IF NOT EXISTS testdb")
        try client.query("USE testdb")
        try client.query("CREATE TABLE IF NOT EXISTS t(id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(64))")
        try client.query("INSERT INTO t (name) VALUES ('alice')")
        let rows = try client.query("SELECT name FROM t WHERE name='alice'")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["name"], "alice")

        client.disconnect()
    }
}
