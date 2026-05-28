//
//  InsertQuery.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public struct InsertQuery: SQLStatement {
    public let table: Table
    public let assignments: [SQLAssignment]

    public init(table: Table, assignments: [SQLAssignment]) {
        self.table = table
        self.assignments = assignments
    }

    public var sql: String {
        guard !self.assignments.isEmpty else {
            return "INSERT INTO \(self.table.sql) DEFAULT VALUES"
        }
        let columns = self.assignments.map(\.sqlColumn).joined(separator: ", ")
        let values = self.assignments.map(\.sqlValue).joined(separator: ", ")
        return "INSERT INTO \(self.table.sql) (\(columns)) VALUES (\(values))"
    }
}