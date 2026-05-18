//
//  DatabaseColumnType.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//

public enum DatabaseColumnType: Equatable, Sendable {
    case decimal
    case tinyInteger
    case smallInteger
    case integer
    case float
    case double
    case null
    case timestamp
    case bigInteger
    case mediumInteger
    case date
    case time
    case dateTime
    case year
    case varchar
    case bit
    case json
    case enumValue
    case set
    case blob
    case varString
    case string
    case geometry
    case unknown(UInt8)
}
