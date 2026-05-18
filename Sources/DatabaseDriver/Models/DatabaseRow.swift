//
//  DatabaseRow.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//
import Foundation

public struct DatabaseRow: Equatable, Sendable {
    public let values: [DatabaseValue]
    public let valuesByColumn: [String: DatabaseValue]

    public init(values: [DatabaseValue], valuesByColumn: [String: DatabaseValue]) {
        self.values = values
        self.valuesByColumn = valuesByColumn
    }

    public subscript(_ column: String) -> DatabaseValue? {
        self.valuesByColumn[column]
    }

    public func string(_ column: String) -> String? {
        self[column]?.stringValue
    }

    public func bool(_ column: String) -> Bool? {
        switch self[column] {
        case let .bool(value): return value
        case let .integer(value): return value != 0
        case let .unsignedInteger(value): return value != 0
        case let .string(value): return value == "1" || value.lowercased() == "true"
        default: return nil
        }
    }

    public func integer(_ column: String) -> Int64? {
        switch self[column] {
        case let .integer(value): return value
        case let .unsignedInteger(value): return Int64(exactly: value)
        case let .string(value): return Int64(value)
        default: return nil
        }
    }

    public func unsignedInteger(_ column: String) -> UInt64? {
        switch self[column] {
        case let .unsignedInteger(value): return value
        case let .integer(value): return UInt64(exactly: value)
        case let .string(value): return UInt64(value)
        default: return nil
        }
    }

    public func double(_ column: String) -> Double? {
        switch self[column] {
        case let .double(value): return value
        case let .decimal(value): return Double(value)
        case let .integer(value): return Double(value)
        case let .unsignedInteger(value): return Double(value)
        case let .string(value): return Double(value)
        default: return nil
        }
    }

    public func bytes(_ column: String) -> Data? {
        guard case let .bytes(value) = self[column] else { return nil }
        return value
    }
}
