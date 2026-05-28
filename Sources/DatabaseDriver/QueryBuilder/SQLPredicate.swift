//
//  SQLPredicate.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public struct SQLPredicate: Sendable {
    public let sql: String

    public init(_ sql: String) {
        self.sql = sql
    }
}