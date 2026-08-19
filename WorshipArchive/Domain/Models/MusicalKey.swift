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
        case .cMinor: "Cm"
        case .cSharpMinor: "C♯m/D♭m"
        case .dMinor: "Dm"
        case .eFlatMinor: "E♭m"
        case .eMinor: "Em"
        case .fMinor: "Fm"
        case .fSharpMinor: "F♯m/G♭m"
        case .gMinor: "Gm"
        case .aFlatMinor: "A♭m"
        case .aMinor: "Am"
        case .bFlatMinor: "B♭m"
        case .bMinor: "Bm"
        }
    }
}
