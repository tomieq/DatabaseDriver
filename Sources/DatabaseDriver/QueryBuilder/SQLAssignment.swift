//
//  SQLAssignment.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public struct SQLAssignment: Sendable {
    public let sql: String
    fileprivate let insertColumnSQL: String
    fileprivate let valueSQL: String

    public init(sql: String) {
        self.sql = sql
        self.insertColumnSQL = sql
        self.valueSQL = sql
    }
}

extension SQLAssignment {
    init(columnSQL: String, insertColumnSQL: String, valueSQL: String) {
        self.insertColumnSQL = insertColumnSQL
        self.valueSQL = valueSQL
        self.sql = columnSQL + " = " + valueSQL
    }

    var sqlColumn: String {
        self.insertColumnSQL
    }

    var sqlValue: String {
        self.valueSQL
    }
}
