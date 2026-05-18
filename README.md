# DatabaseDriver

Thin MySQL/MariaDB client written in Swift. The library uses the MySQL text protocol directly and keeps dependencies limited to `SwiftExtensions` and `swift-crypto`.

## Usage

```swift
import DatabaseDriver

let client = DatabaseClient(config: DatabaseConfig(
	host: "127.0.0.1",
	port: 3306,
	user: "root",
	password: "secret",
	database: "app"
))

try client.connect()
defer { client.disconnect() }

let insert = try client.execute("INSERT INTO users(name) VALUES ('alice')")
print(insert.affectedRows)
print(insert.lastInsertID)

let result = try client.execute("SELECT id, name FROM users")
for row in result.rows {
	print(row.string("name") ?? "")
}

let rows = try client.query("SELECT name FROM users")
print(rows.first?["name"] ?? "")
```

`execute(_:)` returns a `QueryResult` with columns, rows, affected row count, and last inserted id. `query(_:)` is a convenience wrapper for string-only result sets.

## Platform support

The package targets macOS 10.15+, iOS 13+, and Linux. SHA-256 authentication uses `swift-crypto`; sockets use the platform POSIX APIs behind a small internal wrapper.

Test helpers and CI

- Run unit tests:

```bash
make unit
```

- Run integration tests locally (requires Docker):

```bash
make integration
# or
sh ./scripts/run_integration_tests.sh
```

Integration tests are skipped by default; the test checks `RUN_DOCKER_INTEGRATION=1`.
