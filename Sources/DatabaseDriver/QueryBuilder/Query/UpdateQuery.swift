//
//  UpdateQuery.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public struct UpdateQuery: SQLStatement {
    public let table: Table
    public let assignments: [SQLAssignment]
    public let predicate: SQLPredicate?

    public init(table: Table, assignments: [SQLAssignment], predicate: SQLPredicate? = nil) {
        self.table = table
        self.assignments = assignments
        self.predicate = predicate
    }

    public var sql: String {
        var result = "UPDATE \(self.table.sql) SET \(self.assignments.map(\.sql).joined(separator: ", "))"
        if let predicate {
            result += " WHERE \(predicate.sql)"
        }
        return result
    }

    public func filter(_ predicate: SQLPredicate) -> UpdateQuery {
        let combined: SQLPredicate
        if let current = self.predicate {
            combined = current && predicate
        } else {
            combined = predicate
        }
        return UpdateQuery(table: self.table, assignments: self.assignments, predicate: combined)
    }
}