import XCTest
@testable import DatabaseDriver

final class DatabaseDriverTests: XCTestCase {
    func testSHA1Known() throws {
        let d = "abc".data(using: .utf8)!
        let hash = SHA1.hash(data: d)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "a9993e364706816aba3e25717850c26c9cd0d89d")
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
