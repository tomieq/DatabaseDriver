//
//  SQLAggregateExpression.swift
//  DatabaseDriver
//
//  Created by: tomieq on 29/05/2026
//

public struct SQLAggregateExpression<Value>: SQLSelectable {
    public let sql: String
    let decodeScalar: @Sendable (DatabaseValue?) throws -> Value

    init(sql: String, decodeScalar: @escaping @Sendable (DatabaseValue?) throws -> Value) {
        self.sql = sql
        self.decodeScalar = decodeScalar
    }
}