import Foundation
import SwiftData

@Model
final class ArchiveDocument {
    var id: UUID = UUID()
    var originalFileName: String = ""
    var storedFileName: String = ""
    var importedAt: Date = Date()
    var pageCount: Int = 0
    var fileSize: Int64 = 0
    var checksum: String = ""
    var analysisStatusRawValue: String = DocumentAnalysisStatus.pending.rawValue
    var analysisErrorMessage: String?

    @Relationship(deleteRule: .cascade, inverse: \PageAnalysis.document)
    var pageAnalyses: [PageAnalysis]?

    @Relationship(deleteRule: .cascade, inverse: \SongSheet.document)
    var sheets: [SongSheet]?

    init(
        id: UUID = UUID(),
        originalFileName: String,
        storedFileName: String,
        importedAt: Date = Date(),
        pageCount: Int,
        fileSize: Int64,
        checksum: String,
        analysisStatus: DocumentAnalysisStatus = .pending
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.importedAt = importedAt
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.checksum = checksum
        analysisStatusRawValue = analysisStatus.rawValue
    }

    var analysisStatus: DocumentAnalysisStatus {
        get { DocumentAnalysisStatus(rawValue: analysisStatusRawValue) ?? .pending }
        set { analysisStatusRawValue = newValue.rawValue }
    }
}
