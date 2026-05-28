//
//  Table.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public struct Table: Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var sql: String {
        SQLBuilder.quoteIdentifier(self.name)
    }

    public func column<Value>(_ name: String, as type: Value.Type = Value.self) -> Expression<Value> {
        Expression(name, tableName: self.name)
    }

    public func select(_ columns: any SQLSelectable...) -> SelectQuery {
        SelectQuery(table: self, columns: columns.map(\.sql))
    }

    public func select(_ columns: [any SQLSelectable]) -> SelectQuery {
        SelectQuery(table: self, columns: columns.map(\.sql))
    }

    public func filter(_ predicate: SQLPredicate) -> SelectQuery {
        SelectQuery(table: self).filter(predicate)
    }

    public func `where`(_ predicate: SQLPredicate) -> SelectQuery {
        self.filter(predicate)
    }

    public func insert(_ assignments: SQLAssignment...) -> InsertQuery {
        InsertQuery(table: self, assignments: assignments)
    }

    public func insert(_ assignments: [SQLAssignment]) -> InsertQuery {
        InsertQuery(table: self, assignments: assignments)
    }

    public func update(_ assignments: SQLAssignment...) -> UpdateQuery {
        UpdateQuery(table: self, assignments: assignments)
    }

    public func update(_ assignments: [SQLAssignment]) -> UpdateQuery {
        UpdateQuery(table: self, assignments: assignments)
    }

    public func delete() -> DeleteQuery {
        DeleteQuery(table: self)
    }
}