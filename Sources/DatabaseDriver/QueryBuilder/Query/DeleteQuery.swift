//
//  DeleteQuery.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public struct DeleteQuery: SQLStatement {
    public let table: Table
    public let predicate: SQLPredicate?

    public init(table: Table, predicate: SQLPredicate? = nil) {
        self.table = table
        self.predicate = predicate
    }

    public var sql: String {
        var result = "DELETE FROM \(self.table.sql)"
        if let predicate {
            result += " WHERE \(predicate.sql)"
        }
        return result
    }

    public func filter(_ predicate: SQLPredicate) -> DeleteQuery {
        let combined: SQLPredicate
        if let current = self.predicate {
            combined = current && predicate
        } else {
            combined = predicate
        }
        return DeleteQuery(table: self.table, predicate: combined)
    }

    public func `where`(_ predicate: SQLPredicate) -> DeleteQuery {
        self.filter(predicate)
    }
}