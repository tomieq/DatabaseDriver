//
//  DatabaseValue.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//
import Foundation

public enum DatabaseValue: Equatable, Sendable, CustomStringConvertible {
    case null
    case bool(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case double(Double)
    case decimal(String)
    case string(String)
    case bytes(Data)
    case date(DatabaseDate)
    case time(DatabaseTime)
    case dateTime(DatabaseDateTime)

    public var stringValue: String? {
        switch self {
        case .null: return nil
        case let .bool(value): return value ? "1" : "0"
        case let .integer(value): return String(value)
        case let .unsignedInteger(value): return String(value)
        case let .double(value): return String(value)
        case let .decimal(value): return value
        case let .string(value): return value
        case let .bytes(value): return String(data: value, encoding: .utf8)
        case let .date(value): return value.description
        case let .time(value): return value.description
        case let .dateTime(value): return value.description
        }
    }

    public var description: String {
        self.stringValue ?? "NULL"
    }
}
