

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

infix operator <-: AssignmentPrecedence
