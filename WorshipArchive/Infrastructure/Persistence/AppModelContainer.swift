import Foundation
import SwiftData

enum AppModelContainer {
    static let cloudKitContainerIdentifier = "iCloud.com.jacky.WorshipArchive"

    static let schema = Schema([
        ArchiveDocument.self,
        PageAnalysis.self,
        Song.self,
        SongSheet.self,
        PerformanceRecord.self
    ])

    static let production: Result<ModelContainer, ModelContainerStartupError> = {
        do {
            return .success(try make())
        } catch {
            return .failure(
                ModelContainerStartupError(details: error.localizedDescription)
            )
        }
    }()

    static let preview: ModelContainer = {
        do {
            return try make(inMemory: true)
        } catch {
            fatalError("미리보기 저장소를 만들 수 없습니다: \(error.localizedDescription)")
        }
    }()

    static func make(
        inMemory: Bool = false,
        syncsWithCloudKit: Bool = true,
        storageURL: URL? = nil
    ) throws -> ModelContainer {
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase =
            inMemory || !syncsWithCloudKit
            ? .none
            : .private(cloudKitContainerIdentifier)

        let configuration: ModelConfiguration
        if let storageURL {
            configuration = ModelConfiguration(
                "WorshipArchive",
                schema: schema,
                url: storageURL,
                cloudKitDatabase: cloudKitDatabase
            )
        } else {
            configuration = ModelConfiguration(
                "WorshipArchive",
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: cloudKitDatabase
            )
        }

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}

struct ModelContainerStartupError: LocalizedError {
    let details: String

    var errorDescription: String? {
        "악보 저장소를 열 수 없습니다."
    }
}
