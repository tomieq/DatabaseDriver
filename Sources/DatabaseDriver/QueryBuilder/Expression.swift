//
//  Expression.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public struct Expression<Value>: Sendable {
    public let name: String
    public let tableName: String?

    public init(_ name: String, tableName: String? = nil) {
        self.name = name
        self.tableName = tableName
    }

    public var sql: String {
        if let tableName {
            return SQLBuilder.quoteIdentifier(tableName) + "." + SQLBuilder.quoteIdentifier(self.name)
        }
        return SQLBuilder.quoteIdentifier(self.name)
    }

    fileprivate var unqualifiedSQL: String {
        SQLBuilder.quoteIdentifier(self.name)
    }

    public func asc() -> SQLOrdering {
        SQLOrdering(sql: self.sql + " ASC")
    }

    public func desc() -> SQLOrdering {
        SQLOrdering(sql: self.sql + " DESC")
    }
}

public func <- <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLAssignment {
    SQLAssignment(columnSQL: lhs.sql, insertColumnSQL: lhs.unqualifiedSQL, valueSQL: SQLBuilder.literal(rhs.databaseValue))
}

public func <- <Value: DatabaseExpressionValue>(lhs: Expression<Value?>, rhs: Value?) -> SQLAssignment {
    SQLAssignment(columnSQL: lhs.sql, insertColumnSQL: lhs.unqualifiedSQL, valueSQL: SQLBuilder.literal(rhs?.databaseValue ?? .null))
}
