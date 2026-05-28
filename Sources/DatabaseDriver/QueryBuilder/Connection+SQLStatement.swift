//
//  Connection+SQLStatement.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

extension Connection {
    @discardableResult
    public func execute(_ statement: any SQLStatement) throws -> QueryResult {
        try self.execute(statement.sql)
    }

    @discardableResult
    public func execute(_ statement: any SQLStatement) async throws -> QueryResult {
        try await self.execute(statement.sql)
    }

    @discardableResult
    public func run(_ statement: any SQLStatement) throws -> QueryResult {
        try self.execute(statement.sql)
    }

    @discardableResult
    public func run(_ statement: any SQLStatement) async throws -> QueryResult {
        try await self.execute(statement.sql)
    }

    public func prepare(_ query: SelectQuery) throws -> [DatabaseRow] {
        try self.execute(query.sql).rows
    }

    public func prepare(_ query: SelectQuery) async throws -> [DatabaseRow] {
        try await self.execute(query.sql).rows
    }
}
