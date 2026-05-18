//
//  DatabaseConfig.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//

public struct DatabaseConfig: Sendable {
    public var host: String
    public var port: Int
    public var user: String
    public var password: String
    public var database: String?

    public init(host: String = "127.0.0.1", port: Int = 3306, user: String, password: String, database: String? = nil) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
    }
}
