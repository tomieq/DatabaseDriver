//
//  Connection+SQLScalarQuery.swift
//  DatabaseDriver
//
//  Created by: tomieq on 29/05/2026
//

extension Connection {
    public func scalar<Value>(_ statement: SQLScalarQuery<Value>) throws -> Value {
        try statement.decodeScalar(self.scalar(statement.sql))
    }

    public func scalar<Value>(_ statement: SQLScalarQuery<Value>) async throws -> Value {
        try await statement.decodeScalar(self.scalar(statement.sql))
    }
}