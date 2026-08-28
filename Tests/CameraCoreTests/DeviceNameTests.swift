import XCTest
@testable import CameraCore

final class DeviceNameTests: XCTestCase {
    func testExactMatchAfterTrimmingWhitespaceOnly() {
        let a = DeviceName("  iPhone Camera  \n")
        let b = DeviceName("iPhone Camera")
        XCTAssertTrue(a.matches(b))
        XCTAssertEqual(a.value, "iPhone Camera")
    }

    func testNeverMatchesAsSubstring() {
        let requested = DeviceName("iPhone")
        XCTAssertFalse(requested.matches("iPhone Camera"))
        XCTAssertFalse(DeviceName("iPhone Camera").matches("iPhone"))
    }

    func testCaseIsSignificant() {
        XCTAssertFalse(DeviceName("iphone camera").matches("iPhone Camera"))
    }

    func testPreservesApostrophesParenthesesAndUnicode() {
        let name = DeviceName("Bénédicte's iPhone Camera (2)")
        XCTAssertEqual(name.value, "Bénédicte's iPhone Camera (2)")
        XCTAssertTrue(name.matches("Bénédicte's iPhone Camera (2)"))
        XCTAssertFalse(name.matches("Benedicte's iPhone Camera (2)"))
    }

    func testInternalWhitespaceIsPreserved() {
        let name = DeviceName("iPhone   Camera")
        XCTAssertFalse(name.matches("iPhone Camera"))
    }
}
