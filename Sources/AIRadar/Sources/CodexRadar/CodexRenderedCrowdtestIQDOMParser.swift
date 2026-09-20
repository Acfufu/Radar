import Foundation

enum CodexRenderedCrowdtestIQDOMParserError: Error, Equatable, Sendable {
    case bridgePayloadTooLarge
    case invalidPayload
    case revisionMismatch
    case invalidFinalOrigin
    case blockedPage
    case contentPending
    case invalidHarnessCount
    case invalidHarness(harnessIndex: Int)
    case invalidCell(harnessIndex: Int, cellIndex: Int)
    case invalidTrend(harnessIndex: Int, circleIndex: Int)
    case duplicateHarness(harnessIndex: Int)
}

struct CodexRenderedCrowdtestIQDOMParser: Sendable {
    /// ADR-0004 dataset revision; the JS-side constant must stay identical.
    static let parserRevision = "deng-rendered-crowdtest-iq-v1"
    /// Per-reader bridge budget (lifecycle init parameter): the full board
    /// measured ~2.5KiB compressed DOM attributes on 2026-09-20; 4MiB gives
    /// the same 2× headroom discipline as the DTO caps below.
    static let maximumBridgePayloadBytes = 4 * 1_024 * 1_024
    static let maximumHarnessCards = 32
    static let maximumCellsPerHarness = 128
    static let maximumTrendPointsPerHarness = 512
    static let exactOrigin = "https://deng.codexradar.com"

    func parse(_ data: Data, capturedAt: Date) throws -> CodexRenderedCrowdtestIQSnapshot {
        guard data.count <= Self.maximumBridgePayloadBytes else {
            throw CodexRenderedCrowdtestIQDOMParserError.bridgePayloadTooLarge
        }

        let dto: ExtractionDTO
        do {
            dto = try JSONDecoder().decode(ExtractionDTO.self, from: data)
        } catch {
            throw CodexRenderedCrowdtestIQDOMParserError.invalidPayload
        }

        guard dto.revision == Self.parserRevision else {
            throw CodexRenderedCrowdtestIQDOMParserError.revisionMismatch
        }
        guard dto.finalOrigin == Self.exactOrigin else {
            throw CodexRenderedCrowdtestIQDOMParserError.invalidFinalOrigin
        }
        guard dto.pageState != .challenge, dto.pageState != .consent else {
            throw CodexRenderedCrowdtestIQDOMParserError.blockedPage
        }

        // The login wall renders as a ready page with zero cells — treat it
        // as pending so the stabilizer keeps polling instead of pinning an
        // empty snapshot.
        let totalCells = dto.harnesses.reduce(0) { $0 + $1.cells.count }
        guard totalCells > 0 else {
            throw CodexRenderedCrowdtestIQDOMParserError.contentPending
        }

        guard !dto.harnesses.isEmpty, dto.harnesses.count <= Self.maximumHarnessCards else {
            throw CodexRenderedCrowdtestIQDOMParserError.invalidHarnessCount
        }

        var harnesses = try dto.harnesses.enumerated().map { index, value in
            try validatedHarness(value, harnessIndex: index)
        }
        // ADR-0004 five-station mapping: unmapped families are not adopted;
        // they are dropped here so the snapshot only carries station data.
        harnesses = harnesses.filter { CodexRenderedCrowdtestIQSnapshot.mappedHarnesses.contains($0.harness) }
        guard !harnesses.isEmpty else {
            throw CodexRenderedCrowdtestIQDOMParserError.contentPending
        }

        let fingerprint: String
        do {
            fingerprint = try CodexRenderedCrowdtestIQSemanticFingerprint.make(
                harnesses: harnesses,
                finalOrigin: dto.finalOrigin,
                parserRevision: dto.revision
            )
        } catch {
            throw CodexRenderedCrowdtestIQDOMParserError.invalidPayload
        }

        return CodexRenderedCrowdtestIQSnapshot(
            sourceID: .codexRadar,
            parserRevision: dto.revision,
            finalOrigin: dto.finalOrigin,
            capturedAt: capturedAt,
            harnesses: harnesses,
            semanticFingerprint: fingerprint
        )
    }

    private func validatedHarness(
        _ value: ExtractionDTO.Harness,
        harnessIndex: Int
    ) throws -> CodexRenderedCrowdtestIQHarness {
        guard isSafeToken(value.harness), value.harness.count <= 32 else {
            throw CodexRenderedCrowdtestIQDOMParserError.invalidHarness(harnessIndex: harnessIndex)
        }
        guard value.cells.count <= Self.maximumCellsPerHarness else {
            throw CodexRenderedCrowdtestIQDOMParserError.invalidHarness(harnessIndex: harnessIndex)
        }

        let cells = try value.cells.enumerated().map { cellIndex, cell in
            try validatedCell(cell, harnessIndex: harnessIndex, cellIndex: cellIndex)
        }
        // Identity = harness family + model: one card per model upstream.
        let model = cells.first { $0.model.isEmpty == false }?.model

        let trend = try value.circles.enumerated().map { circleIndex, label -> CodexRenderedCrowdtestIQTrendPoint in
            guard label.count <= 64,
                  isBoundedDisplayText(label) else {
                throw CodexRenderedCrowdtestIQDOMParserError.invalidTrend(harnessIndex: harnessIndex, circleIndex: circleIndex)
            }
            return Self.parsedTrendLabel(label)
        }
        guard trend.count <= Self.maximumTrendPointsPerHarness else {
            throw CodexRenderedCrowdtestIQDOMParserError.invalidHarness(harnessIndex: harnessIndex)
        }

        return CodexRenderedCrowdtestIQHarness(
            harness: value.harness.lowercased(),
            model: model,
            cells: cells,
            trend: trend
        )
    }

    private func validatedCell(
        _ value: ExtractionDTO.Cell,
        harnessIndex: Int,
        cellIndex: Int
    ) throws -> CodexRenderedCrowdtestIQCell {
        guard isSafeToken(value.model), isSafeToken(value.effort) else {
            throw CodexRenderedCrowdtestIQDOMParserError.invalidCell(harnessIndex: harnessIndex, cellIndex: cellIndex)
        }
        if let methodTitle = value.methodTitle {
            guard methodTitle.isEmpty || isBoundedDisplayText(methodTitle) else {
                throw CodexRenderedCrowdtestIQDOMParserError.invalidCell(harnessIndex: harnessIndex, cellIndex: cellIndex)
            }
        }
        let iqScore = try validatedScore(value.iqScore, harnessIndex: harnessIndex, cellIndex: cellIndex)
        guard value.iqP.map({ $0 >= 0 }) ?? true,
              value.iqN.map({ $0 >= 0 }) ?? true,
              value.countP.map({ $0 >= 0 }) ?? true,
              value.countN.map({ $0 >= 0 }) ?? true,
              value.coveredTasks.map({ $0 >= 0 }) ?? true,
              value.totalTasks.map({ $0 >= 0 }) ?? true else {
            throw CodexRenderedCrowdtestIQDOMParserError.invalidCell(harnessIndex: harnessIndex, cellIndex: cellIndex)
        }
        return CodexRenderedCrowdtestIQCell(
            model: value.model.lowercased(),
            effort: value.effort.lowercased(),
            iqScore: iqScore,
            iqP: value.iqP,
            iqN: value.iqN,
            countP: value.countP,
            countN: value.countN,
            coveredTasks: value.coveredTasks,
            totalTasks: value.totalTasks,
            coverageInsufficient: value.coverageInsufficient == true,
            methodTitle: value.methodTitle
        )
    }

    private func validatedScore(
        _ value: Double?,
        harnessIndex: Int,
        cellIndex: Int
    ) throws -> Double? {
        guard let value else { return nil }
        guard value.isFinite, (0...150).contains(value) else {
            throw CodexRenderedCrowdtestIQDOMParserError.invalidCell(harnessIndex: harnessIndex, cellIndex: cellIndex)
        }
        return value
    }

    static func parsedTrendLabel(_ label: String) -> CodexRenderedCrowdtestIQTrendPoint {
        // "09/19 07:00 · 106.6 IQ"
        let parts = label.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        var month: Int?
        var day: Int?
        var hour: Int?
        var score: Double?
        if let timing = parts.first {
            let tokens = timing.split(separator: " ").map(String.init)
            if tokens.count >= 2 {
                let dateParts = tokens[0].split(separator: "/").compactMap { Int($0) }
                if dateParts.count == 2 {
                    month = dateParts[0]
                    day = dateParts[1]
                }
                let timeParts = tokens[1].split(separator: ":").compactMap { Int($0) }
                if timeParts.count >= 1 {
                    hour = timeParts[0]
                }
            }
        }
        if let tail = parts.dropFirst().first {
            let number = tail.split(separator: " ").first.map(String.init) ?? tail
            score = Double(number)
        }
        return CodexRenderedCrowdtestIQTrendPoint(label: label, month: month, day: day, hour: hour, score: score)
    }

    private func isBoundedDisplayText(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private func isSafeToken(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 43, 45, 46, 48...57, 65...90, 95, 97...122:
                true
            default:
                false
            }
        }
    }
}

private struct ExtractionDTO: Decodable {
    let revision: String
    let finalOrigin: String
    let pageState: PageState
    let harnesses: [Harness]

    enum PageState: String, Decodable {
        case challenge
        case consent
        case ready
    }

    struct Harness: Decodable {
        let harness: String
        let cells: [Cell]
        let circles: [String]
    }

    struct Cell: Decodable {
        let model: String
        let effort: String
        let iqScore: Double?
        let iqP: Int?
        let iqN: Int?
        let countP: Int?
        let countN: Int?
        let coveredTasks: Int?
        let totalTasks: Int?
        let coverageInsufficient: Bool?
        let methodTitle: String?
    }
}
