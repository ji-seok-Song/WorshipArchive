import Foundation
import UIKit

enum PDFTestFixture {
    static func make(
        pages: [String?],
        emphasizedTitlePageIndexes: Set<Int>? = nil
    ) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString.lowercased())
            .appendingPathExtension("pdf")
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        try renderer.writePDF(to: fileURL) { context in
            for (pageIndex, text) in pages.enumerated() {
                context.beginPage()
                guard let text else { continue }

                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                for (index, line) in lines.enumerated() {
                    let emphasizesFirstLine = emphasizedTitlePageIndexes?
                        .contains(pageIndex) ?? true
                    let font = index == 0 && emphasizesFirstLine
                        ? UIFont.boldSystemFont(ofSize: 28)
                        : UIFont.systemFont(ofSize: 18)
                    (String(line) as NSString).draw(
                        at: CGPoint(x: 72, y: 72 + CGFloat(index) * 40),
                        withAttributes: [
                            .font: font,
                            .foregroundColor: UIColor.black
                        ]
                    )
                }
            }
        }

        return fileURL
    }

    static func remove(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
