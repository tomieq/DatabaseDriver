//
//  SQLOrdering.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public struct SQLOrdering: Sendable {
    public let sql: String

    public init(sql: String) {
        self.sql = sql
    }
}