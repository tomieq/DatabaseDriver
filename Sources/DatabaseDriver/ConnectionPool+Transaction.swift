extension ConnectionPool {
    @discardableResult
    public func transaction<Result>(_ block: (Connection) throws -> Result) throws -> Result {
        try self.withConnection { connection in
            try connection.transaction {
                try block(connection)
            }
        }
    }

    @discardableResult
    public func transaction<Result: Sendable>(_ block: @escaping @Sendable (Connection) async throws -> Result) async throws -> Result {
        try await self.withConnection { connection in
            try await connection.transaction {
                try await block(connection)
            }
        }
    }

    @discardableResult
    public func savepoint<Result>(_ name: String = "database_driver_savepoint", _ block: (Connection) throws -> Result) throws -> Result {
        try self.withConnection { connection in
            try connection.savepoint(name) {
                try block(connection)
            }
        }
    }

    @discardableResult
    public func savepoint<Result: Sendable>(_ name: String = "database_driver_savepoint", _ block: @escaping @Sendable (Connection) async throws -> Result) async throws -> Result {
        try await self.withConnection { connection in
            try await connection.savepoint(name) {
                try await block(connection)
            }
        }
    }
}