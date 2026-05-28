//
//  ConnectionPool.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//
import Foundation

public final class ConnectionPool: @unchecked Sendable {
    public let config: DatabaseConfig
    public let maxConnections: Int

    private let condition = NSCondition()
    private var idle: [Connection] = []
    private var totalConnections = 0
    private var isClosed = false

    public init(config: DatabaseConfig, maxConnections: Int = 10) {
        self.config = config
        self.maxConnections = max(1, maxConnections)
    }

    deinit {
        self.close()
    }

    @discardableResult
    public func execute(_ sql: String) throws -> QueryResult {
        try self.withConnection { client in
            try client.execute(sql)
        }
    }

    @discardableResult
    public func execute(_ sql: String) async throws -> QueryResult {
        try await runBlocking {
            try self.execute(sql)
        }
    }

    public func query(_ sql: String) throws -> [[String: String]] {
        try self.withConnection { client in
            try client.query(sql)
        }
    }

    public func query(_ sql: String) async throws -> [[String: String]] {
        try await runBlocking {
            try self.query(sql)
        }
    }

    public func withConnection<T>(_ body: (Connection) throws -> T) throws -> T {
        let client = try self.acquire()
        do {
            let result = try body(client)
            self.release(client, reusable: client.isConnected)
            return result
        } catch {
            let reusable = client.isConnected && self.canReuseAfterError(error)
            self.release(client, reusable: reusable)
            throw error
        }
    }

    public func withConnection<T: Sendable>(_ body: @escaping @Sendable (Connection) async throws -> T) async throws -> T {
        let client = try await runBlocking {
            try self.acquire()
        }
        do {
            let result = try await body(client)
            self.release(client, reusable: client.isConnected)
            return result
        } catch {
            let reusable = client.isConnected && self.canReuseAfterError(error)
            self.release(client, reusable: reusable)
            throw error
        }
    }

    public func close() {
        self.condition.lock()
        self.isClosed = true
        let clients = self.idle
        self.idle.removeAll()
        self.totalConnections -= clients.count
        self.condition.broadcast()
        self.condition.unlock()

        for client in clients {
            client.disconnect()
        }
    }

    public func close() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                self.close()
                continuation.resume()
            }
        }
    }

    private func acquire() throws -> Connection {
        while true {
            self.condition.lock()
            if self.isClosed {
                self.condition.unlock()
                throw ConnectionError.connectionFailed("pool is closed")
            }
            if let client = self.idle.popLast() {
                self.condition.unlock()
                return client
            }
            if self.totalConnections < self.maxConnections {
                self.totalConnections += 1
                self.condition.unlock()
                let client = Connection(config: self.config)
                do {
                    try client.connect()
                    return client
                } catch {
                    self.condition.lock()
                    self.totalConnections -= 1
                    self.condition.signal()
                    self.condition.unlock()
                    throw error
                }
            }
            self.condition.wait()
            self.condition.unlock()
        }
    }

    private func release(_ client: Connection, reusable: Bool) {
        if reusable {
            self.condition.lock()
            if self.isClosed {
                self.totalConnections -= 1
                self.condition.signal()
                self.condition.unlock()
                client.disconnect()
            } else {
                self.idle.append(client)
                self.condition.signal()
                self.condition.unlock()
            }
        } else {
            client.disconnect()
            self.condition.lock()
            self.totalConnections -= 1
            self.condition.signal()
            self.condition.unlock()
        }
    }

    private func canReuseAfterError(_ error: Error) -> Bool {
        if case ConnectionError.serverError = error { return true }
        return false
    }
}
