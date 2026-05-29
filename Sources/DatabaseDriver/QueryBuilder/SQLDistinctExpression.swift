//
//  SQLDistinctExpression.swift
//  DatabaseDriver
//
//  Created by: tomieq on 29/05/2026
//

public struct SQLDistinctExpression<Value>: SQLSelectable {
    public let sql: String

    init(sql: String) {
        self.sql = sql
    }
}