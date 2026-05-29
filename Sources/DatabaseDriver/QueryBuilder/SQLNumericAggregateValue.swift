//
//  SQLNumericAggregateValue.swift
//  DatabaseDriver
//
//  Created by: tomieq on 29/05/2026
//
import Foundation

public protocol SQLNumericAggregateValue: Sendable {}

extension Int: SQLNumericAggregateValue {}
extension Int8: SQLNumericAggregateValue {}
extension Int16: SQLNumericAggregateValue {}
extension Int32: SQLNumericAggregateValue {}
extension Int64: SQLNumericAggregateValue {}
extension UInt: SQLNumericAggregateValue {}
extension UInt8: SQLNumericAggregateValue {}
extension UInt16: SQLNumericAggregateValue {}
extension UInt32: SQLNumericAggregateValue {}
extension UInt64: SQLNumericAggregateValue {}
extension Float: SQLNumericAggregateValue {}
extension Double: SQLNumericAggregateValue {}
extension Decimal: SQLNumericAggregateValue {}