//
//  SQLStatement.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public protocol SQLStatement: Sendable {
    var sql: String { get }
}