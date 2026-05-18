//
//  DatabaseColumn.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//

public struct DatabaseColumn: Equatable, Sendable {
    public let name: String
    public let type: DatabaseColumnType
    public let isUnsigned: Bool
    public let isBinary: Bool
    public let length: UInt32

    public init(name: String, type: DatabaseColumnType = .string, isUnsigned: Bool = false, isBinary: Bool = false, length: UInt32 = 0) {
        self.name = name
        self.type = type
        self.isUnsigned = isUnsigned
        self.isBinary = isBinary
        self.length = length
    }
}