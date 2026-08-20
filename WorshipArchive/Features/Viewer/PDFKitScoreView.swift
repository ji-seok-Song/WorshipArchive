import PDFKit
import SwiftUI

struct PDFKitScoreView: UIViewRepresentable {
    let document: PDFDocument
    let pageSession: PDFViewerPageSession
    let currentPageIndex: Int
    let onPageChanged: @MainActor (Int) -> Void

    init(
        document: PDFDocument,
        pageSession: PDFViewerPageSession,
        currentPageIndex: Int? = nil,
        onPageChanged: @escaping @MainActor (Int) -> Void
    ) {
        self.document = document
        self.pageSession = pageSession
        self.currentPageIndex = pageSession.clamped(
            currentPageIndex ?? pageSession.initialPageIndex
        )
        self.onPageChanged = onPageChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        context.coordinator.configure(pdfView)
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

        func configure(_ pdfView: PDFView) {
            pdfView.autoScales = true
            pdfView.displayMode = .singlePage
            pdfView.displayDirection = .horizontal
            pdfView.displaysPageBreaks = false
            pdfView.backgroundColor = .systemBackground
            pdfView.accessibilityLabel = "악보 PDF"
            pdfView.usePageViewController(
                true,
                withViewOptions: [
                    UIPageViewController.OptionsKey.interPageSpacing: 12
                ]
            )
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
                guard applicationState.shouldForwardPageChange else { return }
                guard pendingObservationToken == nil else { return }

                attach(to: pdfView)
                if currentPageIndex(in: pdfView) != parent.currentPageIndex {
                    navigate(
                        to: parent.currentPageIndex,
                        in: pdfView,
                        identity: identity
                    )
                }
                return
            }

            suspendObservation()

            if pdfView.document !== parent.document {
                pdfView.document = parent.document
            }
            pdfView.autoScales = true

            go(to: parent.currentPageIndex, in: pdfView)

            resumeObservationOnNextMainTurn(
                for: pdfView,
                identity: identity,
                completesApplication: true
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
            let clampedPageIndex = parent.pageSession.clamped(pageIndex)

            if pageIndex != clampedPageIndex {
                let identity = PDFKitScoreApplicationIdentity(
                    document: parent.document,
                    pageSession: parent.pageSession
                )
                navigate(
                    to: clampedPageIndex,
                    in: pdfView,
                    identity: identity
                )
            }

            parent.onPageChanged(clampedPageIndex)
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
            identity: PDFKitScoreApplicationIdentity,
            completesApplication: Bool
        ) {
            let token = UUID()
            pendingObservationToken = token

            DispatchQueue.main.async { [weak self, weak pdfView] in
                guard
                    let self,
                    let pdfView,
                    self.pendingObservationToken == token,
                    self.applicationState.appliedIdentity == identity
                else {
                    return
                }

                if completesApplication {
                    guard self.applicationState.finishApplying(identity) else {
                        return
                    }
                } else {
                    guard self.applicationState.shouldForwardPageChange else {
                        return
                    }
                }

                self.go(to: self.parent.currentPageIndex, in: pdfView)
                self.pendingObservationToken = nil
                self.attach(to: pdfView)
            }
        }

        private func navigate(
            to pageIndex: Int,
            in pdfView: PDFView,
            identity: PDFKitScoreApplicationIdentity
        ) {
            suspendObservation()
            go(to: pageIndex, in: pdfView)
            resumeObservationOnNextMainTurn(
                for: pdfView,
                identity: identity,
                completesApplication: false
            )
        }

        private func go(to pageIndex: Int, in pdfView: PDFView) {
            let clampedPageIndex = parent.pageSession.clamped(pageIndex)
            guard let page = parent.document.page(at: clampedPageIndex) else {
                return
            }
            guard currentPageIndex(in: pdfView) != clampedPageIndex else {
                return
            }
            pdfView.go(to: page)
        }

        private func currentPageIndex(in pdfView: PDFView) -> Int? {
            guard
                let document = pdfView.document,
                let currentPage = pdfView.currentPage
            else {
                return nil
            }
            return document.index(for: currentPage)
        }
    }
}

struct PDFKitTwoPageScoreView: UIViewRepresentable {
    let document: PDFDocument
    let pageSession: PDFViewerPageSession
    let currentPageIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFKitTwoPageContainerView {
        let containerView = PDFKitTwoPageContainerView()
        context.coordinator.update(parent: self, containerView: containerView)
        return containerView
    }

    func updateUIView(
        _ containerView: PDFKitTwoPageContainerView,
        context: Context
    ) {
        context.coordinator.update(parent: self, containerView: containerView)
    }

    @MainActor
    final class Coordinator {
        private var appliedIdentity: PDFKitTwoPageApplicationIdentity?

        func update(
            parent: PDFKitTwoPageScoreView,
            containerView: PDFKitTwoPageContainerView
        ) {
            let visiblePageIndices = parent.pageSession.visiblePageIndices(
                containing: parent.currentPageIndex,
                pageSpan: 2
            )
            let identity = PDFKitTwoPageApplicationIdentity(
                document: parent.document,
                visiblePageIndices: visiblePageIndices
            )
            guard identity != appliedIdentity else { return }
            appliedIdentity = identity

            apply(
                document: parent.document,
                pageIndex: visiblePageIndices[0],
                to: containerView.primaryPDFView
            )

            if visiblePageIndices.count == 2 {
                containerView.secondaryPDFView.isHidden = false
                apply(
                    document: parent.document,
                    pageIndex: visiblePageIndices[1],
                    to: containerView.secondaryPDFView
                )
            } else {
                containerView.secondaryPDFView.isHidden = true
                containerView.secondaryPDFView.document = nil
            }
        }

        private func apply(
            document: PDFDocument,
            pageIndex: Int,
            to pdfView: PDFView
        ) {
            if pdfView.document !== document {
                pdfView.document = document
            }
            guard let page = document.page(at: pageIndex) else { return }
            if pdfView.currentPage !== page {
                pdfView.go(to: page)
            }
            pdfView.autoScales = true
        }
    }
}

final class PDFKitTwoPageContainerView: UIStackView {
    let primaryPDFView = PDFKitTwoPageContainerView.makePageView(
        accessibilityLabel: "왼쪽 악보 페이지"
    )
    let secondaryPDFView = PDFKitTwoPageContainerView.makePageView(
        accessibilityLabel: "오른쪽 악보 페이지"
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .horizontal
        distribution = .fillEqually
        spacing = 1
        backgroundColor = .separator
        addArrangedSubview(primaryPDFView)
        addArrangedSubview(secondaryPDFView)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makePageView(accessibilityLabel: String) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.displaysPageBreaks = false
        pdfView.backgroundColor = .systemBackground
        pdfView.accessibilityLabel = accessibilityLabel
        return pdfView
    }
}

struct PDFKitTwoPageApplicationIdentity: Equatable {
    let documentIdentifier: ObjectIdentifier
    let visiblePageIndices: [Int]

    init(document: PDFDocument, visiblePageIndices: [Int]) {
        documentIdentifier = ObjectIdentifier(document)
        self.visiblePageIndices = visiblePageIndices
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
