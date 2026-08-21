import Foundation

enum MusicalKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case cMajor
    case cSharpMajor
    case dMajor
    case eFlatMajor
    case eMajor
    case fMajor
    case fSharpMajor
    case gMajor
    case aFlatMajor
    case aMajor
    case bFlatMajor
    case bMajor
    case cMinor
    case cSharpMinor
    case dMinor
    case eFlatMinor
    case eMinor
    case fMinor
    case fSharpMinor
    case gMinor
    case aFlatMinor
    case aMinor
    case bFlatMinor
    case bMinor

    static let allCases: [MusicalKey] = [
        .cMajor, .cSharpMajor, .dMajor, .eFlatMajor, .eMajor, .fMajor,
        .fSharpMajor, .gMajor, .aFlatMajor, .aMajor, .bFlatMajor, .bMajor
    ]

    var id: Self { self }

    var displayName: String {
        switch self {
        case .cMajor: "C"
        case .cSharpMajor: "C♯/D♭"
        case .dMajor: "D"
        case .eFlatMajor: "E♭"
        case .eMajor: "E"
        case .fMajor: "F"
        case .fSharpMajor: "F♯/G♭"
        case .gMajor: "G"
        case .aFlatMajor: "A♭"
        case .aMajor: "A"
        case .bFlatMajor: "B♭"
        case .bMajor: "B"
        case .cMinor: "C"
        case .cSharpMinor: "C♯/D♭"
        case .dMinor: "D"
        case .eFlatMinor: "E♭"
        case .eMinor: "E"
        case .fMinor: "F"
        case .fSharpMinor: "F♯/G♭"
        case .gMinor: "G"
        case .aFlatMinor: "A♭"
        case .aMinor: "A"
        case .bFlatMinor: "B♭"
        case .bMinor: "B"
        }
    }

    var pitchOnly: MusicalKey {
        switch self {
        case .cMajor, .cMinor: .cMajor
        case .cSharpMajor, .cSharpMinor: .cSharpMajor
        case .dMajor, .dMinor: .dMajor
        case .eFlatMajor, .eFlatMinor: .eFlatMajor
        case .eMajor, .eMinor: .eMajor
        case .fMajor, .fMinor: .fMajor
        case .fSharpMajor, .fSharpMinor: .fSharpMajor
        case .gMajor, .gMinor: .gMajor
        case .aFlatMajor, .aFlatMinor: .aFlatMajor
        case .aMajor, .aMinor: .aMajor
        case .bFlatMajor, .bFlatMinor: .bFlatMajor
        case .bMajor, .bMinor: .bMajor
        }
    }
}
