//
//  SQLOptionalValue.swift
//  DatabaseDriver
//
//  Created by: tomieq on 29/05/2026
//

public protocol SQLOptionalValue {
    associatedtype Wrapped: Sendable
}

extension Optional: SQLOptionalValue {}