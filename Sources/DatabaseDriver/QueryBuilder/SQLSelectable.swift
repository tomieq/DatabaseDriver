//
//  SQLSelectable.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public protocol SQLSelectable: Sendable {
    var sql: String { get }
}

extension Expression: SQLSelectable {}

public struct SQL: SQLSelectable, Sendable {
    public let sql: String

    public init(_ sql: String) {
        self.sql = sql
    }
}