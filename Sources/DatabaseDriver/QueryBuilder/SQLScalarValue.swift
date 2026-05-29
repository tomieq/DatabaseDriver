//
//  SQLScalarValue.swift
//  DatabaseDriver
//
//  Created by: tomieq on 29/05/2026
//
import Foundation

public protocol SQLScalarValue: Sendable {
    static func scalarValue(from value: DatabaseValue) -> Self?
}

extension Int: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> Int? {
        switch value {
        case let .integer(value): return Int(exactly: value)
        case let .unsignedInteger(value): return Int(exactly: value)
        case let .string(value): return Int(value)
        default: return nil
        }
    }
}

extension Int8: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> Int8? {
        switch value {
        case let .integer(value): return Int8(exactly: value)
        case let .unsignedInteger(value): return Int8(exactly: value)
        case let .string(value): return Int8(value)
        default: return nil
        }
    }
}

extension Int16: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> Int16? {
        switch value {
        case let .integer(value): return Int16(exactly: value)
        case let .unsignedInteger(value): return Int16(exactly: value)
        case let .string(value): return Int16(value)
        default: return nil
        }
    }
}

extension Int32: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> Int32? {
        switch value {
        case let .integer(value): return Int32(exactly: value)
        case let .unsignedInteger(value): return Int32(exactly: value)
        case let .string(value): return Int32(value)
        default: return nil
        }
    }
}

extension Int64: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> Int64? {
        switch value {
        case let .integer(value): return value
        case let .unsignedInteger(value): return Int64(exactly: value)
        case let .string(value): return Int64(value)
        default: return nil
        }
    }
}

extension UInt: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> UInt? {
        switch value {
        case let .unsignedInteger(value): return UInt(exactly: value)
        case let .integer(value): return UInt(exactly: value)
        case let .string(value): return UInt(value)
        default: return nil
        }
    }
}

extension UInt8: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> UInt8? {
        switch value {
        case let .unsignedInteger(value): return UInt8(exactly: value)
        case let .integer(value): return UInt8(exactly: value)
        case let .string(value): return UInt8(value)
        default: return nil
        }
    }
}

extension UInt16: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> UInt16? {
        switch value {
        case let .unsignedInteger(value): return UInt16(exactly: value)
        case let .integer(value): return UInt16(exactly: value)
        case let .string(value): return UInt16(value)
        default: return nil
        }
    }
}

extension UInt32: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> UInt32? {
        switch value {
        case let .unsignedInteger(value): return UInt32(exactly: value)
        case let .integer(value): return UInt32(exactly: value)
        case let .string(value): return UInt32(value)
        default: return nil
        }
    }
}

extension UInt64: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> UInt64? {
        switch value {
        case let .unsignedInteger(value): return value
        case let .integer(value): return UInt64(exactly: value)
        case let .string(value): return UInt64(value)
        default: return nil
        }
    }
}

extension Double: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> Double? {
        switch value {
        case let .double(value): return value
        case let .decimal(value): return Double(value)
        case let .integer(value): return Double(value)
        case let .unsignedInteger(value): return Double(value)
        case let .string(value): return Double(value)
        default: return nil
        }
    }
}

extension Float: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> Float? {
        Double.scalarValue(from: value).map(Float.init)
    }
}

extension Decimal: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> Decimal? {
        switch value {
        case let .decimal(value): return Decimal(string: value)
        case let .string(value): return Decimal(string: value)
        case let .integer(value): return Decimal(value)
        case let .unsignedInteger(value): return Decimal(value)
        case let .double(value): return Decimal(value)
        default: return nil
        }
    }
}

extension String: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> String? {
        value.stringValue
    }
}

extension Bool: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> Bool? {
        switch value {
        case let .bool(value): return value
        case let .integer(value): return value != 0
        case let .unsignedInteger(value): return value != 0
        case let .string(value) where value == "1" || value.lowercased() == "true": return true
        case let .string(value) where value == "0" || value.lowercased() == "false": return false
        default: return nil
        }
    }
}

extension DatabaseValue: SQLScalarValue {
    public static func scalarValue(from value: DatabaseValue) -> DatabaseValue? {
        value
    }
}