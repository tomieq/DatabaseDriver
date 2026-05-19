import XCTest
@testable import DatabaseDriver

private struct CodableUser: Codable, Equatable {
    let id: Int64?
    let name: String
    let nickname: String?
    let enabled: Bool
    let birthday: DatabaseDate
    let payload: Data
}

private struct CodableUserPatch: Encodable {
    let name: String
    let nickname: String?
}

private struct SchemaUser: DatabaseSchemaRepresentable {
    let id: Int64
    let name: String
    let nickname: String?
    let enabled: Bool

    init() {
        self.id = 0
        self.name = ""
        self.nickname = nil
        self.enabled = false
    }
}

private struct SchemaUserSample {
    let id: Int64
    let name: String
    let payload: Data?
}

final class DatabaseDriverTests: XCTestCase {
    func testSHA1Known() throws {
        let d = "abc".data(using: .utf8)!
        let hash = SHA1.hash(data: d)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "a9993e364706816aba3e25717850c26c9cd0d89d")
    }

    func testObjectAPIBuildsSelectSQL() throws {
        let users = Table("users")
        let id = Expression<Int64>("id")
        let name = Expression<String>("name")
        let enabled = Expression<Bool>("enabled")

        let query = users
            .filter((id >= 10) && (enabled == true))
            .select(id, name)
            .order(name.asc())
            .limit(5, offset: 10)

        XCTAssertEqual(query.sql, "SELECT `id`, `name` FROM `users` WHERE (`id` >= 10) AND (`enabled` = TRUE) ORDER BY `name` ASC LIMIT 5 OFFSET 10")
    }

    func testObjectAPIBuildsInsertUpdateAndDeleteSQL() throws {
        let users = Table("users")
        let id = users.column("id", as: Int64.self)
        let name = users.column("name", as: String.self)
        let nickname = users.column("nickname", as: String?.self)
        let payload = users.column("payload", as: Data.self)

        let insert = users.insert(
            name <- "O'Hara = admin",
            nickname <- nil,
            payload <- Data([0x68, 0x69])
        )

        XCTAssertEqual(insert.sql, "INSERT INTO `users` (`name`, `nickname`, `payload`) VALUES ('O''Hara = admin', NULL, X'6869')")

        let update = users.update(name <- "bob").filter(id == 42)
        XCTAssertEqual(update.sql, "UPDATE `users` SET `users`.`name` = 'bob' WHERE `users`.`id` = 42")

        let delete = users.delete().filter(nickname == nil)
        XCTAssertEqual(delete.sql, "DELETE FROM `users` WHERE `users`.`nickname` IS NULL")
    }

    func testSchemaAPIBuildsCreateTableSQL() throws {
        let users = Table("users")
        let id = users.column("id", as: Int64.self)
        let email = users.column("email", as: String.self)
        let name = users.column("name", as: String?.self)
        let enabled = users.column("enabled", as: Bool.self)
        let createdAt = users.column("created_at", as: DatabaseDateTime.self)

        let create = users.create(ifNotExists: true) { table in
            table.column(id, primaryKey: .autoIncrement)
            table.column(email, type: .varchar(255), unique: true)
            table.column(name)
            table.column(enabled, defaultValue: true)
            table.column(createdAt)
            table.check(id > 0)
        }

        XCTAssertEqual(create.sql, "CREATE TABLE IF NOT EXISTS `users` (`id` BIGINT PRIMARY KEY AUTO_INCREMENT NOT NULL, `email` VARCHAR(255) NOT NULL UNIQUE, `name` TEXT, `enabled` BOOL NOT NULL DEFAULT TRUE, `created_at` DATETIME(6) NOT NULL, CHECK (`id` > 0))")
    }

    func testSchemaAPIBuildsIndexesAndDropSQL() throws {
        let users = Table("users")
        let email = users.column("email", as: String.self)
        let name = users.column("name", as: String?.self)

        XCTAssertEqual(users.createIndex(email).sql, "CREATE INDEX `index_users_on_email` ON `users` (`email`)")
        XCTAssertEqual(users.createIndex(email, name, named: "users_lookup", unique: true).sql, "CREATE UNIQUE INDEX `users_lookup` ON `users` (`email`, `name`)")
        XCTAssertEqual(users.dropIndex(email).sql, "DROP INDEX `index_users_on_email` ON `users`")
        XCTAssertEqual(users.drop(ifExists: true).sql, "DROP TABLE IF EXISTS `users`")
    }

    func testSchemaAPIBuildsCreateTableFromTypeSQL() throws {
        let users = Table("car_users")

        XCTAssertEqual(
            users.create(from: SchemaUser.self, ifNotExists: true).sql,
            "CREATE TABLE IF NOT EXISTS `car_users` (`id` BIGINT NOT NULL, `name` TEXT NOT NULL, `nickname` TEXT, `enabled` BOOL NOT NULL)"
        )
    }

    func testSchemaAPIBuildsCreateTableFromTypeWithOverridesSQL() throws {
        let users = Table("car_users")

        XCTAssertEqual(
            users.create(from: SchemaUser.self, ifNotExists: true) { table in
                table.column(named: "birthday", type: .date, notNull: false)
            }.sql,
            "CREATE TABLE IF NOT EXISTS `car_users` (`id` BIGINT NOT NULL, `name` TEXT NOT NULL, `nickname` TEXT, `enabled` BOOL NOT NULL, `birthday` DATE)"
        )
    }

    func testSchemaAPIBuildsCreateTableFromSampleSQL() throws {
        let users = Table("sample_users")

        XCTAssertEqual(
            users.create(from: SchemaUserSample(id: 0, name: "", payload: Data())).sql,
            "CREATE TABLE `sample_users` (`id` BIGINT NOT NULL, `name` TEXT NOT NULL, `payload` BLOB)"
        )
    }

    func testCodableAPIBuildsInsertAndUpdateSQL() throws {
        let users = Table("users")
        let id = users.column("id", as: Int64.self)

        let user = CodableUser(
            id: nil,
            name: "O'Hara",
            nickname: nil,
            enabled: true,
            birthday: DatabaseDate(year: 2026, month: 5, day: 19),
            payload: Data([0x68, 0x69])
        )

        XCTAssertEqual(
            try users.insert(user).sql,
            "INSERT INTO `users` (`birthday`, `enabled`, `id`, `name`, `nickname`, `payload`) VALUES ('2026-05-19', TRUE, NULL, 'O''Hara', NULL, X'6869')"
        )

        let patch = CodableUserPatch(name: "alice", nickname: nil)
        XCTAssertEqual(
            try users.update(patch).filter(id == 42).sql,
            "UPDATE `users` SET `users`.`name` = 'alice', `users`.`nickname` = NULL WHERE `users`.`id` = 42"
        )
    }

    func testCodableAPIDecodesRows() throws {
        let row = DatabaseRow(
            values: [],
            valuesByColumn: [
                "id": .integer(42),
                "name": .string("alice"),
                "nickname": .null,
                "enabled": .bool(true),
                "birthday": .date(DatabaseDate(year: 2026, month: 5, day: 19)),
                "payload": .bytes(Data([0x68, 0x69]))
            ]
        )

        XCTAssertEqual(
            try row.decode(CodableUser.self),
            CodableUser(
                id: 42,
                name: "alice",
                nickname: nil,
                enabled: true,
                birthday: DatabaseDate(year: 2026, month: 5, day: 19),
                payload: Data([0x68, 0x69])
            )
        )
    }

    func testAsyncPoolReportsClosedPool() async throws {
        let pool = DatabasePool(config: DatabaseConfig(user: "root", password: ""), maxConnections: 1)
        await pool.close()

        do {
            _ = try await pool.execute("SELECT 1")
            XCTFail("Expected closed pool to throw")
        } catch DatabaseError.connectionFailed(let message) {
            XCTAssertEqual(message, "pool is closed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
