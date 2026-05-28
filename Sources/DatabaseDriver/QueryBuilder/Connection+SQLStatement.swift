//
//  Connection+SQLStatement.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

extension Connection {
    @discardableResult
    public func run(_ sql: String) throws -> QueryResult {
        try self.execute(sql)
    }

    @discardableResult
    public func run(_ sql: String) async throws -> QueryResult {
        try await self.execute(sql)
    }

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

    public func prepare(_ sql: String) throws -> [DatabaseRow] {
        try self.execute(sql).rows
    }

    public func prepare(_ sql: String) async throws -> [DatabaseRow] {
        try await self.execute(sql).rows
    }

    public func pluck(_ query: SelectQuery) throws -> DatabaseRow? {
        try self.prepare(query.limit(1)).first
    }

    public func pluck(_ query: SelectQuery) async throws -> DatabaseRow? {
        try await self.prepare(query.limit(1)).first
    }

    public func scalar(_ sql: String) throws -> DatabaseValue? {
        try self.execute(sql).rows.first?.values.first
    }

    public func scalar(_ sql: String) async throws -> DatabaseValue? {
        try await self.execute(sql).rows.first?.values.first
    }

    public func scalar(_ statement: any SQLStatement) throws -> DatabaseValue? {
        try self.scalar(statement.sql)
    }

    public func scalar(_ statement: any SQLStatement) async throws -> DatabaseValue? {
        try await self.scalar(statement.sql)
    }
}
