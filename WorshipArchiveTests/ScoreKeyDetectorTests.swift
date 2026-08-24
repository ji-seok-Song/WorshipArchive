import XCTest
@testable import WorshipArchive

final class ScoreKeyDetectorTests: XCTestCase {
    func testSharpCountMappingUsesCircleOfFifthsFormula() {
        let expected: [MusicalKey] = [
            .cMajor, .gMajor, .dMajor, .aMajor,
            .eMajor, .bMajor, .fSharpMajor
        ]

        XCTAssertEqual(
            (0...6).compactMap { KeySignatureKeyMap.musicalKey(for: .sharps($0)) },
            expected
        )
    }

    func testFlatCountMappingUsesCircleOfFifthsFormula() {
        let expected: [MusicalKey] = [
            .cMajor, .fMajor, .bFlatMajor, .eFlatMajor,
            .aFlatMajor, .cSharpMajor, .fSharpMajor
        ]

        XCTAssertEqual(
            (0...6).compactMap { KeySignatureKeyMap.musicalKey(for: .flats($0)) },
            expected
        )
    }

    func testUnsupportedAccidentalCountIsNotGuessed() {
        XCTAssertNil(KeySignatureKeyMap.musicalKey(for: .sharps(7)))
        XCTAssertNil(KeySignatureKeyMap.musicalKey(for: .flats(7)))
    }

    func testReviewChoiceImmediatelyResolvesToRequestedKey() {
        XCTAssertEqual(KeySignatureChoice.none.musicalKey, .cMajor)
        XCTAssertEqual(KeySignatureChoice.sharp3.musicalKey, .aMajor)
        XCTAssertEqual(KeySignatureChoice.flat5.musicalKey, .cSharpMajor)
    }

    func testSelectableKeysContainOnlyTwelvePitchNames() {
        XCTAssertEqual(MusicalKey.allCases.count, 12)
        XCTAssertFalse(MusicalKey.allCases.map(\.displayName).contains { $0.hasSuffix("m") })
        XCTAssertEqual(MusicalKey.aMinor.pitchOnly, .aMajor)
    }
}
