import Foundation
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
