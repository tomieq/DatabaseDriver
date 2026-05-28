//
//  Expression.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

public struct Expression<Value>: Sendable {
    public let name: String
    public let tableName: String?
    private let literalSQL: String?

    public init(_ name: String, tableName: String? = nil) {
        self.name = name
        self.tableName = tableName
        self.literalSQL = nil
    }

    public var sql: String {
        if let literalSQL { return literalSQL }
        if let tableName {
            return SQLBuilder.quoteIdentifier(tableName) + "." + SQLBuilder.quoteIdentifier(self.name)
        }
        return SQLBuilder.quoteIdentifier(self.name)
    }

    fileprivate var unqualifiedSQL: String {
        SQLBuilder.quoteIdentifier(self.name)
    }

    public var asc: SQLOrdering {
        SQLOrdering(sql: self.sql + " ASC")
    }

    public var desc: SQLOrdering {
        SQLOrdering(sql: self.sql + " DESC")
    }

    public init(literal sql: String) {
        self.name = sql
        self.tableName = nil
        self.literalSQL = sql
    }
}

public func <- <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLAssignment {
    SQLAssignment(columnSQL: lhs.sql, insertColumnSQL: lhs.unqualifiedSQL, valueSQL: SQLBuilder.literal(rhs.databaseValue))
}

public func <- <Value: DatabaseExpressionValue>(lhs: Expression<Value?>, rhs: Value?) -> SQLAssignment {
    SQLAssignment(columnSQL: lhs.sql, insertColumnSQL: lhs.unqualifiedSQL, valueSQL: SQLBuilder.literal(rhs?.databaseValue ?? .null))
}

public func += <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLAssignment {
    SQLAssignment(columnSQL: lhs.sql, insertColumnSQL: lhs.unqualifiedSQL, valueSQL: lhs.sql + " + " + SQLBuilder.literal(rhs.databaseValue))
}

public func -= <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLAssignment {
    SQLAssignment(columnSQL: lhs.sql, insertColumnSQL: lhs.unqualifiedSQL, valueSQL: lhs.sql + " - " + SQLBuilder.literal(rhs.databaseValue))
}

postfix operator ++
postfix public func ++ <Value>(expression: Expression<Value>) -> SQLAssignment {
    SQLAssignment(columnSQL: expression.sql, insertColumnSQL: expression.unqualifiedSQL, valueSQL: expression.sql + " + 1")
}

postfix operator --
postfix public func -- <Value>(expression: Expression<Value>) -> SQLAssignment {
    SQLAssignment(columnSQL: expression.sql, insertColumnSQL: expression.unqualifiedSQL, valueSQL: expression.sql + " - 1")
}
