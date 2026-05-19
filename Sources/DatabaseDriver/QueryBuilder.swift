import Foundation

public protocol SQLStatement: Sendable {
    var sql: String { get }
}

public protocol DatabaseExpressionValue: Sendable {
    var databaseValue: DatabaseValue { get }
}

extension String: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .string(self) }
}

extension Int: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .integer(Int64(self)) }
}

extension Int64: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .integer(self) }
}

extension UInt: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .unsignedInteger(UInt64(self)) }
}

extension UInt64: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .unsignedInteger(self) }
}

extension Double: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .double(self) }
}

extension Bool: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .bool(self) }
}

extension Data: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .bytes(self) }
}

extension DatabaseDate: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .date(self) }
}

extension DatabaseTime: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .time(self) }
}

extension DatabaseDateTime: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .dateTime(self) }
}

extension DatabaseValue: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { self }
}

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

public struct SQLPredicate: Sendable {
    public let sql: String

    public init(_ sql: String) {
        self.sql = sql
    }
}

public struct SQLOrdering: Sendable {
    public let sql: String

    public init(sql: String) {
        self.sql = sql
    }
}

public struct SQLAssignment: Sendable {
    public let sql: String
    fileprivate let insertColumnSQL: String
    fileprivate let valueSQL: String

    public init(sql: String) {
        self.sql = sql
        self.insertColumnSQL = sql
        self.valueSQL = sql
    }
}

public struct Table: Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var sql: String {
        SQLBuilder.quoteIdentifier(self.name)
    }

    public func column<Value>(_ name: String, as type: Value.Type = Value.self) -> Expression<Value> {
        Expression(name, tableName: self.name)
    }

    public func select(_ columns: any SQLSelectable...) -> SelectQuery {
        SelectQuery(table: self, columns: columns.map(\.sql))
    }

    public func select(_ columns: [any SQLSelectable]) -> SelectQuery {
        SelectQuery(table: self, columns: columns.map(\.sql))
    }

    public func filter(_ predicate: SQLPredicate) -> SelectQuery {
        SelectQuery(table: self).filter(predicate)
    }

    public func insert(_ assignments: SQLAssignment...) -> InsertQuery {
        InsertQuery(table: self, assignments: assignments)
    }

    public func insert(_ assignments: [SQLAssignment]) -> InsertQuery {
        InsertQuery(table: self, assignments: assignments)
    }

    public func update(_ assignments: SQLAssignment...) -> UpdateQuery {
        UpdateQuery(table: self, assignments: assignments)
    }

    public func update(_ assignments: [SQLAssignment]) -> UpdateQuery {
        UpdateQuery(table: self, assignments: assignments)
    }

    public func delete() -> DeleteQuery {
        DeleteQuery(table: self)
    }
}

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

    public func order(_ orderings: SQLOrdering...) -> SelectQuery {
        SelectQuery(table: self.table, columns: self.columns, predicate: self.predicate, orderings: self.orderings + orderings, limitValue: self.limitValue, offsetValue: self.offsetValue)
    }

    public func limit(_ limit: Int, offset: Int? = nil) -> SelectQuery {
        SelectQuery(table: self.table, columns: self.columns, predicate: self.predicate, orderings: self.orderings, limitValue: limit, offsetValue: offset)
    }
}

public struct InsertQuery: SQLStatement {
    public let table: Table
    public let assignments: [SQLAssignment]

    public init(table: Table, assignments: [SQLAssignment]) {
        self.table = table
        self.assignments = assignments
    }

    public var sql: String {
        let columns = self.assignments.map(\.sqlColumn).joined(separator: ", ")
        let values = self.assignments.map(\.sqlValue).joined(separator: ", ")
        return "INSERT INTO \(self.table.sql) (\(columns)) VALUES (\(values))"
    }
}

public struct UpdateQuery: SQLStatement {
    public let table: Table
    public let assignments: [SQLAssignment]
    public let predicate: SQLPredicate?

    public init(table: Table, assignments: [SQLAssignment], predicate: SQLPredicate? = nil) {
        self.table = table
        self.assignments = assignments
        self.predicate = predicate
    }

    public var sql: String {
        var result = "UPDATE \(self.table.sql) SET \(self.assignments.map(\.sql).joined(separator: ", "))"
        if let predicate {
            result += " WHERE \(predicate.sql)"
        }
        return result
    }

    public func filter(_ predicate: SQLPredicate) -> UpdateQuery {
        let combined: SQLPredicate
        if let current = self.predicate {
            combined = current && predicate
        } else {
            combined = predicate
        }
        return UpdateQuery(table: self.table, assignments: self.assignments, predicate: combined)
    }
}

public struct DeleteQuery: SQLStatement {
    public let table: Table
    public let predicate: SQLPredicate?

    public init(table: Table, predicate: SQLPredicate? = nil) {
        self.table = table
        self.predicate = predicate
    }

    public var sql: String {
        var result = "DELETE FROM \(self.table.sql)"
        if let predicate {
            result += " WHERE \(predicate.sql)"
        }
        return result
    }

    public func filter(_ predicate: SQLPredicate) -> DeleteQuery {
        let combined: SQLPredicate
        if let current = self.predicate {
            combined = current && predicate
        } else {
            combined = predicate
        }
        return DeleteQuery(table: self.table, predicate: combined)
    }
}

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

public func <- <Value: DatabaseExpressionValue>(lhs: Expression<Value>, rhs: Value) -> SQLAssignment {
    SQLAssignment(columnSQL: lhs.sql, insertColumnSQL: lhs.unqualifiedSQL, valueSQL: SQLBuilder.literal(rhs.databaseValue))
}

public func <- <Value: DatabaseExpressionValue>(lhs: Expression<Value?>, rhs: Value?) -> SQLAssignment {
    SQLAssignment(columnSQL: lhs.sql, insertColumnSQL: lhs.unqualifiedSQL, valueSQL: SQLBuilder.literal(rhs?.databaseValue ?? .null))
}

extension DatabaseClient {
    @discardableResult
    public func execute(_ statement: any SQLStatement) throws -> QueryResult {
        try self.execute(statement.sql)
    }

    @discardableResult
    public func execute(_ statement: any SQLStatement) async throws -> QueryResult {
        try await self.execute(statement.sql)
    }

    @discardableResult
    public func run(_ statement: any SQLStatement) throws -> QueryResult {
        try self.execute(statement.sql)
    }

    @discardableResult
    public func run(_ statement: any SQLStatement) async throws -> QueryResult {
        try await self.execute(statement.sql)
    }

    public func prepare(_ query: SelectQuery) throws -> [DatabaseRow] {
        try self.execute(query.sql).rows
    }

    public func prepare(_ query: SelectQuery) async throws -> [DatabaseRow] {
        try await self.execute(query.sql).rows
    }
}

extension DatabasePool {
    @discardableResult
    public func execute(_ statement: any SQLStatement) throws -> QueryResult {
        try self.execute(statement.sql)
    }

    @discardableResult
    public func execute(_ statement: any SQLStatement) async throws -> QueryResult {
        try await self.execute(statement.sql)
    }

    @discardableResult
    public func run(_ statement: any SQLStatement) throws -> QueryResult {
        try self.execute(statement.sql)
    }

    @discardableResult
    public func run(_ statement: any SQLStatement) async throws -> QueryResult {
        try await self.execute(statement.sql)
    }

    public func prepare(_ query: SelectQuery) throws -> [DatabaseRow] {
        try self.execute(query.sql).rows
    }

    public func prepare(_ query: SelectQuery) async throws -> [DatabaseRow] {
        try await self.execute(query.sql).rows
    }
}

extension SQLAssignment {
    fileprivate init(columnSQL: String, insertColumnSQL: String, valueSQL: String) {
        self.insertColumnSQL = insertColumnSQL
        self.valueSQL = valueSQL
        self.sql = columnSQL + " = " + valueSQL
    }

    fileprivate var sqlColumn: String {
        self.insertColumnSQL
    }

    fileprivate var sqlValue: String {
        self.valueSQL
    }
}

enum SQLBuilder {
    static func quoteIdentifier(_ identifier: String) -> String {
        identifier
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { "`" + $0.replacingOccurrences(of: "`", with: "``") + "`" }
            .joined(separator: ".")
    }

    static func compare(_ lhs: String, _ operation: String, _ rhs: DatabaseValue) -> SQLPredicate {
        SQLPredicate(lhs + " " + operation + " " + self.literal(rhs))
    }

    static func literal(_ value: DatabaseValue) -> String {
        switch value {
        case .null:
            return "NULL"
        case let .bool(value):
            return value ? "TRUE" : "FALSE"
        case let .integer(value):
            return String(value)
        case let .unsignedInteger(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .decimal(value):
            return self.quoteString(value)
        case let .string(value):
            return self.quoteString(value)
        case let .bytes(value):
            return "X'" + value.map { String(format: "%02x", $0) }.joined() + "'"
        case let .date(value):
            return self.quoteString(value.description)
        case let .time(value):
            return self.quoteString(value.description)
        case let .dateTime(value):
            return self.quoteString(value.description)
        }
    }

    private static func quoteString(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}