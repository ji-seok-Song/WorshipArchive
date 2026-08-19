import Foundation

enum AppDestination: String, CaseIterable, Hashable, Identifiable {
    case home
    case search
    case library
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "홈"
        case .search: "검색"
        case .library: "라이브러리"
        case .settings: "설정"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .library: "music.note.list"
        case .settings: "gearshape"
        }
    }
}
