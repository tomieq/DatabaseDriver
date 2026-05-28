# DatabaseDriver

Thin MySQL/MariaDB client written in Swift. The library uses the MySQL text protocol directly and keeps dependencies limited to `SwiftExtensions` and `swift-crypto`.

## Usage

```swift
import DatabaseDriver

let connection = Connection(config: DatabaseConfig(
	host: "127.0.0.1",
	port: 3306,
	user: "root",
	password: "secret",
	database: "app"
))

try connection.connect()
defer { connection.disconnect() }

let insert = try connection.execute("INSERT INTO users(name) VALUES ('alice')")
print(insert.affectedRows)
print(insert.lastInsertID)

let result = try connection.execute("SELECT id, name FROM users")
for row in result.rows {
	print(row.string("name") ?? "")
}

let typed = try connection.execute("SELECT id, enabled, birthday, payload FROM users")
for row in typed.rows {
	let id = row.integer("id")
	let enabled = row.bool("enabled")
	let birthday = row["birthday"]
	let payload = row.bytes("payload")
}

let rows = try connection.query("SELECT name FROM users")
print(rows.first?["name"] ?? "")
```

`execute(_:)` returns a `QueryResult` with columns, rows, affected row count, and last inserted id. `query(_:)` is a convenience wrapper for string-only result sets.

## Object query API

For application code that should not assemble SQL strings by hand, the library also exposes a small Swift query builder. It still produces plain MySQL SQL internally and uses the same `execute(_:)` path.

```swift
let users = Table("users")
let id = users.column("id", as: Int64.self)
let name = users.column("name", as: String.self)
let nickname = users.column("nickname", as: String?.self)
let enabled = users.column("enabled", as: Bool.self)

let insert = try connection.run(users.insert(
	name <- "alice",
	nickname <- nil,
	enabled <- true
))
print(insert.lastInsertID)

let rows = try connection.prepare(
	users
		.filter((enabled == true) && (id >= 1))
		.select(id, name)
		.order(name.asc())
		.limit(20)
)

try connection.run(
	users
		.update(name <- "Alice")
		.filter(id == Int64(insert.lastInsertID))
)

try connection.run(users.delete().filter(nickname == nil))
```

`Table`, `Expression`, comparison operators, `&&`, `||`, `!`, and the assignment operator `<-` are available on macOS and Linux. Values are escaped as SQL literals, identifiers are quoted with MySQL backticks, and `nil` optional values compile to `NULL` / `IS NULL` as appropriate.

### Schema builder

Tables and indexes can also be built without hand-written SQL strings.

```swift
try connection.run(users.create(ifNotExists: true) { table in
	table.column(id, primaryKey: .autoIncrement)
	table.column(name, type: .varchar(255))
	table.column(nickname)
	table.column(enabled, defaultValue: true)
	table.unique(name, nickname)
})

try connection.run(users.createIndex(name, named: "users_name_idx"))

try connection.run(users.dropIndex(name, named: "users_name_idx"))
try connection.run(users.drop(ifExists: true))
```

Column types are inferred from `Expression` where possible: integers, unsigned integers, `Bool`, `Double`, `String`, `Data`, `DatabaseDate`, `DatabaseTime`, and `DatabaseDateTime` map to MySQL column types. Use `type:` for MySQL-specific choices such as `.varchar(255)`, `.decimal(precision:scale:)`, or `.custom("JSON")`. MySQL supports `IF NOT EXISTS` for table creation, but not for `CREATE INDEX` / `DROP INDEX`, so index builders generate MySQL-compatible statements without those clauses.

You can also create a table from a flat Swift type. Swift reflection needs an instance to inspect stored properties, so the `Type.self` form requires a zero-argument initializer through `DatabaseSchemaRepresentable`:

```swift
struct User: DatabaseSchemaRepresentable {
	let id: Int64
	let name: String
	let nickname: String?

	init() {
		self.id = 0
		self.name = ""
		self.nickname = nil
	}
}

try connection.run(Table("car_users").create(from: User.self, ifNotExists: true))
// CREATE TABLE IF NOT EXISTS `car_users` (`id` BIGINT NOT NULL, `name` TEXT NOT NULL, `nickname` TEXT)
```

For models that cannot provide `init()`, pass a sample instance instead:

```swift
try connection.run(Table("car_users").create(from: User(id: 0, name: "", nickname: nil)))
```

`create(from:)` is intentionally a convenience for flat schemas. Use the closure overload to add constraints or override ambiguous/custom columns:

```swift
try connection.run(Table("car_users").create(from: User.self) { table in
	table.column(named: "metadata", type: .custom("JSON"), notNull: false)
})
```

### Codable types

Flat `Codable` models can be inserted, updated, and decoded from selected rows. Property names should match the selected column names.

```swift
struct User: Codable, Equatable {
	let id: Int64?
	let name: String
	let nickname: String?
	let enabled: Bool
}

struct UserPatch: Encodable {
	let nickname: String?
}

let inserted = try connection.run(try users.insert(User(
	id: nil,
	name: "alice",
	nickname: nil,
	enabled: true
)))

let decoded = try connection.prepare(
	users
		.filter(id == Int64(inserted.lastInsertID))
		.select(id, name, nickname, enabled),
	as: User.self
)

try connection.run(
	try users
		.update(UserPatch(nickname: "ally"))
		.filter(id == Int64(inserted.lastInsertID))
)
```

Codable support is intentionally table-shaped: top-level models are keyed containers, nested objects and arrays are not mapped into columns automatically. Optional `nil` stored properties are encoded as SQL `NULL` for inserts and updates.

## Async API

The library exposes both synchronous and async variants. In async server code, prefer the async pool methods:

```swift
let pool = DatabasePool(
	config: DatabaseConfig(user: "app", password: "secret", database: "app"),
	maxConnections: 10
)

let result = try await pool.execute("SELECT id, name FROM users")

try await pool.withConnection { connection in
	try await connection.execute("START TRANSACTION")
	do {
		try await connection.execute("INSERT INTO audit_log(message) VALUES ('started')")
		try await connection.execute("COMMIT")
	} catch {
		try? await connection.execute("ROLLBACK")
		throw error
	}
}

await pool.close()
```

The current async methods are compatibility wrappers around the blocking POSIX socket implementation. They keep Swift concurrency call sites clean and avoid blocking the caller's task directly, but they are not a fully non-blocking network stack yet. Use `DatabasePool` to bound concurrency and avoid funneling all requests through one serialized connection.

## Server-side connection management

`DatabaseClient` represents one MySQL connection. It is safe to share between threads because calls to `connect()`, `disconnect()`, and `execute(_:)` are serialized internally, but a single MySQL socket can still process only one command at a time. In a server application, use one shared `DatabasePool` per database configuration instead of one global `DatabaseClient`.

```swift
let pool = DatabasePool(
	config: DatabaseConfig(
		host: "127.0.0.1",
		port: 3306,
		user: "app",
		password: "secret",
		database: "app"
	),
	maxConnections: 10
)

let users = try pool.execute("SELECT id, name FROM users")

try pool.withConnection { connection in
	try connection.execute("START TRANSACTION")
	do {
		try connection.execute("UPDATE accounts SET balance = balance - 10 WHERE id = 1")
		try connection.execute("UPDATE accounts SET balance = balance + 10 WHERE id = 2")
		try connection.execute("COMMIT")
	} catch {
		try? connection.execute("ROLLBACK")
		throw error
	}
}

pool.close()
```

Recommended pattern:

- Create the pool during application startup and keep it for the lifetime of the process.
- Size `maxConnections` from expected concurrency and MySQL limits. Start small, often near the number of request workers, and keep it below the server's `max_connections` after reserving capacity for migrations, admin tools, and other services.
- Use `pool.execute(_:)` or `pool.query(_:)` for one-shot statements.
- Use `pool.withConnection { ... }` when multiple statements must run on the same connection, for example transactions, temporary tables, session variables, or `LAST_INSERT_ID()` workflows.
- Always close the pool during graceful shutdown with `pool.close()`.

Reconnect behavior:

- New pool connections are opened lazily when demand appears.
- Idle connections are reused.
- SQL errors returned by MySQL, such as syntax errors or missing tables, do not discard the connection.
- Transport/protocol failures discard the connection; the next checkout opens a fresh connection.
- If you manage a raw `DatabaseClient`, call `reconnect()` after a network failure or after MySQL closes an idle connection.

For high-throughput services, prefer many short `pool.execute` calls over sharing one `DatabaseClient` across all requests. Sharing one connection is correct, but it serializes all queries and becomes a bottleneck.

## Type mapping

Column metadata is exposed through `DatabaseColumn.type`, `isUnsigned`, `isBinary`, and `length`. Row values are mapped to `DatabaseValue` cases:

- integer MySQL types: `.integer(Int64)` or `.unsignedInteger(UInt64)`
- `FLOAT` and `DOUBLE`: `.double(Double)`
- `DECIMAL`: `.decimal(String)` to preserve exact precision
- `BOOL`/`TINYINT(1)` and one-byte `BIT`: `.bool(Bool)`
- `DATE`, `TIME`, `DATETIME`, `TIMESTAMP`: `.date`, `.time`, `.dateTime`
- binary `BLOB`/geometry payloads: `.bytes(Data)`
- text, enum, set, json, varchar/string columns: `.string(String)`
- SQL `NULL`: `.null`

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

## Swift Package Manager
```swift
import PackageDescription

let package = Package(
    name: "MyServer",
    platforms: [
        .macOS(.v10_15)
    ],
    dependencies: [
        .package(url: "https://github.com/tomieq/DatabaseDriver", branch: "master")
    ]
)
```
in the target:
```swift
    targets: [
        .executableTarget(
            name: "AppName",
            dependencies: [
                .product(name: "DatabaseDriver", package: "DatabaseDriver")
            ])
    ]
```
