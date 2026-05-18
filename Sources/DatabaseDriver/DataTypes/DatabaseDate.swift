//
//  DatabaseDate.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//

public struct DatabaseDate: Equatable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var description: String { String(format: "%04d-%02d-%02d", self.year, self.month, self.day) }
}
