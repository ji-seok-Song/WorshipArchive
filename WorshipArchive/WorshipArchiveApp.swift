//
//  WorshipArchiveApp.swift
//  WorshipArchive
//
//  Created by JISEOK SONG on 8/19/26.
//

import SwiftUI
import SwiftData

@main
struct WorshipArchiveApp: App {
    private let services = ArchiveServices.live

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch AppModelContainer.production {
        case .success(let modelContainer):
            ContentView(
                fileStore: services.fileStore,
                syncCoordinator: services.syncCoordinator
            )
                .tint(ArchiveTheme.tint)
                .modelContainer(modelContainer)
        case .failure(let error):
            PersistenceUnavailableView(error: error)
                .tint(ArchiveTheme.tint)
        }
    }
}
