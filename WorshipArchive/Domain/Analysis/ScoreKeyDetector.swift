import CoreGraphics
import Foundation

nonisolated enum KeySignature: Hashable, Sendable {
    case none
    case sharps(Int)
    case flats(Int)
}

nonisolated struct DetectedKeySignature: Equatable, Sendable {
    let signature: KeySignature
    let confidence: Double
}

nonisolated struct ScoreKeySignatureDetector: Sendable {
    fileprivate struct StaffCandidate {
        let topLineY: Int
        let spacing: Int
        let score: Double
    }

    private struct StaffDetection {
        let signature: KeySignature
        let strength: Double
    }

    private struct AccidentalMatch {
        let isSharp: Bool
        let count: Int
        let firstScore: Double
        let firstX: Double
    }

    private let sharpOffsets = [0.0, 1.5, -0.5, 1.0, 2.5, 0.5]
    private let flatOffsets = [2.0, 0.5, 2.5, 1.0, 3.0, 1.5]

    func detect(in image: CGImage) -> DetectedKeySignature? {
        guard let raster = GrayscaleRaster(image: image, maximumWidth: 1_200) else {
            return nil
        }

        let detections = staffCandidates(in: raster)
            .prefix(6)
            .compactMap { detectSignature(on: $0, in: raster) }
        guard let first = detections.first else { return nil }

        // Key signatures repeat at the start of score systems. Requiring the
        // first result to agree with another nearby system prevents a time
        // signature or the first note from being mistaken for an accidental.
        let corroborating = detections.dropFirst().prefix(2).filter {
            $0.signature == first.signature
        }
        guard corroborating.count == 2 else { return nil }

        let evidence = [first] + corroborating
        let averageStrength = evidence.map(\.strength).reduce(0, +)
            / Double(evidence.count)
        let confidence = min(
            0.96,
            0.78 + Double(evidence.count - 1) * 0.07 + averageStrength * 0.08
        )
        return DetectedKeySignature(
            signature: first.signature,
            confidence: confidence
        )
    }

    private func staffCandidates(in raster: GrayscaleRaster) -> [StaffCandidate] {
        let xStart = Int(Double(raster.width) * 0.03)
        let xEnd = Int(Double(raster.width) * 0.97)
        let yEnd = Int(Double(raster.height) * 0.78)
        guard xEnd > xStart, yEnd > 40 else { return [] }

        var rowInk = Array(repeating: 0, count: yEnd)
        for y in 0..<yEnd {
            var count = 0
            for x in xStart..<xEnd where raster.isInk(x: x, y: y) {
                count += 1
            }
            rowInk[y] = count
        }
        let smoothed = rowInk.indices.map { y in
            rowInk[max(0, y - 1)...min(rowInk.count - 1, y + 1)].max() ?? 0
        }

        let usableWidth = Double(xEnd - xStart)
        let minimumSpacing = max(5, Int((Double(raster.width) * 0.0055).rounded()))
        let maximumSpacing = min(25, Int((Double(raster.width) * 0.018).rounded()))
        guard minimumSpacing <= maximumSpacing else { return [] }

        var candidates: [StaffCandidate] = []
        for spacing in minimumSpacing...maximumSpacing {
            let lastStart = yEnd - spacing * 4 - 5
            guard lastStart > 20 else { continue }

            for y in 20...lastStart {
                let lineValues = (0..<5).map { smoothed[y + $0 * spacing] }
                let minimumDensity = Double(lineValues.min() ?? 0) / usableWidth
                let averageDensity = Double(lineValues.reduce(0, +))
                    / Double(lineValues.count) / usableWidth
                guard minimumDensity >= 0.38, averageDensity >= 0.45 else {
                    continue
                }
                candidates.append(StaffCandidate(
                    topLineY: y,
                    spacing: spacing,
                    score: averageDensity + minimumDensity * 0.5
                ))
            }
        }

        var selected: [StaffCandidate] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            let overlaps = selected.contains { existing in
                abs(candidate.topLineY - existing.topLineY)
                    < max(candidate.spacing, existing.spacing) * 4
            }
            if !overlaps {
                selected.append(candidate)
            }
        }
        return selected.sorted { $0.topLineY < $1.topLineY }
    }

    private func detectSignature(
        on staff: StaffCandidate,
        in raster: GrayscaleRaster
    ) -> StaffDetection? {
        let spacing = staff.spacing
        let clefWidth = spacing * 3
        let maximumClefX = Int(Double(raster.width) * 0.35) - clefWidth
        guard maximumClefX > 0 else { return nil }

        var bestClefScore = 0.0
        var bestClefX = 0
        let upperStartY = max(0, staff.topLineY - spacing * 2)
        let lowerStartY = min(raster.height, staff.topLineY + spacing * 4)
        let bandEndY = min(raster.height, staff.topLineY + spacing * 6)
        for x in 0..<maximumClefX {
            let upperInk = raster.inkCount(
                xRange: x..<(x + clefWidth),
                yRange: upperStartY..<staff.topLineY
            )
            let lowerInk = raster.inkCount(
                xRange: x..<(x + clefWidth),
                yRange: lowerStartY..<bandEndY
            )
            let totalInk = raster.inkCount(
                xRange: x..<(x + clefWidth),
                yRange: upperStartY..<bandEndY
            )
            let score = (
                Double(min(upperInk, lowerInk)) * 2 + Double(totalInk) * 0.2
            ) / Double(spacing * spacing)
            if score > bestClefScore {
                bestClefScore = score
                bestClefX = x
            }
        }
        guard bestClefScore >= 1 else { return nil }

        let clefEnd = bestClefX + clefWidth
        let band = StaffInkBand(
            raster: raster,
            staff: staff,
            maximumX: min(raster.width, clefEnd + spacing * 12)
        )
        let sharp = accidentalMatch(
            offsets: sharpOffsets,
            isSharp: true,
            clefEnd: clefEnd,
            spacing: spacing,
            band: band
        )
        let flat = accidentalMatch(
            offsets: flatOffsets,
            isSharp: false,
            clefEnd: clefEnd,
            spacing: spacing,
            band: band
        )

        let chosen: AccidentalMatch
        switch (sharp, flat) {
        case (nil, nil):
            return StaffDetection(signature: .none, strength: 0.35)
        case (.some(let match), nil), (nil, .some(let match)):
            chosen = match
        case (.some(let sharp), .some(let flat)):
            let higher = sharp.firstScore >= flat.firstScore ? sharp : flat
            let lower = sharp.firstScore >= flat.firstScore ? flat : sharp
            let scoreRatio = lower.firstScore / max(higher.firstScore, 0.001)
            if scoreRatio >= 0.75,
               abs(sharp.firstX - flat.firstX) >= Double(spacing) * 0.45 {
                chosen = sharp.firstX < flat.firstX ? sharp : flat
            } else {
                chosen = higher
            }
        }

        let signature: KeySignature = chosen.isSharp
            ? .sharps(chosen.count)
            : .flats(chosen.count)
        return StaffDetection(signature: signature, strength: chosen.firstScore)
    }

    private func accidentalMatch(
        offsets: [Double],
        isSharp: Bool,
        clefEnd: Int,
        spacing: Int,
        band: StaffInkBand
    ) -> AccidentalMatch? {
        let spacingValue = Double(spacing)
        let firstStart = Double(clefEnd) + spacingValue * 0.2
        let firstEnd = Double(clefEnd) + spacingValue * 2.5
        let firstStep = max(spacingValue * 0.1, 0.5)
        let firstOptions = stride(
            from: firstStart,
            through: firstEnd,
            by: firstStep
        ).map { x in
            (score: band.symbolScore(centerX: x, staffOffset: offsets[0]), x: x)
        }
        guard let maximum = firstOptions.max(by: { $0.score < $1.score }) else {
            return nil
        }

        let first: (score: Double, x: Double)
        if isSharp {
            let threshold = max(0.15, maximum.score * 0.45)
            first = firstOptions.first(where: { $0.score >= threshold }) ?? maximum
        } else {
            first = maximum
        }
        guard first.score >= 0.15 else { return nil }

        let stepOptions = stride(
            from: spacingValue * 0.65,
            through: spacingValue * 1.16,
            by: max(spacingValue * 0.05, 0.25)
        )
        guard let second = stepOptions.map({ step in
            (
                score: band.symbolScore(
                    centerX: first.x + step,
                    staffOffset: offsets[1]
                ),
                step: step
            )
        }).max(by: { $0.score < $1.score }) else {
            return AccidentalMatch(
                isSharp: isSharp,
                count: 1,
                firstScore: first.score,
                firstX: first.x
            )
        }

        var acceptedScores = [first.score]
        var count = 1
        guard second.score >= max(0.15, first.score * 0.4) else {
            return AccidentalMatch(
                isSharp: isSharp,
                count: count,
                firstScore: first.score,
                firstX: first.x
            )
        }
        acceptedScores.append(second.score)
        count = 2

        for index in 2..<offsets.count {
            let score = band.symbolScore(
                centerX: first.x + Double(index) * second.step,
                staffOffset: offsets[index]
            )
            let sortedScores = acceptedScores.sorted()
            let median = sortedScores[sortedScores.count / 2]
            guard score >= max(0.15, median * 0.4) else { break }
            acceptedScores.append(score)
            count = index + 1
        }

        return AccidentalMatch(
            isSharp: isSharp,
            count: count,
            firstScore: first.score,
            firstX: first.x
        )
    }
}

private nonisolated struct GrayscaleRaster {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(image: CGImage, maximumWidth: Int) {
        guard image.width > 0, image.height > 0 else { return nil }
        let scale = min(1, Double(maximumWidth) / Double(image.width))
        let targetWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(image.height) * scale).rounded()))
        var storage = Array(repeating: UInt8.max, count: targetWidth * targetHeight)
        let didDraw = storage.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: targetWidth,
                      height: targetHeight,
                      bitsPerComponent: 8,
                      bytesPerRow: targetWidth,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else { return false }

            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            context.interpolationQuality = .high
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            )
            return true
        }
        guard didDraw else { return nil }
        width = targetWidth
        height = targetHeight
        pixels = storage
    }

    func isInk(x: Int, y: Int) -> Bool {
        guard (0..<width).contains(x), (0..<height).contains(y) else {
            return false
        }
        return pixels[y * width + x] < 205
    }

    func inkCount(xRange: Range<Int>, yRange: Range<Int>) -> Int {
        guard !xRange.isEmpty, !yRange.isEmpty else { return 0 }
        var count = 0
        for y in yRange where (0..<height).contains(y) {
            for x in xRange where (0..<width).contains(x) && isInk(x: x, y: y) {
                count += 1
            }
        }
        return count
    }
}

private nonisolated struct StaffInkBand {
    private let originY: Int
    private let width: Int
    private let height: Int
    private let integral: [Int]
    private let staffTopY: Int
    private let spacing: Int

    init(
        raster: GrayscaleRaster,
        staff: ScoreKeySignatureDetector.StaffCandidate,
        maximumX: Int
    ) {
        let bandOriginY = max(0, staff.topLineY - staff.spacing * 2)
        let bandWidth = max(1, maximumX)
        let bandHeight = max(
            1,
            min(raster.height, staff.topLineY + staff.spacing * 6) - bandOriginY
        )
        let rowStride = bandWidth + 1
        var values = Array(repeating: 0, count: rowStride * (bandHeight + 1))
        let removalRadius = max(
            1,
            Int((Double(staff.spacing) * 0.1).rounded())
        )

        for localY in 0..<bandHeight {
            let globalY = bandOriginY + localY
            let isStaffLine = (0..<5).contains(where: { lineIndex in
                abs(globalY - (staff.topLineY + lineIndex * staff.spacing))
                    <= removalRadius
            })
            var rowSum = 0
            for x in 0..<bandWidth {
                if !isStaffLine, raster.isInk(x: x, y: globalY) {
                    rowSum += 1
                }
                let index = (localY + 1) * rowStride + x + 1
                values[index] = values[localY * rowStride + x + 1] + rowSum
            }
        }
        originY = bandOriginY
        width = bandWidth
        height = bandHeight
        staffTopY = staff.topLineY
        spacing = staff.spacing
        integral = values
    }

    func symbolScore(centerX: Double, staffOffset: Double) -> Double {
        let halfWidth = Double(spacing) * 0.4
        let centerY = Double(staffTopY) + staffOffset * Double(spacing)
        let inside = CGRect(
            x: centerX - halfWidth,
            y: centerY - Double(spacing) * 1.2,
            width: halfWidth * 2,
            height: Double(spacing) * 2.4
        )
        let outer = CGRect(
            x: centerX - halfWidth,
            y: Double(staffTopY - spacing * 2),
            width: halfWidth * 2,
            height: Double(spacing * 8)
        )
        let insideInk = sum(in: inside)
        let outerInk = sum(in: outer) - insideInk
        let insideArea = max(Int(inside.width.rounded(.up)) * Int(inside.height.rounded(.up)), 1)
        let outerArea = max(
            Int(outer.width.rounded(.up)) * Int(outer.height.rounded(.up)) - insideArea,
            1
        )
        return Double(insideInk) / Double(insideArea)
            - Double(outerInk) / Double(outerArea) * 0.7
    }

    private func sum(in rect: CGRect) -> Int {
        let x0 = max(0, min(width, Int(rect.minX.rounded(.down))))
        let x1 = max(0, min(width, Int(rect.maxX.rounded(.up))))
        let y0 = max(0, min(height, Int(rect.minY.rounded(.down)) - originY))
        let y1 = max(0, min(height, Int(rect.maxY.rounded(.up)) - originY))
        guard x1 > x0, y1 > y0 else { return 0 }
        let stride = width + 1
        return integral[y1 * stride + x1]
            - integral[y0 * stride + x1]
            - integral[y1 * stride + x0]
            + integral[y0 * stride + x0]
    }
}

nonisolated enum KeySignatureKeyMap {
    static func musicalKey(for signature: KeySignature) -> MusicalKey? {
        switch signature {
        case .none:
            .cMajor
        case .sharps(let count):
            switch count {
            case 0: .cMajor
            case 1: .gMajor
            case 2: .dMajor
            case 3: .aMajor
            case 4: .eMajor
            case 5: .bMajor
            case 6: .fSharpMajor
            default: nil
            }
        case .flats(let count):
            switch count {
            case 0: .cMajor
            case 1: .fMajor
            case 2: .bFlatMajor
            case 3: .eFlatMajor
            case 4: .aFlatMajor
            case 5: .cSharpMajor
            case 6: .fSharpMajor
            default: nil
            }
        }
    }
}

nonisolated enum KeySignatureChoice: String, CaseIterable, Identifiable, Sendable {
    case unspecified
    case none
    case sharp1
    case sharp2
    case sharp3
    case sharp4
    case sharp5
    case sharp6
    case flat1
    case flat2
    case flat3
    case flat4
    case flat5
    case flat6

    var id: Self { self }

    var displayName: String {
        switch self {
        case .unspecified: "미지정"
        case .none: "조표 없음 · C"
        case .sharp1: "♯ 1개 · G"
        case .sharp2: "♯ 2개 · D"
        case .sharp3: "♯ 3개 · A"
        case .sharp4: "♯ 4개 · E"
        case .sharp5: "♯ 5개 · B"
        case .sharp6: "♯ 6개 · F♯"
        case .flat1: "♭ 1개 · F"
        case .flat2: "♭ 2개 · B♭"
        case .flat3: "♭ 3개 · E♭"
        case .flat4: "♭ 4개 · A♭"
        case .flat5: "♭ 5개 · D♭"
        case .flat6: "♭ 6개 · G♭"
        }
    }

    var musicalKey: MusicalKey? {
        guard let signature else { return nil }
        return KeySignatureKeyMap.musicalKey(for: signature)
    }

    init(signature: KeySignature?) {
        switch signature {
        case nil: self = .unspecified
        case .some(.none): self = .none
        case .some(.sharps(1)): self = .sharp1
        case .some(.sharps(2)): self = .sharp2
        case .some(.sharps(3)): self = .sharp3
        case .some(.sharps(4)): self = .sharp4
        case .some(.sharps(5)): self = .sharp5
        case .some(.sharps(6)): self = .sharp6
        case .some(.flats(1)): self = .flat1
        case .some(.flats(2)): self = .flat2
        case .some(.flats(3)): self = .flat3
        case .some(.flats(4)): self = .flat4
        case .some(.flats(5)): self = .flat5
        case .some(.flats(6)): self = .flat6
        default: self = .unspecified
        }
    }

    private var signature: KeySignature? {
        switch self {
        case .unspecified: nil
        case .none: KeySignature.none
        case .sharp1: .sharps(1)
        case .sharp2: .sharps(2)
        case .sharp3: .sharps(3)
        case .sharp4: .sharps(4)
        case .sharp5: .sharps(5)
        case .sharp6: .sharps(6)
        case .flat1: .flats(1)
        case .flat2: .flats(2)
        case .flat3: .flats(3)
        case .flat4: .flats(4)
        case .flat5: .flats(5)
        case .flat6: .flats(6)
        }
    }
}
