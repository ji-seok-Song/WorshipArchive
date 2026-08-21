import XCTest
@testable import WorshipArchive

final class ScoreKeyDetectorTests: XCTestCase {
    private let detector = ScoreKeyDetector()

    func testDetectsDMajorFromLeadSheetChords() {
        let result = detector.detect(
            in: "Dadd9 D/F# GM7 A D A7 D Bm7 Em7 A D"
        )

        XCTAssertEqual(result?.musicalKey, .dMajor)
        XCTAssertGreaterThanOrEqual(result?.confidence ?? 0, 0.65)
    }

    func testDetectsEMajorWithSharpsAndSlashChords() {
        let result = detector.detect(
            in: "E B/D# C#m7 Bm7 E7 A E/G# F#m7 B7 E"
        )

        XCTAssertEqual(result?.musicalKey, .eMajor)
    }

    func testReturnsOnlyRootForMinorChordProgression() {
        let result = detector.detect(
            in: "Am Dm G C F Bdim E7 Am"
        )

        XCTAssertEqual(result?.musicalKey, .aMajor)
    }

    func testLeavesInsufficientEvidenceUnspecified() {
        XCTAssertNil(detector.detect(in: "C"))
        XCTAssertNil(detector.detect(in: "주님을 찬양합니다 영원히"))
    }

    func testSelectableKeysContainOnlyTwelvePitchNames() {
        XCTAssertEqual(MusicalKey.allCases.count, 12)
        XCTAssertFalse(MusicalKey.allCases.map(\.displayName).contains { $0.hasSuffix("m") })
        XCTAssertEqual(MusicalKey.aMinor.pitchOnly, .aMajor)
    }
}
