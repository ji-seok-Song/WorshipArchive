import CloudKit
import CryptoKit
import Foundation

nonisolated struct CloudKitPDFAssetRecord: Equatable, Sendable {
    let recordType: String
    let recordName: String
    let zoneName: String
    let checksum: String?
    let fileSize: Int64?
    let pageCount: Int?
    let schemaVersion: Int?
    let pdfFileURL: URL?
    let revision: String?
}

nonisolated enum CloudKitPDFAssetConditionalSaveResult: Equatable, Sendable {
    case saved(CloudKitPDFAssetRecord)
    case recordAlreadyExists
}

nonisolated protocol CloudKitPDFAssetTransport: Sendable {
    func accountAvailability() async throws -> CloudAccountAvailability
    func ensureZone(named zoneName: String) async throws
    func fetchRecord(
        named recordName: String,
        recordType: String,
        zoneName: String
    ) async throws -> CloudKitPDFAssetRecord?
    func saveIfAbsent(
        _ record: CloudKitPDFAssetRecord
    ) async throws -> CloudKitPDFAssetConditionalSaveResult
}

nonisolated struct CloudKitPDFAssetStore: PDFAssetRemote, Sendable {
    static let zoneName = "WorshipArchivePDFAssets.v1"
    static let recordType = "WAPDFAsset"
    static let schemaVersion = 1

    static let checksumField = "checksum"
    static let fileSizeField = "fileSize"
    static let pageCountField = "pageCount"
    static let schemaVersionField = "schemaVersion"
    static let pdfField = "pdf"

    private let transport: any CloudKitPDFAssetTransport
    private let temporaryDirectory: URL

    init(
        transport: any CloudKitPDFAssetTransport,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.transport = transport
        self.temporaryDirectory = temporaryDirectory
    }

    static func live(
        containerIdentifier: String = "iCloud.com.jacky.WorshipArchive"
    ) -> CloudKitPDFAssetStore {
        CloudKitPDFAssetStore(
            transport: LiveCloudKitPDFAssetTransport(
                containerIdentifier: containerIdentifier
            )
        )
    }

    func accountAvailability() async -> CloudAccountAvailability {
        do {
            return try await transport.accountAvailability()
        } catch {
            switch Self.mapCloudKitError(error) {
            case let .accountUnavailable(availability):
                return availability
            case .offline, .rateLimited, .transient:
                return .temporarilyUnavailable
            default:
                return .couldNotDetermine
            }
        }
    }

    func upload(
        _ asset: LocalPDFAsset,
        fileURL: URL
    ) async throws -> PDFAssetUploadResult {
        try validateLocalFile(at: fileURL, against: asset)

        do {
            try await transport.ensureZone(named: Self.zoneName)

            if let existing = try await transport.fetchRecord(
                named: asset.checksum,
                recordType: Self.recordType,
                zoneName: Self.zoneName
            ) {
                return .alreadyPresent(
                    try validatedMetadata(in: existing, matching: asset)
                )
            }

            let candidate = CloudKitPDFAssetRecord(
                recordType: Self.recordType,
                recordName: asset.checksum,
                zoneName: Self.zoneName,
                checksum: asset.checksum,
                fileSize: asset.fileSize,
                pageCount: asset.pageCount,
                schemaVersion: Self.schemaVersion,
                pdfFileURL: fileURL,
                revision: nil
            )

            switch try await transport.saveIfAbsent(candidate) {
            case let .saved(savedRecord):
                return .uploaded(
                    try validatedMetadata(in: savedRecord, matching: asset)
                )

            case .recordAlreadyExists:
                guard let existing = try await transport.fetchRecord(
                    named: asset.checksum,
                    recordType: Self.recordType,
                    zoneName: Self.zoneName
                ) else {
                    throw PDFAssetRemoteError.transient
                }
                return .alreadyPresent(
                    try validatedMetadata(in: existing, matching: asset)
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PDFAssetRemoteError {
            throw error
        } catch {
            throw Self.mapCloudKitError(error)
        }
    }

    func download(checksum: String) async throws -> DownloadedPDFAsset {
        do {
            try await transport.ensureZone(named: Self.zoneName)
            guard let record = try await transport.fetchRecord(
                named: checksum,
                recordType: Self.recordType,
                zoneName: Self.zoneName
            ) else {
                throw PDFAssetRemoteError.notFound
            }

            let metadata = try validatedMetadata(in: record)
            guard metadata.checksum == checksum else {
                throw PDFAssetRemoteError.integrityConflict
            }
            guard let cloudKitTemporaryURL = record.pdfFileURL else {
                throw PDFAssetRemoteError.malformedRecord
            }

            let ownedTemporaryURL = try copyDownloadedAsset(
                from: cloudKitTemporaryURL,
                expectedChecksum: metadata.checksum,
                expectedFileSize: metadata.fileSize
            )
            return DownloadedPDFAsset(
                metadata: metadata,
                temporaryFileURL: ownedTemporaryURL
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PDFAssetRemoteError {
            throw error
        } catch {
            throw Self.mapCloudKitError(error)
        }
    }

    static func mapCloudKitError(_ error: Error) -> PDFAssetRemoteError {
        if let remoteError = error as? PDFAssetRemoteError {
            return remoteError
        }

        let nsError = error as NSError
        guard nsError.domain == CKErrorDomain,
              let code = CKError.Code(rawValue: nsError.code) else {
            return .transient
        }

        if code == .partialFailure,
           let partialError = firstMeaningfulPartialError(in: nsError) {
            return mapCloudKitError(partialError)
        }

        switch code {
        case .networkUnavailable, .networkFailure, .serverResponseLost:
            return .offline

        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            let retryAfter = (nsError.userInfo[CKErrorRetryAfterKey] as? NSNumber)?
                .doubleValue
            return .rateLimited(retryAfter: retryAfter)

        case .quotaExceeded:
            return .quotaExceeded

        case .unknownItem, .zoneNotFound, .userDeletedZone:
            return .notFound

        case .notAuthenticated:
            return .accountUnavailable(.noAccount)

        case .managedAccountRestricted, .permissionFailure:
            return .accountUnavailable(.restricted)

        case .accountTemporarilyUnavailable:
            return .accountUnavailable(.temporarilyUnavailable)

        case .serverRecordChanged, .constraintViolation, .assetFileModified:
            return .integrityConflict

        case .assetFileNotFound, .assetNotAvailable,
             .invalidArguments, .incompatibleVersion:
            return .malformedRecord

        default:
            return .transient
        }
    }

    private func validatedMetadata(
        in record: CloudKitPDFAssetRecord,
        matching localAsset: LocalPDFAsset? = nil
    ) throws -> RemotePDFAsset {
        guard record.recordType == Self.recordType,
              record.zoneName == Self.zoneName,
              !record.recordName.isEmpty,
              let checksum = record.checksum,
              !checksum.isEmpty,
              let fileSize = record.fileSize,
              fileSize >= 0,
              let pageCount = record.pageCount,
              pageCount > 0,
              record.schemaVersion == Self.schemaVersion,
              record.pdfFileURL != nil else {
            throw PDFAssetRemoteError.malformedRecord
        }

        guard checksum == record.recordName else {
            throw PDFAssetRemoteError.integrityConflict
        }

        if let localAsset {
            guard checksum == localAsset.checksum,
                  fileSize == localAsset.fileSize,
                  pageCount == localAsset.pageCount else {
                throw PDFAssetRemoteError.integrityConflict
            }
        }

        return RemotePDFAsset(
            checksum: checksum,
            fileSize: fileSize,
            pageCount: pageCount,
            revision: record.revision
        )
    }

    private func validateLocalFile(
        at fileURL: URL,
        against asset: LocalPDFAsset
    ) throws {
        do {
            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
            guard values.isRegularFile == true,
                  Int64(values.fileSize ?? -1) == asset.fileSize,
                  asset.pageCount > 0,
                  try sha256(of: fileURL) == asset.checksum else {
                throw PDFAssetRemoteError.integrityConflict
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PDFAssetRemoteError {
            throw error
        } catch {
            throw PDFAssetRemoteError.integrityConflict
        }
    }

    private func copyDownloadedAsset(
        from sourceURL: URL,
        expectedChecksum: String,
        expectedFileSize: Int64
    ) throws -> URL {
        let fileManager = FileManager.default
        let downloadsDirectory = temporaryDirectory.appending(
            path: "WorshipArchiveCloudKitDownloads",
            directoryHint: .isDirectory
        )
        let destinationURL = downloadsDirectory.appending(
            path: "\(UUID().uuidString.lowercased()).pdf"
        )

        do {
            let sourceValues = try sourceURL.resourceValues(
                forKeys: [.isRegularFileKey]
            )
            guard sourceValues.isRegularFile == true else {
                throw PDFAssetRemoteError.malformedRecord
            }

            try fileManager.createDirectory(
                at: downloadsDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            let copiedValues = try destinationURL.resourceValues(
                forKeys: [.fileSizeKey]
            )
            guard Int64(copiedValues.fileSize ?? -1) == expectedFileSize,
                  try sha256(of: destinationURL) == expectedChecksum else {
                throw PDFAssetRemoteError.integrityConflict
            }
            return destinationURL
        } catch is CancellationError {
            try? fileManager.removeItem(at: destinationURL)
            throw CancellationError()
        } catch let error as PDFAssetRemoteError {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw PDFAssetRemoteError.transient
        }
    }

    private func sha256(of fileURL: URL) throws -> String {
        try Task.checkCancellation()
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        while let data = try fileHandle.read(upToCount: 1_048_576),
              !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        try Task.checkCancellation()
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func firstMeaningfulPartialError(
        in error: NSError
    ) -> Error? {
        guard let partialErrors = error.userInfo[CKPartialErrorsByItemIDKey]
                as? [AnyHashable: Error] else {
            return nil
        }
        return partialErrors.values.first { partialError in
            let nsError = partialError as NSError
            return nsError.domain != CKErrorDomain
                || nsError.code != CKError.Code.batchRequestFailed.rawValue
        } ?? partialErrors.values.first
    }
}

actor LiveCloudKitPDFAssetTransport: CloudKitPDFAssetTransport {
    private let container: CKContainer
    private let database: CKDatabase
    private var ensuredZoneNames: Set<String> = []

    init(containerIdentifier: String) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func accountAvailability() async throws -> CloudAccountAvailability {
        switch try await container.accountStatus() {
        case .available:
            return .available
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        case .couldNotDetermine:
            return .couldNotDetermine
        @unknown default:
            return .couldNotDetermine
        }
    }

    func ensureZone(named zoneName: String) async throws {
        guard !ensuredZoneNames.contains(zoneName) else { return }
        let zoneID = CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        ensuredZoneNames.insert(zoneName)
    }

    func fetchRecord(
        named recordName: String,
        recordType: String,
        zoneName: String
    ) async throws -> CloudKitPDFAssetRecord? {
        let recordID = CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(
                zoneName: zoneName,
                ownerName: CKCurrentUserDefaultName
            )
        )

        do {
            let record = try await database.record(for: recordID)
            guard record.recordType == recordType else { return nil }
            return snapshot(from: record)
        } catch {
            let nsError = error as NSError
            if nsError.domain == CKErrorDomain,
               nsError.code == CKError.Code.unknownItem.rawValue {
                return nil
            }
            throw error
        }
    }

    func saveIfAbsent(
        _ record: CloudKitPDFAssetRecord
    ) async throws -> CloudKitPDFAssetConditionalSaveResult {
        let recordID = CKRecord.ID(
            recordName: record.recordName,
            zoneID: CKRecordZone.ID(
                zoneName: record.zoneName,
                ownerName: CKCurrentUserDefaultName
            )
        )
        let cloudRecord = CKRecord(
            recordType: record.recordType,
            recordID: recordID
        )
        cloudRecord[CloudKitPDFAssetStore.checksumField] = record.checksum
            as CKRecordValue?
        if let fileSize = record.fileSize {
            cloudRecord[CloudKitPDFAssetStore.fileSizeField] = NSNumber(
                value: fileSize
            )
        }
        if let pageCount = record.pageCount {
            cloudRecord[CloudKitPDFAssetStore.pageCountField] = NSNumber(
                value: pageCount
            )
        }
        if let schemaVersion = record.schemaVersion {
            cloudRecord[CloudKitPDFAssetStore.schemaVersionField] = NSNumber(
                value: schemaVersion
            )
        }
        if let fileURL = record.pdfFileURL {
            cloudRecord[CloudKitPDFAssetStore.pdfField] = CKAsset(fileURL: fileURL)
        }

        do {
            let result = try await database.modifyRecords(
                saving: [cloudRecord],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            guard let saveResult = result.saveResults[recordID] else {
                throw PDFAssetRemoteError.transient
            }
            switch saveResult {
            case let .success(savedRecord):
                return .saved(snapshot(from: savedRecord))
            case let .failure(error):
                if Self.isConditionalCreateConflict(error) {
                    return .recordAlreadyExists
                }
                throw error
            }
        } catch {
            if Self.isConditionalCreateConflict(error) {
                return .recordAlreadyExists
            }
            throw error
        }
    }

    private func snapshot(from record: CKRecord) -> CloudKitPDFAssetRecord {
        let fileSize = (record[CloudKitPDFAssetStore.fileSizeField]
            as? NSNumber)?.int64Value
        let pageCountNumber = record[CloudKitPDFAssetStore.pageCountField]
            as? NSNumber
        let schemaVersionNumber = record[CloudKitPDFAssetStore.schemaVersionField]
            as? NSNumber
        let asset = record[CloudKitPDFAssetStore.pdfField] as? CKAsset

        return CloudKitPDFAssetRecord(
            recordType: record.recordType,
            recordName: record.recordID.recordName,
            zoneName: record.recordID.zoneID.zoneName,
            checksum: record[CloudKitPDFAssetStore.checksumField] as? String,
            fileSize: fileSize,
            pageCount: pageCountNumber.map { Int(truncating: $0) },
            schemaVersion: schemaVersionNumber.map { Int(truncating: $0) },
            pdfFileURL: asset?.fileURL,
            revision: record.recordChangeTag
        )
    }

    private static func isConditionalCreateConflict(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == CKErrorDomain else { return false }
        if nsError.code == CKError.Code.serverRecordChanged.rawValue {
            return true
        }
        guard nsError.code == CKError.Code.partialFailure.rawValue,
              let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey]
                as? [AnyHashable: Error] else {
            return false
        }
        return partialErrors.values.contains(where: isConditionalCreateConflict)
    }
}
