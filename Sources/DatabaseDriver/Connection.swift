import Foundation

public enum ConnectionError: Error, Sendable {
    case connectionFailed(String)
    case protocolError(String)
    case serverError(code: Int, message: String)
}

public final class Connection: @unchecked Sendable {
    let config: DatabaseConfig
    var socket: NetworkSocket?
    var sequence: UInt8 = 0
    var proto: MySQLProtocol?
    private let lock = NSRecursiveLock()

    public init(config: DatabaseConfig) {
        self.config = config
    }

    public var isConnected: Bool {
        self.withLock {
            self.socket != nil && self.proto != nil
        }
    }

    public func connect() throws {
        try self.withLock {
            let s = try NetworkSocket()
            do {
                try s.connect(host: self.config.host, port: self.config.port)
                self.socket = s
                let p = MySQLProtocol(socket: s)
                p.resetSequence()
                self.proto = p
                try self.performHandshake()
            } catch {
                try? s.close()
                self.socket = nil
                self.proto = nil
                throw error
            }
        }
    }

    public func connect() async throws {
        try await runBlocking {
            try self.connect()
        }
    }

    public func reconnect() throws {
        self.disconnect()
        try self.connect()
    }

    public func reconnect() async throws {
        try await runBlocking {
            try self.reconnect()
        }
    }

    public func disconnect() {
        self.withLock {
            try? self.socket?.close()
            self.socket = nil
            self.proto = nil
        }
    }

    public func disconnect() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                self.disconnect()
                continuation.resume()
            }
        }
    }

    deinit {
        disconnect()
    }

    func performHandshake() throws {
        guard self.socket != nil else { throw ConnectionError.connectionFailed("no socket") }
        guard let proto else { throw ConnectionError.connectionFailed("no protocol") }
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
            } else if first == 0x01 {
                try self.handleAuthMoreData(resp, handshake: serverHandshake, proto: proto)
                proto.resetSequence()
                return
            } else if first == 0xFF {
                let (code, msg) = MySQLProtocol.parseErrorPacket(resp)
                throw ConnectionError.serverError(code: code, message: msg)
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
                let respBytes = fullResp.count.uInt8.data
                    .appending(fullResp.data)
                    .array
                try proto.writePacket(respBytes)
                // read final response
                resp = try proto.readPacket()
                if resp.count > 0 {
                    if resp[0] == 0x00 { proto.resetSequence(); return }
                    if resp[0] == 0xFF {
                        let (code, msg) = MySQLProtocol.parseErrorPacket(resp)
                        throw ConnectionError.serverError(code: code, message: msg)
                    }
                }
            }
        }
        throw ConnectionError.protocolError("unexpected auth response")
    }

    private func handleAuthMoreData(_ packet: [UInt8], handshake: ServerHandshake, proto: MySQLProtocol) throws {
        guard packet.count == 2 else {
            throw ConnectionError.protocolError("unexpected auth more data packet")
        }

        switch packet[1] {
        case CachingSHA2Password.fastAuthSuccess:
            let finalResponse = try proto.readPacket()
            try self.handleFinalAuthResponse(finalResponse, proto: proto)
        case CachingSHA2Password.performFullAuthentication:
            try proto.writePacket([CachingSHA2Password.requestPublicKey])
            let publicKeyPacket = try proto.readPacket()
            let publicKeyPayload: Data
            if publicKeyPacket.first == 0x01 {
                publicKeyPayload = Data(publicKeyPacket.dropFirst())
            } else {
                publicKeyPayload = Data(publicKeyPacket)
            }
            let encryptedPassword = try CachingSHA2Password.encryptedPassword(
                self.config.password,
                scramble: handshake.scramble,
                publicKeyPEM: publicKeyPayload
            )
            try proto.writePacket(encryptedPassword.array)
            let finalResponse = try proto.readPacket()
            try self.handleFinalAuthResponse(finalResponse, proto: proto)
        default:
            throw ConnectionError.protocolError("unexpected auth more data status")
        }
    }

    private func handleFinalAuthResponse(_ packet: [UInt8], proto: MySQLProtocol) throws {
        guard let first = packet.first else {
            throw ConnectionError.protocolError("empty auth response")
        }

        if first == 0x00 {
            return
        }
        if first == 0xFF {
            let (code, msg) = MySQLProtocol.parseErrorPacket(packet)
            throw ConnectionError.serverError(code: code, message: msg)
        }

        throw ConnectionError.protocolError("unexpected auth response")
    }

    @discardableResult
    public func execute(_ sql: String) throws -> QueryResult {
        try self.withLock {
            guard self.socket != nil else { throw ConnectionError.connectionFailed("no socket") }
            guard let proto else { throw ConnectionError.connectionFailed("no protocol") }
            try proto.sendQuery(sql: sql)
            let first = try proto.readPacket()
            if first.count == 0 { return QueryResult(columns: [], rows: [], affectedRows: 0, lastInsertID: 0) }
            if first[0] == 0x00 {
                let ok = MySQLProtocol.parseOKPacket(first)
                return QueryResult(columns: [], rows: [], affectedRows: ok.affectedRows, lastInsertID: ok.lastInsertID)
            }
            if first[0] == 0xFF {
                let (code, msg) = MySQLProtocol.parseErrorPacket(first)
                throw ConnectionError.serverError(code: code, message: msg)
            }
            // Result set: first packet is column count (len-encoded-int)
            var offset = 0
            let (columnCount, _) = MySQLProtocol.readLengthEncodedInt(first, offset: &offset)
            var columns: [DatabaseColumn] = []
            for _ in 0..<columnCount {
                let colPacket = try proto.readPacket()
                columns.append(MySQLProtocol.parseColumnPacket(colPacket))
            }
            _ = try proto.readPacket() // EOF
            var rows: [DatabaseRow] = []
            while true {
                let pkt = try proto.readPacket()
                if pkt.count > 0, pkt[0] == 0xFE, pkt.count < 9 { break } // EOF
                let row = MySQLProtocol.parseRowPacket(pkt, columns: columns)
                var dict: [String: DatabaseValue] = [:]
                for (i, col) in columns.enumerated() {
                    dict[col.name] = row[i]
                }
                rows.append(DatabaseRow(values: row, valuesByColumn: dict))
            }
            return QueryResult(columns: columns, rows: rows, affectedRows: 0, lastInsertID: 0)
        }
    }

    @discardableResult
    public func execute(_ sql: String) async throws -> QueryResult {
        try await runBlocking {
            try self.execute(sql)
        }
    }

    public func query(_ sql: String) throws -> [[String: String]] {
        try self.execute(sql).rows.map { row in
            row.valuesByColumn.compactMapValues(\.stringValue)
        }
    }

    public func query(_ sql: String) async throws -> [[String: String]] {
        try await runBlocking {
            try self.query(sql)
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        self.lock.lock()
        defer { self.lock.unlock() }
        return try body()
    }
}
