//
//  SQLBuilder.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//

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
