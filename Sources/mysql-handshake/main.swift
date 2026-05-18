import Foundation
import DatabaseDriver

let argv = CommandLine.arguments
let host = argv.count > 1 ? argv[1] : "127.0.0.1"
let port = argv.count > 2 ? Int(argv[2]) ?? 3307 : 3307
let user = argv.count > 3 ? argv[3] : "root"
let password = argv.count > 4 ? argv[4] : ""

print("mysql-handshake: connecting to \(host):\(port) as \(user) (password length=\(password.count))")
let cfg = DatabaseConfig(host: host, port: port, user: user, password: password)
let client = DatabaseClient(config: cfg)
do {
    try client.connect()
    print("connect() succeeded — handshake completed")
    // Try a simple query to exercise COM_QUERY
    let rows = try client.query("SELECT 1 AS one")
    print("query returned rows: \(rows)")
    client.disconnect()
} catch {
    print("client error: \(error)")
    client.disconnect()
    exit(1)
}

print("Done")
