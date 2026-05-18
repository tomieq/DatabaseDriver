//
//  QueryResult.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//

public struct QueryResult: Equatable, Sendable {
    public let columns: [DatabaseColumn]
    public let rows: [DatabaseRow]
    public let affectedRows: Int
    public let lastInsertID: Int

    public init(columns: [DatabaseColumn], rows: [DatabaseRow], affectedRows: Int, lastInsertID: Int) {
        self.columns = columns
        self.rows = rows
        self.affectedRows = affectedRows
        self.lastInsertID = lastInsertID
    }

    public var isResultSet: Bool { !self.columns.isEmpty }
}