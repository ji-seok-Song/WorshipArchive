import Foundation

nonisolated enum KeySignature: Hashable, Sendable {
    case none
    case sharps(Int)
    case flats(Int)
}

nonisolated enum KeySignatureKeyMap {
    static func musicalKey(for signature: KeySignature) -> MusicalKey? {
        switch signature {
        case .none:
            .cMajor
        case .sharps(let count):
            switch count {
            case 0: .cMajor
            case 1: .gMajor
            case 2: .dMajor
            case 3: .aMajor
            case 4: .eMajor
            case 5: .bMajor
            case 6: .fSharpMajor
            default: nil
            }
        case .flats(let count):
            switch count {
            case 0: .cMajor
            case 1: .fMajor
            case 2: .bFlatMajor
            case 3: .eFlatMajor
            case 4: .aFlatMajor
            case 5: .cSharpMajor
            case 6: .fSharpMajor
            default: nil
            }
        }
    }
}

nonisolated enum KeySignatureChoice: String, CaseIterable, Identifiable, Sendable {
    case unspecified
    case none
    case sharp1
    case sharp2
    case sharp3
    case sharp4
    case sharp5
    case sharp6
    case flat1
    case flat2
    case flat3
    case flat4
    case flat5
    case flat6

    var id: Self { self }

    var displayName: String {
        switch self {
        case .unspecified: "미지정"
        case .none: "조표 없음 · C"
        case .sharp1: "♯ 1개 · G"
        case .sharp2: "♯ 2개 · D"
        case .sharp3: "♯ 3개 · A"
        case .sharp4: "♯ 4개 · E"
        case .sharp5: "♯ 5개 · B"
        case .sharp6: "♯ 6개 · F♯"
        case .flat1: "♭ 1개 · F"
        case .flat2: "♭ 2개 · B♭"
        case .flat3: "♭ 3개 · E♭"
        case .flat4: "♭ 4개 · A♭"
        case .flat5: "♭ 5개 · D♭"
        case .flat6: "♭ 6개 · G♭"
        }
    }

    var musicalKey: MusicalKey? {
        guard let signature else { return nil }
        return KeySignatureKeyMap.musicalKey(for: signature)
    }

    private var signature: KeySignature? {
        switch self {
        case .unspecified: nil
        case .none: KeySignature.none
        case .sharp1: .sharps(1)
        case .sharp2: .sharps(2)
        case .sharp3: .sharps(3)
        case .sharp4: .sharps(4)
        case .sharp5: .sharps(5)
        case .sharp6: .sharps(6)
        case .flat1: .flats(1)
        case .flat2: .flats(2)
        case .flat3: .flats(3)
        case .flat4: .flats(4)
        case .flat5: .flats(5)
        case .flat6: .flats(6)
        }
    }
}
