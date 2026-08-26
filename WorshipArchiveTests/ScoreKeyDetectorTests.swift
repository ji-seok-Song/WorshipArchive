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

    func testConsensusUsesRepeatedCountInsteadOfFirstStaff() {
        let result = KeySignatureConsensus.resolve([
            KeySignatureEvidence(signature: .flats(1), strength: 0.42),
            KeySignatureEvidence(signature: .sharps(4), strength: 0.31),
            KeySignatureEvidence(signature: .sharps(4), strength: 0.36),
            KeySignatureEvidence(signature: .sharps(4), strength: 0.34),
            KeySignatureEvidence(signature: .sharps(2), strength: 0.38)
        ])

        XCTAssertEqual(result?.signature, .sharps(4))
    }

    func testConsensusRejectsTiedAccidentalCounts() {
        let result = KeySignatureConsensus.resolve([
            KeySignatureEvidence(signature: .sharps(3), strength: 0.42),
            KeySignatureEvidence(signature: .sharps(3), strength: 0.38),
            KeySignatureEvidence(signature: .flats(2), strength: 0.39),
            KeySignatureEvidence(signature: .flats(2), strength: 0.37)
        ])

        XCTAssertNil(result)
    }

    func testConsensusUsesMedianWhenStaffCountsAreOffByOne() {
        let result = KeySignatureConsensus.resolve([
            KeySignatureEvidence(signature: .sharps(3), strength: 0.48),
            KeySignatureEvidence(signature: .sharps(5), strength: 0.43),
            KeySignatureEvidence(signature: .sharps(3), strength: 0.54),
            KeySignatureEvidence(signature: .sharps(4), strength: 0.51),
            KeySignatureEvidence(signature: .sharps(4), strength: 0.50)
        ])

        XCTAssertEqual(result?.signature, .sharps(4))
    }

    func testBlankKeyNeedsThreeAgreeingStaves() {
        XCTAssertNil(KeySignatureConsensus.resolve([
            KeySignatureEvidence(signature: .none, strength: 0.35),
            KeySignatureEvidence(signature: .none, strength: 0.35)
        ]))

        XCTAssertEqual(
            KeySignatureConsensus.resolve([
                KeySignatureEvidence(signature: .none, strength: 0.35),
                KeySignatureEvidence(signature: .none, strength: 0.35),
                KeySignatureEvidence(signature: .none, strength: 0.35)
            ])?.signature,
            KeySignature.none
        )
    }

    func testReviewChoiceImmediatelyResolvesToRequestedKey() {
        XCTAssertEqual(KeySignatureChoice.none.musicalKey, .cMajor)
        XCTAssertEqual(KeySignatureChoice.sharp3.musicalKey, .aMajor)
        XCTAssertEqual(KeySignatureChoice.flat5.musicalKey, .cSharpMajor)
    }

    func testDetectedSignatureSelectsMatchingReviewChoice() {
        XCTAssertEqual(KeySignatureChoice(signature: KeySignature.none), .none)
        XCTAssertEqual(KeySignatureChoice(signature: .sharps(3)), .sharp3)
        XCTAssertEqual(KeySignatureChoice(signature: .flats(4)), .flat4)
        XCTAssertEqual(KeySignatureChoice(signature: .sharps(7)), .unspecified)
    }

    func testSelectableKeysContainOnlyTwelvePitchNames() {
        XCTAssertEqual(MusicalKey.allCases.count, 12)
        XCTAssertFalse(MusicalKey.allCases.map(\.displayName).contains { $0.hasSuffix("m") })
        XCTAssertEqual(MusicalKey.aMinor.pitchOnly, .aMajor)
    }
}
