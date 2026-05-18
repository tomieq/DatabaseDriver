import Foundation

struct ServerHandshake {
    let scramble: Data
    let authPluginName: String
}

final class MySQLProtocol {
    let socket: NetworkSocket
    private var sequence: UInt8 = 0

    func resetSequence() {
        self.sequence = 0
    }

    init(socket: NetworkSocket) {
        self.socket = socket
    }

    func readPacket() throws -> [UInt8] {
        let header = try socket.readExactly(4)
        let headerBytes = [UInt8](header)
        let len = Int(headerBytes[0]) | (Int(headerBytes[1]) << 8) | (Int(headerBytes[2]) << 16)
        let seq = headerBytes[3]
        _ = seq // sequence from server
        if len == 0 { return [] }
        let payload = try socket.readExactly(len)
        return [UInt8](payload)
    }

    func writePacket(_ payload: [UInt8]) throws {
        let len = payload.count
        var header = [UInt8](repeating: 0, count: 4)
        header[0] = UInt8(len & 0xFF)
        header[1] = UInt8((len >> 8) & 0xFF)
        header[2] = UInt8((len >> 16) & 0xFF)
        header[3] = self.sequence
        self.sequence &+= 1
        var data = Data(header)
        data.append(contentsOf: payload)
        try self.socket.writeAll(data)
    }

    func readGreeting() throws -> ServerHandshake {
        let pkt = try readPacket()
        var idx = 0
        guard pkt.count > 0 else { throw NSError(domain: "MySQLProtocol", code: 1, userInfo: nil) }
        idx += 1 // protocol
        // server version (null-terminated)
        let verStart = idx
        while idx < pkt.count && pkt[idx] != 0 { idx += 1 }
        let ver = String(bytes: pkt[verStart..<idx], encoding: .utf8) ?? ""
        idx += 1
        // connection id
        idx += 4
        // auth-plugin-data-part-1 (8 bytes)
        let part1 = Data(pkt[idx..<(idx + 8)])
        idx += 8
        idx += 1 // filler
        // capability flags (lower)
        let capLower = UInt16(pkt[idx]) | (UInt16(pkt[idx + 1]) << 8)
        idx += 2
        // charset
        idx += 1
        // status
        idx += 2
        // capability upper
        let capUpper = UInt16(pkt[idx]) | (UInt16(pkt[idx + 1]) << 8)
        idx += 2
        let capability = UInt32(capUpper) << 16 | UInt32(capLower)
        var authPluginDataLen = 0
        if capability & 0x00008000 != 0 { // CLIENT_PLUGIN_AUTH
            authPluginDataLen = Int(pkt[idx])
        }
        idx += 1
        idx += 10 // reserved
        var part2 = Data()
        if authPluginDataLen > 0 {
            let len2 = max(13, authPluginDataLen - 8)
            if idx + len2 <= pkt.count {
                part2 = Data(pkt[idx..<(idx + len2)])
                idx += len2
            }
        } else if idx < pkt.count {
            // try read remaining up to null before plugin name
            let remStart = idx
            while idx < pkt.count && pkt[idx] != 0 { idx += 1 }
            if idx > remStart {
                part2 = Data(pkt[remStart..<idx])
            }
        }
        var pluginName = "mysql_native_password"
        if idx < pkt.count {
            // skip null if present
            if pkt[idx] == 0 { idx += 1 }
            let nameStart = idx
            while idx < pkt.count && pkt[idx] != 0 { idx += 1 }
            if idx > nameStart {
                pluginName = String(bytes: pkt[nameStart..<idx], encoding: .utf8) ?? pluginName
            }
        }
        let scramble = part1 + part2
        return ServerHandshake(scramble: scramble, authPluginName: pluginName)
    }

    static func authResponse(password: String, scramble: Data) -> Data {
        if password.isEmpty { return Data() }
        let p = [UInt8](password.utf8)
        let sha1 = SHA1.hash(data: Data(p))
        let sha1sha1 = SHA1.hash(data: sha1)
        var concat = Data()
        concat.append(scramble)
        concat.append(sha1sha1)
        let stage3 = SHA1.hash(data: concat)
        var out = Data(count: sha1.count)
        for i in 0..<sha1.count {
            out[i] = sha1[i] ^ stage3[i]
        }
        return out
    }

    func sendAuth(username: String, authResponse: Data, database: String?, pluginName: String) throws {
        var payload = [UInt8]()
        let capability: UInt32 = 0x0000A685 // CLIENT_PROTOCOL_41 | CLIENT_SECURE_CONNECTION | CLIENT_LONG_FLAG | CLIENT_PLUGIN_AUTH | CLIENT_CONNECT_WITH_DB
        payload.append(UInt8(capability & 0xFF))
        payload.append(UInt8((capability >> 8) & 0xFF))
        payload.append(UInt8((capability >> 16) & 0xFF))
        payload.append(UInt8((capability >> 24) & 0xFF))
        // max packet
        payload.append(contentsOf: [0, 0, 0, 0])
        // charset
        payload.append(33)
        // reserved 23 bytes
        payload.append(contentsOf: [UInt8](repeating: 0, count: 23))
        // username
        payload.append(contentsOf: Array(username.utf8))
        payload.append(0)
        // auth response length + data
        payload.append(UInt8(authResponse.count))
        payload.append(contentsOf: [UInt8](authResponse))
        if let db = database {
            payload.append(contentsOf: Array(db.utf8))
            payload.append(0)
        }
        // plugin name
        payload.append(contentsOf: Array(pluginName.utf8))
        payload.append(0)
        try self.writePacket(payload)
    }

    func sendQuery(sql: String) throws {
        var payload = [UInt8]()
        payload.append(0x03) // COM_QUERY
        payload.append(contentsOf: Array(sql.utf8))
        try self.writePacket(payload)
    }

    static func parseErrorPacket(_ pkt: [UInt8]) -> (Int, String) {
        // 0xFF, error-code(2), sql-state-marker '#', sql-state(5), message
        if pkt.count < 3 { return (0, "unknown error") }
        let code = Int(pkt[1]) | (Int(pkt[2]) << 8)
        var msg = ""
        if pkt.count > 3 {
            msg = String(bytes: pkt[3...], encoding: .utf8) ?? ""
        }
        return (code, msg)
    }

    static func readLengthEncodedInt(_ data: [UInt8], offset: inout Int) -> (Int, Int) {
        if offset >= data.count { return (0, 0) }
        let fb = data[offset]
        offset += 1
        if fb < 0xFB { return (Int(fb), 1) }
        if fb == 0xFC {
            let v = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2
            return (v, 3)
        }
        if fb == 0xFD {
            let v = Int(data[offset]) | (Int(data[offset + 1]) << 8) | (Int(data[offset + 2]) << 16)
            offset += 3
            return (v, 4)
        }
        if fb == 0xFE {
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(data[offset + i]) << (8 * i) }
            offset += 8
            return (Int(v), 9)
        }
        return (0, 0)
    }

    static func parseColumnPacket(_ pkt: [UInt8]) -> String {
        // column packet contains multiple length-encoded strings; name is 5th or 7th depending; to be simple, parse all sequential strings and take the 4th or 5th
        var idx = 0
        func readLenString() -> String {
            if idx >= pkt.count { return "" }
            let first = pkt[idx]
            if first == 0xFB { idx += 1; return "" }
            var off = idx
            let (len, used) = self.readLengthEncodedInt(pkt, offset: &off)
            if used == 1 && pkt[idx] < 0xFB {
                // single byte length
                let s = String(bytes: pkt[(idx + 1)..<(idx + 1 + len)], encoding: .utf8) ?? ""
                idx = idx + 1 + len
                return s
            }
            // fallback: read until null
            var start = idx
            while idx < pkt.count && pkt[idx] != 0 { idx += 1 }
            let s = String(bytes: pkt[start..<idx], encoding: .utf8) ?? ""
            idx += 1
            return s
        }
        // read catalog, db, table, org_table, name
        let _ = readLenString()
        let _ = readLenString()
        let _ = readLenString()
        let _ = readLenString()
        let name = readLenString()
        return name
    }

    static func parseRowPacket(_ pkt: [UInt8], columnCount: Int) -> [String] {
        var idx = 0
        var row: [String] = []
        for _ in 0..<columnCount {
            if idx >= pkt.count { row.append(""); continue }
            let b = pkt[idx]
            if b == 0xFB { idx += 1; row.append(""); continue }
            var off = idx
            let (len, _) = self.readLengthEncodedInt(pkt, offset: &off)
            // if single-byte length
            if pkt[idx] < 0xFB {
                let s = String(bytes: pkt[(idx + 1)..<(idx + 1 + len)], encoding: .utf8) ?? ""
                row.append(s)
                idx = idx + 1 + len
                continue
            }
            // fallback
            row.append("")
        }
        return row
    }
}
