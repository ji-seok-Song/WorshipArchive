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

        if syncsWithCloudKit, !inMemory {
            try createCloudMigrationBackupIfNeeded(
                storeURL: configuration.url
            )
        }

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    static func cloudMigrationBackupURL(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent()
            .appending(
                path: "WorshipArchive-CloudMigrationBackup-v1",
                directoryHint: .isDirectory
            )
    }

    private static func createCloudMigrationBackupIfNeeded(
        storeURL: URL
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        let backupURL = cloudMigrationBackupURL(for: storeURL)
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }

        let temporaryBackupURL = backupURL
            .deletingLastPathComponent()
            .appending(
                path: "WorshipArchive-CloudMigrationBackup-v1-\(UUID().uuidString).partial",
                directoryHint: .isDirectory
            )

        do {
            try fileManager.createDirectory(
                at: temporaryBackupURL,
                withIntermediateDirectories: false
            )

            for sourceURL in storeFiles(for: storeURL) where
                fileManager.fileExists(atPath: sourceURL.path)
            {
                try fileManager.copyItem(
                    at: sourceURL,
                    to: temporaryBackupURL.appending(path: sourceURL.lastPathComponent)
                )
            }

            try fileManager.moveItem(
                at: temporaryBackupURL,
                to: backupURL
            )
        } catch {
            try? fileManager.removeItem(at: temporaryBackupURL)
            throw error
        }
    }

    private static func storeFiles(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(filePath: storeURL.path + "-wal"),
            URL(filePath: storeURL.path + "-shm")
        ]
    }
}

struct ModelContainerStartupError: LocalizedError {
    let details: String

    var errorDescription: String? {
        "악보 저장소를 열 수 없습니다."
    }
}
