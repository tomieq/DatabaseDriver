# DatabaseDriver

DatabaseDriver is a pure Swift MySQL/MariaDB client. It speaks the MySQL text protocol directly, supports Swift 6 structured concurrency call sites, and offers a small type-safe SQL layer.

## Contents

- [Installation](#installation)
- [Getting Started](#getting-started)
- [Connecting to MySQL](#connecting-to-mysql)
- [Executing Raw SQL](#executing-raw-sql)
- [Building Type-Safe SQL](#building-type-safe-sql)
- [Creating Tables and Indexes](#creating-tables-and-indexes)
- [Inserting Rows](#inserting-rows)
- [Selecting Rows](#selecting-rows)
- [Aggregate Scalar Queries](#aggregate-scalar-queries)
- [Updating Rows](#updating-rows)
- [Deleting Rows](#deleting-rows)
- [Transactions and Savepoints](#transactions-and-savepoints)
- [Codable Types](#codable-types)
- [Connection Pools](#connection-pools)
- [Async API](#async-api)
- [Type Mapping](#type-mapping)
- [Error Handling](#error-handling)

## Installation

Add DatabaseDriver to your package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/tomieq/DatabaseDriver", branch: "master")
]
```

Then add the product to your target:

```swift
targets: [
    .executableTarget(
        name: "App",
        dependencies: [
            .product(name: "DatabaseDriver", package: "DatabaseDriver")
        ]
    )
]
```

Import the module where you use it:

```swift
import DatabaseDriver
```

## Getting Started

```swift
let db = Connection(config: DatabaseConfig(
    host: "127.0.0.1",
    port: 3306,
    user: "root",
    password: "secret",
    database: "app"
))

try db.connect()
defer { db.disconnect() }

try db.run("CREATE TABLE IF NOT EXISTS users (id BIGINT AUTO_INCREMENT PRIMARY KEY, email TEXT NOT NULL)")

let insert = try db.run("INSERT INTO users (email) VALUES ('alice@example.com')")
print(insert.lastInsertID)

let rows = try db.prepare("SELECT id, email FROM users")
for row in rows {
    print(row.integer("id") ?? 0, row.string("email") ?? "")
}
```

`Connection` represents one MySQL session. A single connection serializes commands internally and can be shared safely, but one socket can still execute only one statement at a time. Server applications should usually use `ConnectionPool`.

## Connecting to MySQL

Create a configuration with the host, port, credentials, and optional default database:

```swift
let config = DatabaseConfig(
    host: "127.0.0.1",
    port: 3306,
    user: "app",
    password: "secret",
    database: "app"
)
```

Open and close a connection explicitly:

```swift
let db = Connection(config: config)
try db.connect()
defer { db.disconnect() }
```

Reconnect after a transport failure or when MySQL closes an idle connection:

```swift
try db.reconnect()
```

The same methods are also available as async wrappers:

```swift
try await db.connect()
await db.disconnect()
```

## Executing Raw SQL

Use raw SQL when you need full MySQL syntax or quick one-off statements.

```swift
let result = try db.execute("SELECT id, email FROM users")
```

`run(_:)` is an alias matching SQLite.swift naming:

```swift
try db.run("UPDATE users SET email='alice@example.com' WHERE id=1")
```

`execute(_:)` and `run(_:)` return `QueryResult`:

```swift
let result = try db.run("INSERT INTO users (email) VALUES ('bob@example.com')")
print(result.affectedRows)
print(result.lastInsertID)
```

For result sets, use `prepare(_:)` to get rows:

```swift
for row in try db.prepare("SELECT id, email FROM users") {
    print(row.integer("id") ?? 0)
    print(row.string("email") ?? "")
}
```

Use `scalar(_:)` for the first value of the first row:

```swift
let count = try db.scalar("SELECT COUNT(*) FROM users")
print(count?.stringValue ?? "0")
```

Use `query(_:)` for a simple string-only dictionary view:

```swift
let rows = try db.query("SELECT email FROM users")
print(rows.first?["email"] ?? "")
```

Raw SQL strings are sent through the MySQL text protocol. The query builder escapes literals for generated statements, but raw SQL is your responsibility.

## Building Type-Safe SQL

DatabaseDriver has `Table` and `Expression` types for constructing SQL without hand-assembling identifiers and values.

```swift
let users = Table("users")
let id = users.column("id", as: Int64.self)
let email = users.column("email", as: String.self)
let name = users.column("name", as: String?.self)
let enabled = users.column("enabled", as: Bool.self)
```

You can also create unqualified expressions directly, which is useful for examples and selected columns:

```swift
let id = Expression<Int64>("id")
let email = Expression<String>("email")
let count = Expression<Int>(literal: "COUNT(*)")
```

Identifiers are quoted with MySQL backticks and values are escaped as SQL literals.

### Predicates

```swift
users.filter(id == 1)
users.where(name != nil)
users.where((enabled == true) && (id >= 10))
users.where(email.like("%@example.com"))
users.where([1, 2, 3].contains(id))
users.where(!(enabled == false))
```

Supported predicate operators include `==`, `!=`, `>`, `>=`, `<`, `<=`, `===`, `!==`, `&&`, `||`, and prefix `!`. Optional `nil` comparisons generate `IS NULL` or `IS NOT NULL`.

### Ordering and Limits

```swift
users.select().order(email)
users.select().order(email.asc)
users.select().order(email.desc, id.asc)
users.select().limit(20)
users.select().limit(20, offset: 40)
```

For compatibility with older DatabaseDriver code, `email.asc()` and `email.desc()` also work.

### Grouping

Use `group(by:)` to emit `GROUP BY` clauses on selected columns or expressions.

```swift
let latestTemperatures = temperatures
    .select(id.max, area, value)
    .group(by: area)
    .order(area.asc)

print(latestTemperatures.sql)
// SELECT max(`temperatures`.`id`), `temperatures`.`area`, `temperatures`.`value` FROM `temperatures` GROUP BY `temperatures`.`area` ORDER BY `temperatures`.`area` ASC
```

## Creating Tables and Indexes

Create tables with a schema builder:

```swift
try db.run(users.create(ifNotExists: true) { table in
    table.column(id, primaryKey: .autoIncrement)
    table.column(email, type: .varchar(255), unique: true)
    table.column(name)
    table.column(enabled, defaultValue: true)
    table.check(id > 0)
})
```

Common column options:

```swift
table.column(id, primaryKey: true)
table.column(id, primaryKey: .autoIncrement)
table.column(email, unique: true)
table.column(enabled, defaultValue: true)
table.column(name, notNull: false)
table.column(email, type: .varchar(255))
table.column(Expression<DatabaseValue>("metadata"), type: .custom("JSON"))
```

Table constraints are available in the `create` closure:

```swift
table.primaryKey(id)
table.unique(email, name)
table.check(id > 0)
table.foreignKey([id], references: Table("accounts"), [Expression<Int64>("id")], delete: .cascade)
```

Create and drop indexes:

```swift
try db.run(users.createIndex(email))
try db.run(users.createIndex(email, named: "users_email_idx", unique: true))
try db.run(users.createIndex(email, ifNotExists: true))

try db.run(users.dropIndex(email))
try db.run(users.dropIndex(email, ifExists: true))
```

Drop tables:

```swift
try db.run(users.drop(ifExists: true))
```

### Creating Tables from Swift Types

Flat Swift types can be reflected into column definitions. The `Type.self` overload requires `DatabaseSchemaRepresentable` so the library can create a sample instance:

```swift
struct UserSchema: DatabaseSchemaRepresentable {
    let id: Int64
    let email: String
    let nickname: String?

    init() {
        self.id = 0
        self.email = ""
        self.nickname = nil
    }
}

try db.run(Table("users").create(from: UserSchema.self, ifNotExists: true))
```

You can also pass a sample value:

```swift
try db.run(Table("users").create(from: UserSchema()))
```

Add overrides in the closure overload:

```swift
try db.run(Table("users").create(from: UserSchema.self) { table in
    table.column(named: "metadata", type: .custom("JSON"), notNull: false)
})
```

## Inserting Rows

Use `<-` setters, similar to SQLite.swift:

```swift
let insert = try db.run(users.insert(
    email <- "alice@example.com",
    name <- "Alice",
    enabled <- true
))

print(insert.lastInsertID)
```

Optional values become `NULL`:

```swift
try db.run(users.insert(name <- nil))
```

Calling `insert()` without setters generates `DEFAULT VALUES`:

```swift
try db.run(users.insert())
```

## Selecting Rows

Prepare a select query:

```swift
let rows = try db.prepare(
    users
        .select(id, email, name)
        .where(enabled == true)
        .order(email.asc)
        .limit(20)
)
```

Read values from `DatabaseRow` by column name:

```swift
for row in rows {
    let userID = row.integer("id")
    let emailAddress = row.string("email")
    let nickname = row["nickname"]
}
```

Use `pluck(_:)` for the first row:

```swift
if let user = try db.pluck(users.where(id == 1)) {
    print(user.string("email") ?? "")
}
```

Use `scalar(_:)` with generated SQL too:

```swift
let count: Int = try db.scalar(users.count)
print(count)
```

## Aggregate Scalar Queries

Aggregate helpers build single-column scalar queries and can be passed directly to `scalar(_:)`. The typed overload decodes the returned `DatabaseValue` into the aggregate's Swift result type.

```swift
let count: Int = try db.scalar(users.count)
// SELECT count(*) FROM `users`

let activeCount: Int = try db.scalar(users.where(enabled == true).count)
// SELECT count(*) FROM `users` WHERE `users`.`enabled` = TRUE
```

Aggregate helpers now preserve the rest of the select query, so filtering, grouping, ordering, and limits remain intact when you derive a scalar query.

Column `count` counts non-`NULL` values in that column. Prefix an expression with `distinct` to emit `DISTINCT` inside the aggregate.

```swift
let namedUsers: Int = try db.scalar(users.select(name.count))
// SELECT count(`users`.`name`) FROM `users`

let uniqueNames: Int = try db.scalar(users.select(name.distinct.count))
// SELECT count(DISTINCT `users`.`name`) FROM `users`
```

Comparable columns support `max` and `min`; numeric columns support `average`, `sum`, and `total`.

```swift
let newestID: Int64? = try db.scalar(users.select(id.max))
// SELECT max(`users`.`id`) FROM `users`

let firstID: Int64? = try db.scalar(users.select(id.min))
// SELECT min(`users`.`id`) FROM `users`

let averageBalance: Double? = try db.scalar(users.select(balance.average))
// SELECT avg(`users`.`balance`) FROM `users`

let balanceSum: Double? = try db.scalar(users.select(balance.sum))
// SELECT sum(`users`.`balance`) FROM `users`

let balanceTotal: Double = try db.scalar(users.select(balance.total))
// SELECT total(`users`.`balance`) FROM `users`
```

`average`, `sum`, `min`, and `max` return optionals because an empty result can produce `NULL`. `total` returns `Double` and decodes `NULL` as `0.0`.

## Updating Rows

Update all rows by calling `update` on a table:

```swift
try db.run(users.update(enabled <- true))
```

Scope updates with `filter` or `where`:

```swift
try db.run(
    users
        .update(name <- "Alice")
        .where(id == 1)
)
```

Convenience setters can use the current column value:

```swift
let balance = users.column("balance", as: Double.self)
let loginCount = users.column("login_count", as: Int.self)

try db.run(users.update(balance += 10.0).where(id == 1))
try db.run(users.update(balance -= 5.0).where(id == 1))
try db.run(users.update(loginCount++).where(id == 1))
try db.run(users.update(loginCount--).where(id == 1))
```

`run(_:)` returns a `QueryResult`; `affectedRows` contains the number of changed rows reported by MySQL.

## Deleting Rows

Delete all rows:

```swift
try db.run(users.delete())
```

Delete selected rows:

```swift
try db.run(users.delete().where(id == 1))
try db.run(users.delete().filter(name == nil))
```

## Transactions and Savepoints

Use `transaction` to run a group of statements atomically. The transaction commits when the block returns and rolls back when the block throws.

```swift
try db.transaction {
    try db.run(users.insert(email <- "betty@example.com"))
    try db.run(users.insert(email <- "cathy@example.com"))
}
```

The generic return value is preserved:

```swift
let insertedID = try db.transaction {
    let result = try db.run(users.insert(email <- "dan@example.com"))
    return result.lastInsertID
}
```

Use `savepoint` inside larger transactions or when you need nested rollback behavior:

```swift
try db.transaction {
    try db.run(users.insert(email <- "outer@example.com"))

    try db.savepoint("optional_user") {
        try db.run(users.insert(email <- "inner@example.com"))
    }
}
```

On a pool, the closure receives the single checked-out connection that owns the transaction:

```swift
try pool.transaction { db in
    try db.run(users.insert(email <- "pooled@example.com"))
    try db.run(users.update(enabled <- true).where(email == "pooled@example.com"))
}
```

## Codable Types

Flat `Codable` values can be inserted, updated, and decoded from rows. Property names should match column names.

```swift
struct User: Codable, Equatable {
    let id: Int64?
    let email: String
    let nickname: String?
    let enabled: Bool
}

struct UserPatch: Encodable {
    let nickname: String?
}
```

Insert an `Encodable` value:

```swift
let result = try db.run(try users.insert(User(
    id: nil,
    email: "alice@example.com",
    nickname: nil,
    enabled: true
)))
```

Update from an `Encodable` value:

```swift
try db.run(
    try users
        .update(UserPatch(nickname: "ally"))
        .where(id == Int64(result.lastInsertID))
)
```

Decode selected rows:

```swift
let decoded = try db.prepare(
    users
        .select(id, email, users.column("nickname", as: String?.self), enabled)
        .where(id == Int64(result.lastInsertID)),
    as: User.self
)
```

You can also decode manually from rows or query results:

```swift
let user = try row.decode(User.self)
let users = try result.decode(User.self)
```

Codable support is intentionally table-shaped. Top-level models must use keyed containers. Nested keyed containers, unkeyed containers, and single-value top-level rows are not mapped into columns automatically.

Foundation `Date` is supported natively. DatabaseDriver encodes and decodes `Date` values as Unix timestamps in seconds since 1970 stored in MySQL `DOUBLE` columns.

```swift
struct Event: Codable, Equatable {
    let name: String
    let occurredAt: Date
}

let events = Table("events")
let occurredAt = events.column("occurredAt", as: Date.self)

try db.run(events.create(ifNotExists: true) { table in
    table.column(events.column("id", as: Int64.self), primaryKey: .autoIncrement)
    table.column(events.column("name", as: String.self))
    table.column(occurredAt)
})
```

## Connection Pools

Use `ConnectionPool` in server applications to bound concurrency and reuse MySQL sessions.

```swift
let pool = ConnectionPool(
    config: DatabaseConfig(
        host: "127.0.0.1",
        port: 3306,
        user: "app",
        password: "secret",
        database: "app"
    ),
    maxConnections: 10
)

defer { pool.close() }

let rows = try pool.prepare("SELECT id, email FROM users")
```

Use one-shot methods for independent statements:

```swift
try pool.run("INSERT INTO audit_log(message) VALUES ('started')")
let value = try pool.scalar("SELECT COUNT(*) FROM users")
```

Use `withConnection` when statements must share session state, temporary tables, `USE database`, `LAST_INSERT_ID()`, or explicit MySQL session variables:

```swift
try pool.withConnection { db in
    try db.run("SET @request_id = 'abc'")
    try db.run("INSERT INTO audit_log(message) VALUES (@request_id)")
}
```

Use `pool.transaction` for transaction blocks:

```swift
try pool.transaction { db in
    try db.run("UPDATE accounts SET balance = balance - 10 WHERE id = 1")
    try db.run("UPDATE accounts SET balance = balance + 10 WHERE id = 2")
}
```

Pool behavior:

- Connections are opened lazily.
- Idle connections are reused.
- SQL errors returned by MySQL do not discard a connection.
- Transport and protocol failures discard a connection.
- `close()` disconnects idle connections and prevents new checkouts.

## Async API

Most connection and pool operations have async variants:

```swift
try await db.connect()
let rows = try await db.prepare(users.where(enabled == true))
try await db.transaction {
    try await db.run(users.insert(email <- "async@example.com"))
}
await db.disconnect()
```

Pool APIs are also available asynchronously:

```swift
let result = try await pool.run("SELECT 1")

try await pool.transaction { db in
    try await db.run(users.insert(email <- "pooled-async@example.com"))
}

await pool.close()
```

The current async implementation wraps the blocking POSIX socket code on a utility queue. This keeps async call sites clean and avoids blocking the caller task directly, but it is not a fully non-blocking network stack.

## Type Mapping

Rows expose typed helpers and raw `DatabaseValue` values:

```swift
row.string("email")
row.bool("enabled")
row.integer("id")
row.unsignedInteger("quota")
row.double("score")
row.bytes("payload")
row["created_at"]
```

`DatabaseValue` cases:

- `.null`
- `.bool(Bool)`
- `.integer(Int64)`
- `.unsignedInteger(UInt64)`
- `.double(Double)`
- `.decimal(String)`
- `.string(String)`
- `.bytes(Data)`
- `.date(DatabaseDate)`
- `.time(DatabaseTime)`
- `.dateTime(DatabaseDateTime)`

Native `Date` values are represented through `.double(Double)` using Unix seconds since 1970.

Column metadata is available through `DatabaseColumn`:

```swift
let result = try db.run("SELECT * FROM users")
for column in result.columns {
    print(column.name, column.type, column.isUnsigned, column.isBinary, column.length)
}
```

Schema inference maps Swift values to MySQL column types:

- `Bool` -> `BOOL`
- signed integers -> `BIGINT` or related integer types
- unsigned integers -> unsigned integer types
- `Double` -> `DOUBLE`
- `Date` -> `DOUBLE`
- `String` -> `TEXT` by default
- `Data` -> `BLOB`
- `DatabaseDate` -> `DATE`
- `DatabaseTime` -> `TIME`
- `DatabaseDateTime` -> `DATETIME`

Use explicit `SQLColumnType` values when you need MySQL-specific choices:

```swift
.varchar(255)
.decimal(precision: 10, scale: 2)
.dateTime(fractionalSecondsPrecision: 6)
.custom("JSON")
```

## Error Handling

DatabaseDriver throws `ConnectionError` for connection, protocol, and server failures:

```swift
do {
    try db.run("SELECT * FROM definitely_missing_table")
} catch ConnectionError.serverError(let code, let message) {
    print("MySQL error", code, message)
} catch ConnectionError.connectionFailed(let message) {
    print("Connection failed", message)
} catch {
    print("Unexpected error", error)
}
```

`ConnectionError.serverError` means MySQL returned an error packet. The connection can usually be reused after normal SQL errors. Protocol or transport errors should be treated as connection failures; `ConnectionPool` discards those connections automatically.
