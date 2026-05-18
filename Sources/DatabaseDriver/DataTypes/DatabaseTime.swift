//
//  DatabaseTime.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//

public struct DatabaseTime: Equatable, Sendable, CustomStringConvertible {
    public let isNegative: Bool
    public let hours: Int
    public let minutes: Int
    public let seconds: Int
    public let microseconds: Int

    public init(isNegative: Bool = false, hours: Int, minutes: Int, seconds: Int, microseconds: Int = 0) {
        self.isNegative = isNegative
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.microseconds = microseconds
    }

    public var description: String {
        let prefix = self.isNegative ? "-" : ""
        let base = String(format: "%@%02d:%02d:%02d", prefix, self.hours, self.minutes, self.seconds)
        if self.microseconds == 0 { return base }
        return base + String(format: ".%06d", self.microseconds)
    }
}