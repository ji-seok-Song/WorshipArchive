import CoreGraphics
import XCTest
@testable import WorshipArchive

final class PDFTextFontSizingTests: XCTestCase {
    func testExtremeFinitePointSizeIsClampedBeforeBucketing() throws {
        let pointSize = try XCTUnwrap(
            PDFTextFontSizing.bucketedPointSize(.greatestFiniteMagnitude)
        )

        XCTAssertTrue(pointSize.isFinite)
        XCTAssertEqual(pointSize, PDFTextFontSizing.maximumPointSize)
    }

    func testNonFiniteAndNonPositivePointSizesAreRejected() {
        XCTAssertNil(PDFTextFontSizing.bucketedPointSize(.infinity))
        XCTAssertNil(PDFTextFontSizing.bucketedPointSize(.nan))
        XCTAssertNil(PDFTextFontSizing.bucketedPointSize(0))
        XCTAssertNil(PDFTextFontSizing.bucketedPointSize(-1))
    }
}
