import XCTest
@testable import DatabaseDriver

final class DatabaseDriverTests: XCTestCase {
    func testSHA1Known() throws {
        let d = "abc".data(using: .utf8)!
        let hash = SHA1.hash(data: d)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "a9993e364706816aba3e25717850c26c9cd0d89d")
    }
}
