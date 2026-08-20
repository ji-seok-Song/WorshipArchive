import PDFKit
import SwiftUI

struct PDFKitScoreView: UIViewRepresentable {
    let document: PDFDocument
    let pageSession: PDFViewerPageSession
    let onPageChanged: @MainActor (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .systemBackground
        pdfView.accessibilityLabel = "악보 PDF"

        context.coordinator.update(parent: self, pdfView: pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.update(parent: self, pdfView: pdfView)
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: Coordinator) {
        coordinator.detach(from: pdfView)
    }

    @MainActor
    final class Coordinator: NSObject {
        private var parent: PDFKitScoreView
        private weak var observedPDFView: PDFView?
        private var applicationState = PDFKitScoreApplicationState()
        private var pendingObservationToken: UUID?

        init(parent: PDFKitScoreView) {
            self.parent = parent
        }

        func attach(to pdfView: PDFView) {
            guard observedPDFView !== pdfView else { return }
            if let observedPDFView {
                detach(from: observedPDFView)
            }

            observedPDFView = pdfView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageDidChange(_:)),
                name: Notification.Name.PDFViewPageChanged,
                object: pdfView
            )
        }

        func detach(from pdfView: PDFView) {
            pendingObservationToken = nil
            NotificationCenter.default.removeObserver(
                self,
                name: Notification.Name.PDFViewPageChanged,
                object: pdfView
            )
            if observedPDFView === pdfView {
                observedPDFView = nil
            }
        }

        func update(parent: PDFKitScoreView, pdfView: PDFView) {
            self.parent = parent

            let identity = PDFKitScoreApplicationIdentity(
                document: parent.document,
                pageSession: parent.pageSession
            )
            guard applicationState.beginApplying(identity) else {
                if applicationState.shouldForwardPageChange {
                    attach(to: pdfView)
                }
                return
            }

            suspendObservation()

            if pdfView.document !== parent.document {
                pdfView.document = parent.document
            }
            pdfView.autoScales = true

            if let initialPage = parent.document.page(
                at: parent.pageSession.initialPageIndex
            ) {
                pdfView.go(to: initialPage)
            }

            resumeObservationOnNextMainTurn(
                for: pdfView,
                identity: identity
            )
        }

        @objc
        private func pageDidChange(_ notification: Notification) {
            guard applicationState.shouldForwardPageChange else { return }
            guard
                let pdfView = notification.object as? PDFView,
                pdfView === observedPDFView,
                let document = pdfView.document,
                let currentPage = pdfView.currentPage
            else {
                return
            }

            let pageIndex = document.index(for: currentPage)
            guard (0..<document.pageCount).contains(pageIndex) else { return }
            parent.onPageChanged(parent.pageSession.clamped(pageIndex))
        }

        private func suspendObservation() {
            pendingObservationToken = nil
            guard let observedPDFView else { return }

            NotificationCenter.default.removeObserver(
                self,
                name: Notification.Name.PDFViewPageChanged,
                object: observedPDFView
            )
            self.observedPDFView = nil
        }

        private func resumeObservationOnNextMainTurn(
            for pdfView: PDFView,
            identity: PDFKitScoreApplicationIdentity
        ) {
            let token = UUID()
            pendingObservationToken = token

            DispatchQueue.main.async { [weak self, weak pdfView] in
                guard
                    let self,
                    let pdfView,
                    self.pendingObservationToken == token,
                    self.applicationState.finishApplying(identity)
                else {
                    return
                }

                self.pendingObservationToken = nil
                self.attach(to: pdfView)
            }
        }
    }
}

struct PDFKitScoreApplicationIdentity: Equatable {
    let documentIdentifier: ObjectIdentifier
    let pageSession: PDFViewerPageSession

    init(document: PDFDocument, pageSession: PDFViewerPageSession) {
        documentIdentifier = ObjectIdentifier(document)
        self.pageSession = pageSession
    }
}

struct PDFKitScoreApplicationState {
    private(set) var appliedIdentity: PDFKitScoreApplicationIdentity?
    private(set) var isApplying = false

    var shouldForwardPageChange: Bool {
        !isApplying
    }

    mutating func beginApplying(
        _ identity: PDFKitScoreApplicationIdentity
    ) -> Bool {
        guard appliedIdentity != identity else { return false }

        appliedIdentity = identity
        isApplying = true
        return true
    }

    mutating func finishApplying(
        _ identity: PDFKitScoreApplicationIdentity
    ) -> Bool {
        guard appliedIdentity == identity, isApplying else { return false }
        isApplying = false
        return true
    }
}
