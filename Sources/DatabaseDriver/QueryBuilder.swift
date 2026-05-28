

public func == <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLPredicate {
    SQLBuilder.compare(lhs.sql, "=", rhs.databaseValue)
}

public func == <Value: DatabaseExpressionValue>(lhs: Expression<Value?>, rhs: Value?) -> SQLPredicate {
    guard let rhs else { return SQLPredicate(lhs.sql + " IS NULL") }
    return SQLBuilder.compare(lhs.sql, "=", rhs.databaseValue)
}

public func != <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLPredicate {
    SQLBuilder.compare(lhs.sql, "!=", rhs.databaseValue)
}

public func != <Value: DatabaseExpressionValue>(lhs: Expression<Value?>, rhs: Value?) -> SQLPredicate {
    guard let rhs else { return SQLPredicate(lhs.sql + " IS NOT NULL") }
    return SQLBuilder.compare(lhs.sql, "!=", rhs.databaseValue)
}

public func > <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLPredicate {
    SQLBuilder.compare(lhs.sql, ">", rhs.databaseValue)
}

public func >= <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLPredicate {
    SQLBuilder.compare(lhs.sql, ">=", rhs.databaseValue)
}

public func < <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLPredicate {
    SQLBuilder.compare(lhs.sql, "<", rhs.databaseValue)
}

public func <= <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLPredicate {
    SQLBuilder.compare(lhs.sql, "<=", rhs.databaseValue)
}

public func && (lhs: SQLPredicate, rhs: SQLPredicate) -> SQLPredicate {
    SQLPredicate("(\(lhs.sql)) AND (\(rhs.sql))")
}

public func || (lhs: SQLPredicate, rhs: SQLPredicate) -> SQLPredicate {
    SQLPredicate("(\(lhs.sql)) OR (\(rhs.sql))")
}

prefix public func ! (predicate: SQLPredicate) -> SQLPredicate {
    SQLPredicate("NOT (\(predicate.sql))")
}

public func === <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLPredicate {
    SQLBuilder.compare(lhs.sql, "IS", rhs.databaseValue)
}

public func === <Value: DatabaseExpressionValue>(lhs: Expression<Value?>, rhs: Value?) -> SQLPredicate {
    guard let rhs else { return SQLPredicate(lhs.sql + " IS NULL") }
    return SQLBuilder.compare(lhs.sql, "IS", rhs.databaseValue)
}

public func !== <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLPredicate {
    SQLBuilder.compare(lhs.sql, "IS NOT", rhs.databaseValue)
}

public func !== <Value: DatabaseExpressionValue>(lhs: Expression<Value?>, rhs: Value?) -> SQLPredicate {
    guard let rhs else { return SQLPredicate(lhs.sql + " IS NOT NULL") }
    return SQLBuilder.compare(lhs.sql, "IS NOT", rhs.databaseValue)
}

extension Expression where Value == String {
    public func like(_ pattern: String) -> SQLPredicate {
        SQLBuilder.compare(self.sql, "LIKE", pattern.databaseValue)
    }
}

extension Expression {
    public func like(_ pattern: String) -> SQLPredicate where Value == String? {
        SQLBuilder.compare(self.sql, "LIKE", pattern.databaseValue)
    }
}

extension Array where Element: DatabaseExpressionValue {
    public func contains(_ expression: Expression<Element>) -> SQLPredicate {
        SQLPredicate("\(expression.sql) IN (\(self.map { SQLBuilder.literal($0.databaseValue) }.joined(separator: ", ")))")
    }
}

infix operator <-: AssignmentPrecedence
