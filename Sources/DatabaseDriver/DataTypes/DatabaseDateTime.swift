//
//  DatabaseDateTime.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//

public struct DatabaseDateTime: Equatable, Sendable, CustomStringConvertible {
    public let date: DatabaseDate
    public let time: DatabaseTime

    public init(date: DatabaseDate, time: DatabaseTime) {
        self.date = date
        self.time = time
    }

    public var description: String { "\(self.date) \(self.time)" }
}