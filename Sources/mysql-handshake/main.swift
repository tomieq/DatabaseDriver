import Foundation
import DatabaseDriver

let argv = CommandLine.arguments
let host = argv.count > 1 ? argv[1] : "127.0.0.1"
let port = argv.count > 2 ? Int(argv[2]) ?? 3307 : 3307
let user = argv.count > 3 ? argv[3] : "root"
let password = argv.count > 4 ? argv[4] : ""
let scenario = argv.count > 5 ? argv[5] : "smoke"

print("mysql-handshake: connecting to \(host):\(port) as \(user) (password length=\(password.count))")

func makeClient() -> Connection {
    Connection(config: DatabaseConfig(host: host, port: port, user: user, password: password))
}

func runSmoke() throws {
    let client = makeClient()
    try client.connect()
    defer { client.disconnect() }
    print("connect() succeeded — handshake completed")
    let rows = try client.query("SELECT 1 AS one")
    print("smoke: query returned rows: \(rows)")
}

func runFull() throws {
    let client = makeClient()
    try client.connect()
    defer { client.disconnect() }
    print("connect() succeeded — handshake completed")
    try client.execute("CREATE DATABASE IF NOT EXISTS testdb")
    try client.execute("USE testdb")
    try client.execute("CREATE TABLE IF NOT EXISTS t(id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(64))")
    try client.execute("INSERT INTO t (name) VALUES ('alice')")
    let rows = try client.query("SELECT name FROM t WHERE name='alice'")
    print("full: selected rows: \(rows)")
}

do {
    switch scenario {
    case "smoke": try runSmoke()
    case "full": try runFull()
    default:
        print("unknown scenario: \(scenario). use 'smoke' or 'full'")
        exit(2)
    }
} catch {
    print("client error: \(error)")
    exit(1)
}

print("Done")
