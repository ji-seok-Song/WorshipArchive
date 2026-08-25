import PDFKit
import SwiftUI

struct PDFPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL
    let initialPageIndex: Int?

    init(url: URL, initialPageIndex: Int? = nil) {
        self.url = url
        self.initialPageIndex = initialPageIndex
    }

    var body: some View {
        NavigationStack {
            PDFKitDocumentView(
                url: url,
                initialPageIndex: initialPageIndex
            )
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("원본 PDF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("완료") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct PDFKitDocumentView: UIViewRepresentable {
    let url: URL
    let initialPageIndex: Int?

    final class Coordinator {
        var displayedInitialPageIndex: Int?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
            context.coordinator.displayedInitialPageIndex = nil
        }

        guard
            let initialPageIndex,
            let document = pdfView.document,
            document.pageCount > 0
        else {
            return
        }

        let clampedIndex = min(max(initialPageIndex, 0), document.pageCount - 1)
        guard context.coordinator.displayedInitialPageIndex != clampedIndex else {
            return
        }
        guard let page = document.page(at: clampedIndex) else { return }

        pdfView.go(to: page)
        context.coordinator.displayedInitialPageIndex = clampedIndex
    }
}
