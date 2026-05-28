import Foundation

public enum DatabaseCodingError: Error, Sendable, CustomStringConvertible {
    case unsupportedContainer(String)
    case unsupportedValue(String)

    public var description: String {
        switch self {
        case let .unsupportedContainer(message): return message
        case let .unsupportedValue(message): return message
        }
    }
}

extension DatabaseDate: Codable {
    private enum CodingKeys: String, CodingKey {
        case year
        case month
        case day
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            year: try container.decode(Int.self, forKey: .year),
            month: try container.decode(Int.self, forKey: .month),
            day: try container.decode(Int.self, forKey: .day)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.year, forKey: .year)
        try container.encode(self.month, forKey: .month)
        try container.encode(self.day, forKey: .day)
    }
}

extension DatabaseTime: Codable {
    private enum CodingKeys: String, CodingKey {
        case isNegative
        case hours
        case minutes
        case seconds
        case microseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isNegative: try container.decode(Bool.self, forKey: .isNegative),
            hours: try container.decode(Int.self, forKey: .hours),
            minutes: try container.decode(Int.self, forKey: .minutes),
            seconds: try container.decode(Int.self, forKey: .seconds),
            microseconds: try container.decode(Int.self, forKey: .microseconds)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.isNegative, forKey: .isNegative)
        try container.encode(self.hours, forKey: .hours)
        try container.encode(self.minutes, forKey: .minutes)
        try container.encode(self.seconds, forKey: .seconds)
        try container.encode(self.microseconds, forKey: .microseconds)
    }
}

extension DatabaseDateTime: Codable {
    private enum CodingKeys: String, CodingKey {
        case date
        case time
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            date: try container.decode(DatabaseDate.self, forKey: .date),
            time: try container.decode(DatabaseTime.self, forKey: .time)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.date, forKey: .date)
        try container.encode(self.time, forKey: .time)
    }
}

extension Table {
    public func insert<Value: Encodable>(_ value: Value) throws -> InsertQuery {
        try InsertQuery(table: self, assignments: DatabaseObjectEncoder.encode(value, tableName: self.name))
    }

    public func update<Value: Encodable>(_ value: Value) throws -> UpdateQuery {
        try UpdateQuery(table: self, assignments: DatabaseObjectEncoder.encode(value, tableName: self.name))
    }
}

extension DatabaseRow {
    public func decode<Value: Decodable>(_ type: Value.Type = Value.self) throws -> Value {
        try Value(from: DatabaseRowDecoder(row: self))
    }
}

extension QueryResult {
    public func decode<Value: Decodable>(_ type: Value.Type = Value.self) throws -> [Value] {
        try self.rows.map { try $0.decode(type) }
    }
}

extension Connection {
    public func prepare<Value: Decodable>(_ query: SelectQuery, as type: Value.Type) throws -> [Value] {
        try self.prepare(query).map { try $0.decode(type) }
    }

    public func prepare<Value: Decodable>(_ query: SelectQuery, as type: Value.Type) async throws -> [Value] {
        try await self.prepare(query).map { try $0.decode(type) }
    }
}

extension ConnectionPool {
    public func prepare<Value: Decodable>(_ query: SelectQuery, as type: Value.Type) throws -> [Value] {
        try self.prepare(query).map { try $0.decode(type) }
    }

    public func prepare<Value: Decodable>(_ query: SelectQuery, as type: Value.Type) async throws -> [Value] {
        try await self.prepare(query).map { try $0.decode(type) }
    }
}

private final class DatabaseObjectEncoder: Encoder {
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]
    private let tableName: String
    private var values: [String: DatabaseValue] = [:]

    init(tableName: String, codingPath: [CodingKey] = []) {
        self.tableName = tableName
        self.codingPath = codingPath
    }

    static func encode<Value: Encodable>(_ value: Value, tableName: String) throws -> [SQLAssignment] {
        let encoder = DatabaseObjectEncoder(tableName: tableName)
        try value.encode(to: encoder)
        encoder.includeNilOptionals(from: value)
        return encoder.values.sorted { $0.key < $1.key }.map { key, value in
            let expression = Expression<DatabaseValue>(key, tableName: tableName)
            return expression <- value
        }
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(DatabaseObjectKeyedEncodingContainer(encoder: self))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        DatabaseUnsupportedUnkeyedEncodingContainer(codingPath: self.codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        DatabaseObjectSingleValueEncodingContainer(codingPath: self.codingPath)
    }

    fileprivate func set(_ value: DatabaseValue, forKey key: CodingKey) {
        self.values[key.stringValue] = value
    }

    fileprivate func includeNilOptionals<Value>(from value: Value) {
        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            guard let label = child.label, self.values[label] == nil else { continue }
            let childMirror = Mirror(reflecting: child.value)
            if childMirror.displayStyle == .optional, childMirror.children.isEmpty {
                self.values[label] = .null
            }
        }
    }
}

private struct DatabaseObjectKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: DatabaseObjectEncoder
    var codingPath: [CodingKey] { self.encoder.codingPath }

    mutating func encodeNil(forKey key: Key) throws {
        self.encoder.set(.null, forKey: key)
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws { self.encoder.set(.bool(value), forKey: key) }
    mutating func encode(_ value: String, forKey key: Key) throws { self.encoder.set(.string(value), forKey: key) }
    mutating func encode(_ value: Double, forKey key: Key) throws { self.encoder.set(.double(value), forKey: key) }
    mutating func encode(_ value: Float, forKey key: Key) throws { self.encoder.set(.double(Double(value)), forKey: key) }
    mutating func encode(_ value: Int, forKey key: Key) throws { self.encoder.set(.integer(Int64(value)), forKey: key) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { self.encoder.set(.integer(Int64(value)), forKey: key) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { self.encoder.set(.integer(Int64(value)), forKey: key) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { self.encoder.set(.integer(Int64(value)), forKey: key) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { self.encoder.set(.integer(value), forKey: key) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { self.encoder.set(.unsignedInteger(UInt64(value)), forKey: key) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { self.encoder.set(.unsignedInteger(UInt64(value)), forKey: key) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { self.encoder.set(.unsignedInteger(UInt64(value)), forKey: key) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { self.encoder.set(.unsignedInteger(UInt64(value)), forKey: key) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { self.encoder.set(.unsignedInteger(value), forKey: key) }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        self.encoder.set(try DatabaseValueBox.box(value), forKey: key)
    }

    mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try self.encode(value, forKey: key)
        } else {
            self.encoder.set(.null, forKey: key)
        }
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(DatabaseUnsupportedKeyedEncodingContainer<NestedKey>(codingPath: self.codingPath + [key]))
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        DatabaseUnsupportedUnkeyedEncodingContainer(codingPath: self.codingPath + [key])
    }

    mutating func superEncoder() -> Encoder { DatabaseUnsupportedEncoder(codingPath: self.codingPath) }
    mutating func superEncoder(forKey key: Key) -> Encoder { DatabaseUnsupportedEncoder(codingPath: self.codingPath + [key]) }
}

private enum DatabaseValueBox {
    static func box<Value: Encodable>(_ value: Value) throws -> DatabaseValue {
        if let value = value as? DatabaseValue { return value }
        if let value = value as? String { return .string(value) }
        if let value = value as? Bool { return .bool(value) }
        if let value = value as? Double { return .double(value) }
        if let value = value as? Float { return .double(Double(value)) }
        if let value = value as? Int { return .integer(Int64(value)) }
        if let value = value as? Int8 { return .integer(Int64(value)) }
        if let value = value as? Int16 { return .integer(Int64(value)) }
        if let value = value as? Int32 { return .integer(Int64(value)) }
        if let value = value as? Int64 { return .integer(value) }
        if let value = value as? UInt { return .unsignedInteger(UInt64(value)) }
        if let value = value as? UInt8 { return .unsignedInteger(UInt64(value)) }
        if let value = value as? UInt16 { return .unsignedInteger(UInt64(value)) }
        if let value = value as? UInt32 { return .unsignedInteger(UInt64(value)) }
        if let value = value as? UInt64 { return .unsignedInteger(value) }
        if let value = value as? Data { return .bytes(value) }
        if let value = value as? Decimal { return .decimal(NSDecimalNumber(decimal: value).stringValue) }
        if let value = value as? DatabaseDate { return .date(value) }
        if let value = value as? DatabaseTime { return .time(value) }
        if let value = value as? DatabaseDateTime { return .dateTime(value) }

        let encoder = DatabaseSingleValueEncoder()
        try value.encode(to: encoder)
        guard let boxed = encoder.value else {
            throw DatabaseCodingError.unsupportedValue("Unsupported Encodable value at top level")
        }
        return boxed
    }
}

private final class DatabaseSingleValueEncoder: Encoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    var value: DatabaseValue?

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(DatabaseUnsupportedKeyedEncodingContainer<Key>(codingPath: self.codingPath))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        DatabaseUnsupportedUnkeyedEncodingContainer(codingPath: self.codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        DatabaseSingleValueEncodingContainer(encoder: self)
    }
}

private struct DatabaseSingleValueEncodingContainer: SingleValueEncodingContainer {
    let encoder: DatabaseSingleValueEncoder
    var codingPath: [CodingKey] { self.encoder.codingPath }

    mutating func encodeNil() throws { self.encoder.value = .null }
    mutating func encode(_ value: Bool) throws { self.encoder.value = .bool(value) }
    mutating func encode(_ value: String) throws { self.encoder.value = .string(value) }
    mutating func encode(_ value: Double) throws { self.encoder.value = .double(value) }
    mutating func encode(_ value: Float) throws { self.encoder.value = .double(Double(value)) }
    mutating func encode(_ value: Int) throws { self.encoder.value = .integer(Int64(value)) }
    mutating func encode(_ value: Int8) throws { self.encoder.value = .integer(Int64(value)) }
    mutating func encode(_ value: Int16) throws { self.encoder.value = .integer(Int64(value)) }
    mutating func encode(_ value: Int32) throws { self.encoder.value = .integer(Int64(value)) }
    mutating func encode(_ value: Int64) throws { self.encoder.value = .integer(value) }
    mutating func encode(_ value: UInt) throws { self.encoder.value = .unsignedInteger(UInt64(value)) }
    mutating func encode(_ value: UInt8) throws { self.encoder.value = .unsignedInteger(UInt64(value)) }
    mutating func encode(_ value: UInt16) throws { self.encoder.value = .unsignedInteger(UInt64(value)) }
    mutating func encode(_ value: UInt32) throws { self.encoder.value = .unsignedInteger(UInt64(value)) }
    mutating func encode(_ value: UInt64) throws { self.encoder.value = .unsignedInteger(value) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        self.encoder.value = try DatabaseValueBox.box(value)
    }
}

private final class DatabaseRowDecoder: Decoder {
    let row: DatabaseRow
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]

    init(row: DatabaseRow, codingPath: [CodingKey] = []) {
        self.row = row
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(DatabaseRowKeyedDecodingContainer<Key>(decoder: self))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw DatabaseCodingError.unsupportedContainer("Database rows cannot be decoded as unkeyed containers")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw DatabaseCodingError.unsupportedContainer("Database rows cannot be decoded as single values")
    }
}

private struct DatabaseRowKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: DatabaseRowDecoder
    var codingPath: [CodingKey] { self.decoder.codingPath }
    var allKeys: [Key] { self.decoder.row.valuesByColumn.keys.compactMap(Key.init(stringValue:)) }

    func contains(_ key: Key) -> Bool {
        self.decoder.row.valuesByColumn.keys.contains(key.stringValue)
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let value = self.decoder.row.valuesByColumn[key.stringValue] else { return true }
        return value == .null
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try self.value(for: key).bool(codingPath: self.codingPath + [key]) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try self.value(for: key).string(codingPath: self.codingPath + [key]) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try self.value(for: key).double(codingPath: self.codingPath + [key]) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { Float(try self.value(for: key).double(codingPath: self.codingPath + [key])) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try self.value(for: key).int(codingPath: self.codingPath + [key]) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try self.value(for: key).int8(codingPath: self.codingPath + [key]) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try self.value(for: key).int16(codingPath: self.codingPath + [key]) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try self.value(for: key).int32(codingPath: self.codingPath + [key]) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try self.value(for: key).int64(codingPath: self.codingPath + [key]) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try self.value(for: key).uint(codingPath: self.codingPath + [key]) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try self.value(for: key).uint8(codingPath: self.codingPath + [key]) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try self.value(for: key).uint16(codingPath: self.codingPath + [key]) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try self.value(for: key).uint32(codingPath: self.codingPath + [key]) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try self.value(for: key).uint64(codingPath: self.codingPath + [key]) }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let value = try self.value(for: key)
        if type == DatabaseValue.self { return value as! T }
        if type == Data.self { return try value.data(codingPath: self.codingPath + [key]) as! T }
        if type == Decimal.self { return try value.decimal(codingPath: self.codingPath + [key]) as! T }
        if type == DatabaseDate.self { return try value.date(codingPath: self.codingPath + [key]) as! T }
        if type == DatabaseTime.self { return try value.time(codingPath: self.codingPath + [key]) as! T }
        if type == DatabaseDateTime.self { return try value.dateTime(codingPath: self.codingPath + [key]) as! T }
        return try T(from: DatabaseValueDecoder(value: value, codingPath: self.codingPath + [key]))
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        throw DatabaseCodingError.unsupportedContainer("Database row column '\(key.stringValue)' cannot be decoded as a nested keyed container")
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        throw DatabaseCodingError.unsupportedContainer("Database row column '\(key.stringValue)' cannot be decoded as a nested unkeyed container")
    }

    func superDecoder() throws -> Decoder { DatabaseUnsupportedDecoder(codingPath: self.codingPath) }
    func superDecoder(forKey key: Key) throws -> Decoder { DatabaseUnsupportedDecoder(codingPath: self.codingPath + [key]) }

    private func value(for key: Key) throws -> DatabaseValue {
        guard let value = self.decoder.row.valuesByColumn[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Missing column '\(key.stringValue)'"))
        }
        return value
    }
}

private final class DatabaseValueDecoder: Decoder {
    let value: DatabaseValue
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]

    init(value: DatabaseValue, codingPath: [CodingKey]) {
        self.value = value
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        throw DatabaseCodingError.unsupportedContainer("Database values cannot be decoded as keyed containers")
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw DatabaseCodingError.unsupportedContainer("Database values cannot be decoded as unkeyed containers")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        DatabaseValueSingleValueDecodingContainer(value: self.value, codingPath: self.codingPath)
    }
}

private struct DatabaseValueSingleValueDecodingContainer: SingleValueDecodingContainer {
    let value: DatabaseValue
    let codingPath: [CodingKey]

    func decodeNil() -> Bool { self.value == .null }
    func decode(_ type: Bool.Type) throws -> Bool { try self.value.bool(codingPath: self.codingPath) }
    func decode(_ type: String.Type) throws -> String { try self.value.string(codingPath: self.codingPath) }
    func decode(_ type: Double.Type) throws -> Double { try self.value.double(codingPath: self.codingPath) }
    func decode(_ type: Float.Type) throws -> Float { Float(try self.value.double(codingPath: self.codingPath)) }
    func decode(_ type: Int.Type) throws -> Int { try self.value.int(codingPath: self.codingPath) }
    func decode(_ type: Int8.Type) throws -> Int8 { try self.value.int8(codingPath: self.codingPath) }
    func decode(_ type: Int16.Type) throws -> Int16 { try self.value.int16(codingPath: self.codingPath) }
    func decode(_ type: Int32.Type) throws -> Int32 { try self.value.int32(codingPath: self.codingPath) }
    func decode(_ type: Int64.Type) throws -> Int64 { try self.value.int64(codingPath: self.codingPath) }
    func decode(_ type: UInt.Type) throws -> UInt { try self.value.uint(codingPath: self.codingPath) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try self.value.uint8(codingPath: self.codingPath) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try self.value.uint16(codingPath: self.codingPath) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try self.value.uint32(codingPath: self.codingPath) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try self.value.uint64(codingPath: self.codingPath) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if type == DatabaseValue.self { return self.value as! T }
        if type == Data.self { return try self.value.data(codingPath: self.codingPath) as! T }
        if type == Decimal.self { return try self.value.decimal(codingPath: self.codingPath) as! T }
        if type == DatabaseDate.self { return try self.value.date(codingPath: self.codingPath) as! T }
        if type == DatabaseTime.self { return try self.value.time(codingPath: self.codingPath) as! T }
        if type == DatabaseDateTime.self { return try self.value.dateTime(codingPath: self.codingPath) as! T }
        throw DatabaseCodingError.unsupportedValue("Unsupported Decodable value at \(self.codingPath.map(\.stringValue).joined(separator: "."))")
    }
}

private extension DatabaseValue {
    func bool(codingPath: [CodingKey]) throws -> Bool {
        switch self {
        case let .bool(value): return value
        case let .integer(value): return value != 0
        case let .unsignedInteger(value): return value != 0
        case let .string(value) where value == "1" || value.lowercased() == "true": return true
        case let .string(value) where value == "0" || value.lowercased() == "false": return false
        default: throw self.typeMismatch(Bool.self, codingPath: codingPath)
        }
    }

    func string(codingPath: [CodingKey]) throws -> String {
        guard let value = self.stringValue else { throw self.valueNotFound(String.self, codingPath: codingPath) }
        return value
    }

    func double(codingPath: [CodingKey]) throws -> Double {
        switch self {
        case let .double(value): return value
        case let .decimal(value): if let double = Double(value) { return double }
        case let .integer(value): return Double(value)
        case let .unsignedInteger(value): return Double(value)
        case let .string(value): if let double = Double(value) { return double }
        default: break
        }
        throw self.typeMismatch(Double.self, codingPath: codingPath)
    }

    func int(codingPath: [CodingKey]) throws -> Int { try self.exactInteger(Int.self, codingPath: codingPath) }
    func int8(codingPath: [CodingKey]) throws -> Int8 { try self.exactInteger(Int8.self, codingPath: codingPath) }
    func int16(codingPath: [CodingKey]) throws -> Int16 { try self.exactInteger(Int16.self, codingPath: codingPath) }
    func int32(codingPath: [CodingKey]) throws -> Int32 { try self.exactInteger(Int32.self, codingPath: codingPath) }
    func int64(codingPath: [CodingKey]) throws -> Int64 { try self.exactInteger(Int64.self, codingPath: codingPath) }
    func uint(codingPath: [CodingKey]) throws -> UInt { try self.exactUnsignedInteger(UInt.self, codingPath: codingPath) }
    func uint8(codingPath: [CodingKey]) throws -> UInt8 { try self.exactUnsignedInteger(UInt8.self, codingPath: codingPath) }
    func uint16(codingPath: [CodingKey]) throws -> UInt16 { try self.exactUnsignedInteger(UInt16.self, codingPath: codingPath) }
    func uint32(codingPath: [CodingKey]) throws -> UInt32 { try self.exactUnsignedInteger(UInt32.self, codingPath: codingPath) }
    func uint64(codingPath: [CodingKey]) throws -> UInt64 { try self.exactUnsignedInteger(UInt64.self, codingPath: codingPath) }

    func data(codingPath: [CodingKey]) throws -> Data {
        guard case let .bytes(value) = self else { throw self.typeMismatch(Data.self, codingPath: codingPath) }
        return value
    }

    func decimal(codingPath: [CodingKey]) throws -> Decimal {
        switch self {
        case let .decimal(value):
            return Decimal(string: value) ?? 0
        case let .string(value):
            if let decimal = Decimal(string: value) { return decimal }
        case let .integer(value): return Decimal(value)
        case let .unsignedInteger(value): return Decimal(value)
        default: break
        }
        throw self.typeMismatch(Decimal.self, codingPath: codingPath)
    }

    func date(codingPath: [CodingKey]) throws -> DatabaseDate {
        guard case let .date(value) = self else { throw self.typeMismatch(DatabaseDate.self, codingPath: codingPath) }
        return value
    }

    func time(codingPath: [CodingKey]) throws -> DatabaseTime {
        guard case let .time(value) = self else { throw self.typeMismatch(DatabaseTime.self, codingPath: codingPath) }
        return value
    }

    func dateTime(codingPath: [CodingKey]) throws -> DatabaseDateTime {
        guard case let .dateTime(value) = self else { throw self.typeMismatch(DatabaseDateTime.self, codingPath: codingPath) }
        return value
    }

    private func exactInteger<T: FixedWidthInteger>(_ type: T.Type, codingPath: [CodingKey]) throws -> T {
        switch self {
        case let .integer(value): if let exact = T(exactly: value) { return exact }
        case let .unsignedInteger(value): if let exact = T(exactly: value) { return exact }
        case let .string(value): if let exact = T(value) { return exact }
        default: break
        }
        throw self.typeMismatch(type, codingPath: codingPath)
    }

    private func exactUnsignedInteger<T: FixedWidthInteger>(_ type: T.Type, codingPath: [CodingKey]) throws -> T {
        switch self {
        case let .unsignedInteger(value): if let exact = T(exactly: value) { return exact }
        case let .integer(value): if let exact = T(exactly: value) { return exact }
        case let .string(value): if let exact = T(value) { return exact }
        default: break
        }
        throw self.typeMismatch(type, codingPath: codingPath)
    }

    private func typeMismatch(_ type: Any.Type, codingPath: [CodingKey]) -> DecodingError {
        DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode \(self) as \(type)"))
    }

    private func valueNotFound(_ type: Any.Type, codingPath: [CodingKey]) -> DecodingError {
        DecodingError.valueNotFound(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode NULL as \(type)"))
    }
}

private struct DatabaseObjectSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [CodingKey]

    mutating func encodeNil() throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: Bool) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: String) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: Double) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: Float) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: Int) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: Int8) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: Int16) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: Int32) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: Int64) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: UInt) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: UInt8) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: UInt16) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: UInt32) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode(_ value: UInt64) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
    mutating func encode<T: Encodable>(_ value: T) throws { throw DatabaseCodingError.unsupportedContainer("Top-level Codable database objects must use keyed containers") }
}

private struct DatabaseUnsupportedKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey]
    mutating func encodeNil(forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Bool, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: String, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Double, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Float, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Int, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Int8, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Int16, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Int32, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Int64, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: UInt, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database columns") }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> { KeyedEncodingContainer(DatabaseUnsupportedKeyedEncodingContainer<NestedKey>(codingPath: self.codingPath + [key])) }
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer { DatabaseUnsupportedUnkeyedEncodingContainer(codingPath: self.codingPath + [key]) }
    mutating func superEncoder() -> Encoder { DatabaseUnsupportedEncoder(codingPath: self.codingPath) }
    mutating func superEncoder(forKey key: Key) -> Encoder { DatabaseUnsupportedEncoder(codingPath: self.codingPath + [key]) }
}

private struct DatabaseUnsupportedUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey]
    var count: Int = 0
    mutating func encodeNil() throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Bool) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: String) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Double) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Float) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Int) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Int8) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Int16) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Int32) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: Int64) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: UInt) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: UInt8) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: UInt16) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: UInt32) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode(_ value: UInt64) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func encode<T: Encodable>(_ value: T) throws { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database columns") }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> { KeyedEncodingContainer(DatabaseUnsupportedKeyedEncodingContainer<NestedKey>(codingPath: self.codingPath)) }
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer { self }
    mutating func superEncoder() -> Encoder { DatabaseUnsupportedEncoder(codingPath: self.codingPath) }
}

private struct DatabaseUnsupportedEncoder: Encoder {
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]
    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> { KeyedEncodingContainer(DatabaseUnsupportedKeyedEncodingContainer<Key>(codingPath: self.codingPath)) }
    func unkeyedContainer() -> UnkeyedEncodingContainer { DatabaseUnsupportedUnkeyedEncodingContainer(codingPath: self.codingPath) }
    func singleValueContainer() -> SingleValueEncodingContainer { DatabaseObjectSingleValueEncodingContainer(codingPath: self.codingPath) }
}

private struct DatabaseUnsupportedDecoder: Decoder {
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> { throw DatabaseCodingError.unsupportedContainer("Nested keyed Codable objects are not supported for database rows") }
    func unkeyedContainer() throws -> UnkeyedDecodingContainer { throw DatabaseCodingError.unsupportedContainer("Unkeyed Codable objects are not supported for database rows") }
    func singleValueContainer() throws -> SingleValueDecodingContainer { throw DatabaseCodingError.unsupportedContainer("Unsupported decoder") }
}
