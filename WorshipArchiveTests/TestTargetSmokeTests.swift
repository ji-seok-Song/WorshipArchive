import XCTest
@testable import WorshipArchive

final class TestTargetSmokeTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertEqual(SearchTextNormalizer.normalize("  주 사랑  "), "주 사랑")
    }
}
