//
//  DatabaseExpressionValue.swift
//  DatabaseDriver
//
//  Created by: tomieq on 28/05/2026
//
import Foundation

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

extension Float: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .double(Double(self)) }
}

extension Decimal: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .decimal(NSDecimalNumber(decimal: self).stringValue) }
}

extension Bool: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .bool(self) }
}

extension Data: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .bytes(self) }
}

extension Date: DatabaseExpressionValue {
    public var databaseValue: DatabaseValue { .integer(Int64(self.timeIntervalSince1970)) }
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
