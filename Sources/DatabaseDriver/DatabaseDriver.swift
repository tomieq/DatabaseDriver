import Foundation

public struct DatabaseConfig {
    public var host: String
    public var port: Int
    public var user: String
    public var password: String
    public var database: String?

    public init(host: String = "127.0.0.1", port: Int = 3306, user: String, password: String, database: String? = nil) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
    }
}

public enum DatabaseError: Error {
    case connectionFailed(String)
    case protocolError(String)
    case serverError(code: Int, message: String)
}

public final class DatabaseClient {
    let config: DatabaseConfig
    var socket: NetworkSocket?
    var sequence: UInt8 = 0

    public init(config: DatabaseConfig) {
        self.config = config
    }

    public func connect() throws {
        let s = try NetworkSocket()
        try s.connect(host: self.config.host, port: self.config.port)
        self.socket = s
        try self.performHandshake()
    }

    public func disconnect() {
        try? self.socket?.close()
        self.socket = nil
    }

    deinit {
        disconnect()
    }

    func performHandshake() throws {
        guard let socket else { throw DatabaseError.connectionFailed("no socket") }
        let proto = MySQLProtocol(socket: socket)
        proto.resetSequence()
        let serverHandshake = try proto.readGreeting()
        let authResp = MySQLProtocol.authResponse(password: self.config.password, scramble: serverHandshake.scramble)
        proto.resetSequence()
        try proto.sendAuth(username: self.config.user, authResponse: authResp, database: self.config.database, pluginName: serverHandshake.authPluginName)
        let resp = try proto.readPacket()
        if resp.count > 0 {
            let first = resp[0]
            if first == 0x00 {
                // OK
                return
            } else if first == 0xFF {
                let (code, msg) = MySQLProtocol.parseErrorPacket(resp)
                throw DatabaseError.serverError(code: code, message: msg)
            }
        }
        throw DatabaseError.protocolError("unexpected auth response")
    }

    public func query(_ sql: String) throws -> [[String: String]] {
        guard let socket else { throw DatabaseError.connectionFailed("no socket") }
        let proto = MySQLProtocol(socket: socket)
        proto.resetSequence()
        try proto.sendQuery(sql: sql)
        let first = try proto.readPacket()
        if first.count == 0 { return [] }
        if first[0] == 0x00 { return [] } // OK packet
        if first[0] == 0xFF {
            let (code, msg) = MySQLProtocol.parseErrorPacket(first)
            throw DatabaseError.serverError(code: code, message: msg)
        }
        // Result set: first packet is column count (len-encoded-int)
        var offset = 0
        let (columnCount, used) = MySQLProtocol.readLengthEncodedInt(first, offset: &offset)
        var columns: [String] = []
        for _ in 0..<columnCount {
            let colPacket = try proto.readPacket()
            let col = MySQLProtocol.parseColumnPacket(colPacket)
            columns.append(col)
        }
        _ = try proto.readPacket() // EOF
        var rows: [[String: String]] = []
        while true {
            let pkt = try proto.readPacket()
            if pkt.count > 0, pkt[0] == 0xFE, pkt.count < 9 { break } // EOF
            let row = MySQLProtocol.parseRowPacket(pkt, columnCount: columns.count)
            var dict: [String: String] = [:]
            for (i, col) in columns.enumerated() {
                dict[col] = row[i]
            }
            rows.append(dict)
        }
        return rows
    }
}
