import XCTest
@testable import IrmaServerSwift

final class IrmaServerSwiftTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertThrowsError(try Initialize(configuration: "{}"))
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
