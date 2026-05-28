extension Connection {
    @discardableResult
    public func transaction<Result>(_ block: () throws -> Result) throws -> Result {
        try self.execute("START TRANSACTION")
        do {
            let result = try block()
            try self.execute("COMMIT")
            return result
        } catch {
            _ = try? self.execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    public func transaction<Result>(_ block: () async throws -> Result) async throws -> Result {
        try await self.execute("START TRANSACTION")
        do {
            let result = try await block()
            try await self.execute("COMMIT")
            return result
        } catch {
            _ = try? await self.execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    public func savepoint<Result>(_ name: String = "database_driver_savepoint", _ block: () throws -> Result) throws -> Result {
        let identifier = SQLBuilder.quoteIdentifier(name)
        try self.execute("SAVEPOINT \(identifier)")
        do {
            let result = try block()
            try self.execute("RELEASE SAVEPOINT \(identifier)")
            return result
        } catch {
            _ = try? self.execute("ROLLBACK TO SAVEPOINT \(identifier)")
            _ = try? self.execute("RELEASE SAVEPOINT \(identifier)")
            throw error
        }
    }

    @discardableResult
    public func savepoint<Result>(_ name: String = "database_driver_savepoint", _ block: () async throws -> Result) async throws -> Result {
        let identifier = SQLBuilder.quoteIdentifier(name)
        try await self.execute("SAVEPOINT \(identifier)")
        do {
            let result = try await block()
            try await self.execute("RELEASE SAVEPOINT \(identifier)")
            return result
        } catch {
            _ = try? await self.execute("ROLLBACK TO SAVEPOINT \(identifier)")
            _ = try? await self.execute("RELEASE SAVEPOINT \(identifier)")
            throw error
        }
    }
}