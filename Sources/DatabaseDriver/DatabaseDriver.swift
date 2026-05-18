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

public enum DatabaseValue: Equatable, Sendable, CustomStringConvertible {
    case null
    case string(String)

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var description: String {
        switch self {
        case .null: return "NULL"
        case let .string(value): return value
        }
    }
}

public struct DatabaseColumn: Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct DatabaseRow: Equatable, Sendable {
    public let values: [DatabaseValue]
    public let valuesByColumn: [String: DatabaseValue]

    public init(values: [DatabaseValue], valuesByColumn: [String: DatabaseValue]) {
        self.values = values
        self.valuesByColumn = valuesByColumn
    }

    public subscript(_ column: String) -> DatabaseValue? {
        self.valuesByColumn[column]
    }

    public func string(_ column: String) -> String? {
        self[column]?.stringValue
    }
}

public struct QueryResult: Equatable, Sendable {
    public let columns: [DatabaseColumn]
    public let rows: [DatabaseRow]
    public let affectedRows: Int
    public let lastInsertID: Int

    public init(columns: [DatabaseColumn], rows: [DatabaseRow], affectedRows: Int, lastInsertID: Int) {
        self.columns = columns
        self.rows = rows
        self.affectedRows = affectedRows
        self.lastInsertID = lastInsertID
    }

    public var isResultSet: Bool { !self.columns.isEmpty }
}

public final class DatabaseClient {
    let config: DatabaseConfig
    var socket: NetworkSocket?
    var sequence: UInt8 = 0
    var proto: MySQLProtocol?

    public init(config: DatabaseConfig) {
        self.config = config
    }

    public func connect() throws {
        let s = try NetworkSocket()
        try s.connect(host: self.config.host, port: self.config.port)
        self.socket = s
        let p = MySQLProtocol(socket: s)
        p.resetSequence()
        self.proto = p
        try self.performHandshake()
    }

    public func disconnect() {
        try? self.socket?.close()
        self.socket = nil
        self.proto = nil
    }

    deinit {
        disconnect()
    }

    func performHandshake() throws {
        guard self.socket != nil else { throw DatabaseError.connectionFailed("no socket") }
        guard let proto else { throw DatabaseError.connectionFailed("no protocol") }
        let serverHandshake = try proto.readGreeting()
        let authResp: Data
        if serverHandshake.authPluginName == "caching_sha2_password" {
            authResp = MySQLProtocol.authResponseCachingSHA2(password: self.config.password, scramble: serverHandshake.scramble)
        } else {
            authResp = MySQLProtocol.authResponseNative(password: self.config.password, scramble: serverHandshake.scramble)
        }
        try proto.sendAuth(username: self.config.user, authResponse: authResp, database: self.config.database, pluginName: serverHandshake.authPluginName)
        var resp = try proto.readPacket()
        if resp.count > 0 {
            let first = resp[0]
            if first == 0x00 {
                // OK
                proto.resetSequence()
                return
            } else if first == 0xFF {
                let (code, msg) = MySQLProtocol.parseErrorPacket(resp)
                throw DatabaseError.serverError(code: code, message: msg)
            } else if first == 0xFE {
                // Auth switch request: server may request full auth for plugin (e.g., caching_sha2_password)
                // Format: 0xFE, plugin_name (NUL), scramble
                var idx = 1
                // read plugin name
                var plugin = ""
                while idx < resp.count, resp[idx] != 0 {
                    plugin.append(Character(UnicodeScalar(resp[idx])))
                    idx += 1
                }
                if idx < resp.count, resp[idx] == 0 { idx += 1 }
                let scramble = Data(resp[idx..<resp.count])
                let fullResp: Data
                if plugin.contains("caching_sha2") {
                    fullResp = MySQLProtocol.authResponseCachingSHA2(password: self.config.password, scramble: scramble)
                } else {
                    fullResp = MySQLProtocol.authResponseNative(password: self.config.password, scramble: scramble)
                }
                // send auth switch response (length-prefixed)
                var respBytes = [UInt8]()
                respBytes.append(UInt8(fullResp.count & 0xFF))
                respBytes.append(contentsOf: [UInt8](fullResp))
                try proto.writePacket(respBytes)
                // read final response
                resp = try proto.readPacket()
                if resp.count > 0 {
                    if resp[0] == 0x00 { proto.resetSequence(); return }
                    if resp[0] == 0xFF {
                        let (code, msg) = MySQLProtocol.parseErrorPacket(resp)
                        throw DatabaseError.serverError(code: code, message: msg)
                    }
                }
            }
        }
        throw DatabaseError.protocolError("unexpected auth response")
    }

    @discardableResult
    public func execute(_ sql: String) throws -> QueryResult {
        guard self.socket != nil else { throw DatabaseError.connectionFailed("no socket") }
        guard let proto else { throw DatabaseError.connectionFailed("no protocol") }
        try proto.sendQuery(sql: sql)
        let first = try proto.readPacket()
        if first.count == 0 { return QueryResult(columns: [], rows: [], affectedRows: 0, lastInsertID: 0) }
        if first[0] == 0x00 {
            let ok = MySQLProtocol.parseOKPacket(first)
            return QueryResult(columns: [], rows: [], affectedRows: ok.affectedRows, lastInsertID: ok.lastInsertID)
        }
        if first[0] == 0xFF {
            let (code, msg) = MySQLProtocol.parseErrorPacket(first)
            throw DatabaseError.serverError(code: code, message: msg)
        }
        // Result set: first packet is column count (len-encoded-int)
        var offset = 0
        let (columnCount, _) = MySQLProtocol.readLengthEncodedInt(first, offset: &offset)
        var columns: [DatabaseColumn] = []
        for _ in 0..<columnCount {
            let colPacket = try proto.readPacket()
            columns.append(DatabaseColumn(name: MySQLProtocol.parseColumnPacket(colPacket)))
        }
        _ = try proto.readPacket() // EOF
        var rows: [DatabaseRow] = []
        while true {
            let pkt = try proto.readPacket()
            if pkt.count > 0, pkt[0] == 0xFE, pkt.count < 9 { break } // EOF
            let row = MySQLProtocol.parseRowPacket(pkt, columnCount: columns.count)
            var dict: [String: DatabaseValue] = [:]
            for (i, col) in columns.enumerated() {
                dict[col.name] = row[i]
            }
            rows.append(DatabaseRow(values: row, valuesByColumn: dict))
        }
        return QueryResult(columns: columns, rows: rows, affectedRows: 0, lastInsertID: 0)
    }

    public func query(_ sql: String) throws -> [[String: String]] {
        try self.execute(sql).rows.map { row in
            row.valuesByColumn.compactMapValues(\.stringValue)
        }
    }
}
