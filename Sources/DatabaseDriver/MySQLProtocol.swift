import Foundation
import SwiftExtensions
import Crypto

final class MySQLProtocol {
    let socket: NetworkSocket
    private var sequence: UInt8 = 0
    private let debug: Bool

    func resetSequence() {
        self.sequence = 0
    }

    init(socket: NetworkSocket) {
        self.socket = socket
        self.debug = ProcessInfo.processInfo.environment["MYSQLPROTO_DEBUG"] == "1"
    }

    func readPacket() throws -> [UInt8] {
        // Read first header/payload, and if server used maximal length (0xFFFFFF)
        // then read continuation packets and concatenate payloads.
        var fullPayload = [UInt8]()
        while true {
            let header = try socket.readExactly(4)
            let headerBytes = header.array
            let len = Int(headerBytes[0]) | (Int(headerBytes[1]) << 8) | (Int(headerBytes[2]) << 16)
            let seq = headerBytes[3]
            // Update shared sequence to server sequence + 1 so next write uses expected id
            self.sequence = seq &+ 1
            if self.debug {
                let hexHeader = headerBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("[mysqlproto] readPacket header: len=\(len) seq=\(seq) -> nextSequence=\(self.sequence) headerHex=\(hexHeader)")
            }
            if len == 0 {
                // empty payload packet
                if fullPayload.isEmpty {
                    return []
                } else {
                    break
                }
            }
            let payload = try socket.readExactly(len)
            if self.debug {
                print("[mysqlproto] readPacket payload(\(len)) firstByte=\(payload.first.map({ String(format: "0x%02X", $0) }) ?? "nil")")
                let hex = [UInt8](payload).map { String(format: "%02X", $0) }.joined(separator: " ")
                print("[mysqlproto] readPacket payload hex: \(hex)")
                if let fb = payload.first, fb == 0xFF {
                    let msg = String(data: payload, encoding: .utf8) ?? "<non-utf8>"
                    print("[mysqlproto] server error payload: \(msg)")
                }
            }
            fullPayload.append(contentsOf: payload.array)
            // if this packet used the maximum payload length, server may send a continuation packet
            if len < 0xFFFFFF {
                break
            }
            // otherwise continue reading next header/payload
        }
        return fullPayload
    }

    func writePacket(_ payload: [UInt8]) throws {
        let len = payload.count
        let header = len.uInt24
            .data
            .swappedBytes
            .appending(self.sequence)
        if self.debug {
            let hexHeader = header.map { String(format: "%02X", $0) }.joined(separator: " ")
            let hexPayload = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[mysqlproto] writePacket header: len=\(len) seq=\(self.sequence) headerHex=\(hexHeader)")
            print("[mysqlproto] writePacket payload hex: \(hexPayload)")
        }
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
        _ = String(bytes: pkt[verStart..<idx], encoding: .utf8) ?? ""
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

    static func authResponseNative(password: String, scramble: Data) -> Data {
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

    static func authResponseCachingSHA2(password: String, scramble: Data) -> Data {
        if password.isEmpty { return Data() }
        func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
        let pData = Data(password.utf8)
        let hash1 = sha256(pData)
        let hash2 = sha256(hash1)
        var concat = Data()
        concat.append(scramble)
        concat.append(hash2)
        let toXor = sha256(concat)
        var out = Data(count: hash1.count)
        for i in 0..<hash1.count {
            out[i] = hash1[i] ^ toXor[i]
        }
        return out
    }

    func sendAuth(username: String, authResponse: Data, database: String?, pluginName: String) throws {
        var payload = [UInt8]()
        // include CLIENT_PLUGIN_AUTH and common flags so server accepts plugin-based auth
        // CLIENT_LONG_PASSWORD | CLIENT_FOUND_ROWS | CLIENT_LONG_FLAG | CLIENT_CONNECT_WITH_DB? | CLIENT_PROTOCOL_41 | CLIENT_TRANSACTIONS | CLIENT_SECURE_CONNECTION | CLIENT_PLUGIN_AUTH
        var capability: UInt32 = 0x0008A207
        if database != nil { capability |= 0x00000008 }
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
        if self.debug {
            let hex = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[mysqlproto] sendAuth payload len=\(payload.count) authRespLen=\(authResponse.count) plugin=\(pluginName)")
            print("[mysqlproto] sendAuth hex: \(hex)")
        }
        try self.writePacket(payload)
    }

    func sendQuery(sql: String) throws {
        // each COM_QUERY should start with client sequence 0
        self.resetSequence()
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

    static func parseOKPacket(_ pkt: [UInt8]) -> (affectedRows: Int, lastInsertID: Int) {
        var offset = 1
        let (affectedRows, _) = self.readLengthEncodedInt(pkt, offset: &offset)
        let (lastInsertID, _) = self.readLengthEncodedInt(pkt, offset: &offset)
        return (affectedRows, lastInsertID)
    }

    static func readLengthEncodedString(_ data: [UInt8], offset: inout Int) -> String? {
        guard let bytes = self.readLengthEncodedBytes(data, offset: &offset) else { return nil }
        return String(data: bytes, encoding: .utf8) ?? ""
    }

    static func readLengthEncodedBytes(_ data: [UInt8], offset: inout Int) -> Data? {
        if offset >= data.count { return Data() }
        if data[offset] == 0xFB {
            offset += 1
            return nil
        }
        let (length, _) = self.readLengthEncodedInt(data, offset: &offset)
        guard offset + length <= data.count else { return Data() }
        let value = Data(data[offset..<(offset + length)])
        offset += length
        return value
    }

    static func parseColumnPacket(_ pkt: [UInt8]) -> DatabaseColumn {
        var idx = 0
        let _ = self.readLengthEncodedString(pkt, offset: &idx)
        let _ = self.readLengthEncodedString(pkt, offset: &idx)
        let _ = self.readLengthEncodedString(pkt, offset: &idx)
        let _ = self.readLengthEncodedString(pkt, offset: &idx)
        let name = self.readLengthEncodedString(pkt, offset: &idx) ?? ""
        let _ = self.readLengthEncodedString(pkt, offset: &idx)
        let _ = self.readLengthEncodedInt(pkt, offset: &idx)

        var characterSet: UInt16 = 0
        var columnLength: UInt32 = 0
        var typeCode: UInt8 = 0xFE
        var flags: UInt16 = 0
        if idx + 10 <= pkt.count {
            characterSet = UInt16(pkt[idx]) | (UInt16(pkt[idx + 1]) << 8)
            idx += 2
            columnLength = UInt32(pkt[idx]) | (UInt32(pkt[idx + 1]) << 8) | (UInt32(pkt[idx + 2]) << 16) | (UInt32(pkt[idx + 3]) << 24)
            idx += 4
            typeCode = pkt[idx]
            idx += 1
            flags = UInt16(pkt[idx]) | (UInt16(pkt[idx + 1]) << 8)
        }

        return DatabaseColumn(
            name: name,
            type: self.columnType(for: typeCode),
            isUnsigned: flags & 0x0020 != 0,
            isBinary: characterSet == 63,
            length: columnLength
        )
    }

    static func parseRowPacket(_ pkt: [UInt8], columns: [DatabaseColumn]) -> [DatabaseValue] {
        var idx = 0
        var row: [DatabaseValue] = []
        for column in columns {
            guard let bytes = readLengthEncodedBytes(pkt, offset: &idx) else {
                row.append(.null)
                continue
            }
            row.append(self.parseValue(bytes, column: column))
        }
        return row
    }

    private static func columnType(for code: UInt8) -> DatabaseColumnType {
        switch code {
        case 0x00, 0xF6: return .decimal
        case 0x01: return .tinyInteger
        case 0x02: return .smallInteger
        case 0x03: return .integer
        case 0x04: return .float
        case 0x05: return .double
        case 0x06: return .null
        case 0x07: return .timestamp
        case 0x08: return .bigInteger
        case 0x09: return .mediumInteger
        case 0x0A, 0x0E: return .date
        case 0x0B: return .time
        case 0x0C: return .dateTime
        case 0x0D: return .year
        case 0x0F: return .varchar
        case 0x10: return .bit
        case 0xF5: return .json
        case 0xF7: return .enumValue
        case 0xF8: return .set
        case 0xF9, 0xFA, 0xFB, 0xFC: return .blob
        case 0xFD: return .varString
        case 0xFE: return .string
        case 0xFF: return .geometry
        default: return .unknown(code)
        }
    }

    private static func parseValue(_ bytes: Data, column: DatabaseColumn) -> DatabaseValue {
        let text = String(data: bytes, encoding: .utf8) ?? ""
        switch column.type {
        case .tinyInteger where column.length == 1:
            return .bool(text != "0")
        case .tinyInteger, .smallInteger, .integer, .mediumInteger, .bigInteger, .year:
            if column.isUnsigned { return .unsignedInteger(UInt64(text) ?? 0) }
            return .integer(Int64(text) ?? 0)
        case .float, .double:
            return .double(Double(text) ?? 0)
        case .decimal:
            return .decimal(text)
        case .date:
            return self.parseDate(text).map(DatabaseValue.date) ?? .string(text)
        case .time:
            return self.parseTime(text).map(DatabaseValue.time) ?? .string(text)
        case .timestamp, .dateTime:
            return self.parseDateTime(text).map(DatabaseValue.dateTime) ?? .string(text)
        case .bit:
            if bytes.count == 1 { return .bool(bytes[bytes.startIndex] != 0) }
            return .bytes(bytes)
        case .blob where column.isBinary, .geometry where column.isBinary:
            return .bytes(bytes)
        default:
            return .string(text)
        }
    }

    private static func parseDate(_ text: String) -> DatabaseDate? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        return DatabaseDate(year: year, month: month, day: day)
    }

    private static func parseTime(_ text: String) -> DatabaseTime? {
        var value = text
        let isNegative = value.first == "-"
        if isNegative { value.removeFirst() }
        let secondParts = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let clockParts = secondParts[0].split(separator: ":", omittingEmptySubsequences: false)
        guard clockParts.count == 3, let hours = Int(clockParts[0]), let minutes = Int(clockParts[1]), let seconds = Int(clockParts[2]) else { return nil }
        let microseconds = secondParts.count == 2 ? Int(secondParts[1].padding(toLength: 6, withPad: "0", startingAt: 0).prefix(6)) ?? 0 : 0
        return DatabaseTime(isNegative: isNegative, hours: hours, minutes: minutes, seconds: seconds, microseconds: microseconds)
    }

    private static func parseDateTime(_ text: String) -> DatabaseDateTime? {
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let date = self.parseDate(String(parts[0])), let time = self.parseTime(String(parts[1])) else { return nil }
        return DatabaseDateTime(date: date, time: time)
    }
}
