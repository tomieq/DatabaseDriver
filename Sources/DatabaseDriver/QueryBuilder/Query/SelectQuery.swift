//
//  SelectQuery.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public struct SelectQuery: SQLStatement {
    public let table: Table
    public let columns: [String]
    public let predicate: SQLPredicate?
    public let orderings: [SQLOrdering]
    public let limitValue: Int?
    public let offsetValue: Int?

    public init(
        table: Table,
        columns: [String] = ["*"],
        predicate: SQLPredicate? = nil,
        orderings: [SQLOrdering] = [],
        limitValue: Int? = nil,
        offsetValue: Int? = nil
    ) {
        self.table = table
        self.columns = columns.isEmpty ? ["*"] : columns
        self.predicate = predicate
        self.orderings = orderings
        self.limitValue = limitValue
        self.offsetValue = offsetValue
    }

    public var sql: String {
        var parts = ["SELECT", self.columns.joined(separator: ", "), "FROM", self.table.sql]
        if let predicate {
            parts.append("WHERE")
            parts.append(predicate.sql)
        }
        if !self.orderings.isEmpty {
            parts.append("ORDER BY")
            parts.append(self.orderings.map(\.sql).joined(separator: ", "))
        }
        if let limitValue {
            parts.append("LIMIT")
            parts.append(String(limitValue))
        }
        if let offsetValue {
            parts.append("OFFSET")
            parts.append(String(offsetValue))
        }
        return parts.joined(separator: " ")
    }

    public func select(_ columns: any SQLSelectable...) -> SelectQuery {
        SelectQuery(table: self.table, columns: columns.map(\.sql), predicate: self.predicate, orderings: self.orderings, limitValue: self.limitValue, offsetValue: self.offsetValue)
    }

    public func filter(_ predicate: SQLPredicate) -> SelectQuery {
        let combined: SQLPredicate
        if let current = self.predicate {
            combined = current && predicate
        } else {
            combined = predicate
        }
        return SelectQuery(table: self.table, columns: self.columns, predicate: combined, orderings: self.orderings, limitValue: self.limitValue, offsetValue: self.offsetValue)
    }

    public func `where`(_ predicate: SQLPredicate) -> SelectQuery {
        self.filter(predicate)
    }

    public func order(_ orderings: SQLOrdering...) -> SelectQuery {
        SelectQuery(table: self.table, columns: self.columns, predicate: self.predicate, orderings: self.orderings + orderings, limitValue: self.limitValue, offsetValue: self.offsetValue)
    }

    public func order(_ columns: any SQLSelectable...) -> SelectQuery {
        self.order(columns.map { SQLOrdering(sql: $0.sql) })
    }

    public func order(_ orderings: [SQLOrdering]) -> SelectQuery {
        SelectQuery(table: self.table, columns: self.columns, predicate: self.predicate, orderings: self.orderings + orderings, limitValue: self.limitValue, offsetValue: self.offsetValue)
    }

    public func limit(_ limit: Int, offset: Int? = nil) -> SelectQuery {
        SelectQuery(table: self.table, columns: self.columns, predicate: self.predicate, orderings: self.orderings, limitValue: limit, offsetValue: offset)
    }
}
