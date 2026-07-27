import Foundation

enum CodexRenderedIQHistoryDOMParserError: Error, Equatable, Sendable {
    case bridgePayloadTooLarge
    case invalidPayload
    case revisionMismatch
    case invalidFinalOrigin
    case blockedPage
    case missingRoot
    case invalidSelectedRange
    case contentPending
    case invalidSeriesCount
    case invalidSeries(seriesIndex: Int)
    case duplicateSeries(seriesIndex: Int)
    case missingAggregate
    case invalidPointCount(seriesIndex: Int)
    case invalidPoint(seriesIndex: Int, pointIndex: Int)
    case duplicatePoint(seriesIndex: Int, pointIndex: Int)
    case invalidPointLabel(seriesIndex: Int, pointIndex: Int)
    case invalidIQ(seriesIndex: Int, pointIndex: Int)
}

struct CodexRenderedIQHistoryDOMParser: Sendable {
    static let parserRevision = "codex-radar-rendered-iq-history-v1"
    static let maximumBridgePayloadBytes = 64 * 1_024

    func parse(_ data: Data, capturedAt: Date) throws -> CodexRenderedIQHistorySnapshot {
        guard data.count <= Self.maximumBridgePayloadBytes else {
            throw CodexRenderedIQHistoryDOMParserError.bridgePayloadTooLarge
        }

        let dto: ExtractionDTO
        do {
            dto = try JSONDecoder().decode(ExtractionDTO.self, from: data)
        } catch {
            throw CodexRenderedIQHistoryDOMParserError.invalidPayload
        }

        guard dto.revision == Self.parserRevision else {
            throw CodexRenderedIQHistoryDOMParserError.revisionMismatch
        }
        guard dto.finalOrigin == "https://deng.codexradar.com" else {
            throw CodexRenderedIQHistoryDOMParserError.invalidFinalOrigin
        }
        guard dto.pageState == .ready else {
            throw CodexRenderedIQHistoryDOMParserError.blockedPage
        }
        guard dto.rootPresent else {
            throw CodexRenderedIQHistoryDOMParserError.missingRoot
        }
        guard dto.selectedRange == "24h" else {
            throw CodexRenderedIQHistoryDOMParserError.invalidSelectedRange
        }
        guard !dto.series.isEmpty else {
            throw CodexRenderedIQHistoryDOMParserError.contentPending
        }
        guard (2...8).contains(dto.series.count) else {
            throw CodexRenderedIQHistoryDOMParserError.invalidSeriesCount
        }
        guard dto.series.contains(where: { $0.seriesKey == "aggregate" }) else {
            throw CodexRenderedIQHistoryDOMParserError.missingAggregate
        }

        let series = try validatedSeries(dto.series)
        guard series.filter({ $0.seriesKey == "aggregate" }).count == 1 else {
            throw CodexRenderedIQHistoryDOMParserError.missingAggregate
        }

        let fingerprint: String
        do {
            fingerprint = try CodexRenderedIQHistorySemanticFingerprint.make(
                sourceID: .codexRadar,
                series: series,
                finalOrigin: dto.finalOrigin,
                parserRevision: dto.revision
            )
        } catch {
            throw CodexRenderedIQHistoryDOMParserError.invalidPayload
        }

        return CodexRenderedIQHistorySnapshot(
            sourceID: .codexRadar,
            parserRevision: dto.revision,
            finalOrigin: dto.finalOrigin,
            capturedAt: capturedAt,
            series: series,
            semanticFingerprint: fingerprint
        )
    }

    private func validatedSeries(_ values: [ExtractionDTO.Series]) throws -> [CodexRenderedIQHistorySeries] {
        var keys = Set<String>()
        return try values.enumerated().map { seriesIndex, value in
            guard value.sourceOrder == seriesIndex,
                  isBoundedText(value.displayName, maximumLength: 128),
                  isValidSeriesKey(value.seriesKey, seriesIndex: seriesIndex) else {
                throw CodexRenderedIQHistoryDOMParserError.invalidSeries(seriesIndex: seriesIndex)
            }
            guard keys.insert(value.seriesKey).inserted else {
                throw CodexRenderedIQHistoryDOMParserError.duplicateSeries(seriesIndex: seriesIndex)
            }
            guard value.points.count == 24 else {
                throw CodexRenderedIQHistoryDOMParserError.invalidPointCount(seriesIndex: seriesIndex)
            }

            var sourceOrders = Set<Int>()
            var sourceLabels = Set<String>()
            let points = try value.points.enumerated().map { pointIndex, point in
                guard sourceOrders.insert(point.sourceOrder).inserted else {
                    throw CodexRenderedIQHistoryDOMParserError.duplicatePoint(
                        seriesIndex: seriesIndex,
                        pointIndex: pointIndex
                    )
                }
                guard point.sourceOrder == pointIndex else {
                    throw CodexRenderedIQHistoryDOMParserError.invalidPoint(
                        seriesIndex: seriesIndex,
                        pointIndex: pointIndex
                    )
                }
                guard isBoundedText(point.sourceTimeLabel, maximumLength: 64),
                      sourceLabels.insert(point.sourceTimeLabel).inserted else {
                    throw CodexRenderedIQHistoryDOMParserError.invalidPointLabel(
                        seriesIndex: seriesIndex,
                        pointIndex: pointIndex
                    )
                }
                guard point.iq.isFinite, (0...150).contains(point.iq) else {
                    throw CodexRenderedIQHistoryDOMParserError.invalidIQ(
                        seriesIndex: seriesIndex,
                        pointIndex: pointIndex
                    )
                }
                return CodexRenderedIQHistoryPoint(
                    sourceOrder: point.sourceOrder,
                    sourceTimeLabel: point.sourceTimeLabel,
                    iq: point.iq
                )
            }
            return CodexRenderedIQHistorySeries(
                sourceOrder: value.sourceOrder,
                seriesKey: value.seriesKey,
                displayName: value.displayName,
                points: points
            )
        }
    }

    private func isValidSeriesKey(_ key: String, seriesIndex: Int) -> Bool {
        if key == "aggregate" {
            return seriesIndex == 0
        }
        guard key.hasPrefix("model:") else { return false }
        let model = String(key.dropFirst("model:".count))
        return isSafeToken(model, maximumLength: 64)
    }

    private func isBoundedText(_ value: String, maximumLength: Int) -> Bool {
        !value.isEmpty
            && value.count <= maximumLength
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private func isSafeToken(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
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
    let rootPresent: Bool
    let selectedRange: String?
    let pageState: PageState
    let series: [Series]

    struct Series: Decodable {
        let sourceOrder: Int
        let seriesKey: String
        let displayName: String
        let points: [Point]
    }

    struct Point: Decodable {
        let sourceOrder: Int
        let sourceTimeLabel: String
        let iq: Double
    }
}

private enum PageState: String, Decodable {
    case ready
    case challenge
    case consent
}
