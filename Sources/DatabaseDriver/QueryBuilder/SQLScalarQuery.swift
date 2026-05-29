//
//  SQLScalarQuery.swift
//  DatabaseDriver
//
//  Created by: tomieq on 29/05/2026
//

public struct SQLScalarQuery<Value>: SQLStatement {
    public let sql: String
    let decodeScalar: @Sendable (DatabaseValue?) throws -> Value

    init(sql: String, decodeScalar: @escaping @Sendable (DatabaseValue?) throws -> Value) {
        self.sql = sql
        self.decodeScalar = decodeScalar
    }

    init(query: SelectQuery, decodeScalar: @escaping @Sendable (DatabaseValue?) throws -> Value) {
        self.init(sql: query.sql, decodeScalar: decodeScalar)
    }
}

func decodeRequiredScalar<Value: SQLScalarValue>(_ type: Value.Type, from value: DatabaseValue?) throws -> Value {
    guard let value, value != .null, let scalar = Value.scalarValue(from: value) else {
        throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: [], debugDescription: "Cannot decode scalar value as \(type)"))
    }
    return scalar
}

func decodeOptionalScalar<Value: SQLScalarValue>(_ type: Value.Type, from value: DatabaseValue?) throws -> Value? {
    guard let value, value != .null else { return nil }
    guard let scalar = Value.scalarValue(from: value) else {
        throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: [], debugDescription: "Cannot decode scalar value as \(type)"))
    }
    return scalar
}