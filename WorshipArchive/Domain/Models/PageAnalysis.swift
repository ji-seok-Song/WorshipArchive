import Foundation
import SwiftData

@Model
final class PageAnalysis {
    var id: UUID = UUID()
    private(set) var pageIndex: Int = 0
    var extractedText: String = ""
    var confidence: Double = 0
    var statusRawValue: String = PageAnalysisStatus.pending.rawValue
    var recognitionMethodRawValue: String = TextRecognitionMethod.none.rawValue
    var errorMessage: String?
    var document: ArchiveDocument?

    private init(
        id: UUID = UUID(),
        pageIndex: Int,
        extractedText: String = "",
        confidence: Double = 0,
        status: PageAnalysisStatus = .pending,
        recognitionMethod: TextRecognitionMethod = .none,
        document: ArchiveDocument
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.extractedText = extractedText
        self.confidence = confidence
        statusRawValue = status.rawValue
        recognitionMethodRawValue = recognitionMethod.rawValue
        self.document = document
    }

    static func create(
        id: UUID = UUID(),
        pageIndex: Int,
        extractedText: String = "",
        confidence: Double = 0,
        status: PageAnalysisStatus = .pending,
        recognitionMethod: TextRecognitionMethod = .none,
        document: ArchiveDocument
    ) throws -> PageAnalysis {
        try PageIndexValidator.validate(
            pageIndex,
            documentPageCount: document.pageCount
        )

        return PageAnalysis(
            id: id,
            pageIndex: pageIndex,
            extractedText: extractedText,
            confidence: confidence,
            status: status,
            recognitionMethod: recognitionMethod,
            document: document
        )
    }

    var status: PageAnalysisStatus {
        get { PageAnalysisStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    var recognitionMethod: TextRecognitionMethod {
        get { TextRecognitionMethod(rawValue: recognitionMethodRawValue) ?? .none }
        set { recognitionMethodRawValue = newValue.rawValue }
    }
}
