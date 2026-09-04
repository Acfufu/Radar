import Foundation

enum CodexRenderedWarningDOMParserError: Error, Equatable, Sendable {
    case bridgePayloadTooLarge
    case invalidPayload
    case revisionMismatch
    case invalidFinalOrigin
    case blockedPage
    case missingRoot
    case missingGrid
    case missingLiveTime
    case invalidSourceTime
    case contentPending
    case invalidCardCount
    case explicitEmptyHasCards
    case invalidCard(cardIndex: Int)
    case invalidMetrics(cardIndex: Int)
    case invalidMetricValue(cardIndex: Int)
    case duplicateIdentity(cardIndex: Int)
}

struct CodexRenderedWarningDOMParser: Sendable {
    static let parserRevision = "codex-radar-rendered-dom-v2"
    static let maximumBridgePayloadBytes = 16 * 1_024

    func parse(_ data: Data, capturedAt: Date) throws -> CodexRenderedWarningSnapshot {
        guard data.count <= Self.maximumBridgePayloadBytes else {
            throw CodexRenderedWarningDOMParserError.bridgePayloadTooLarge
        }

        let dto: ExtractionDTO
        do {
            dto = try JSONDecoder().decode(ExtractionDTO.self, from: data)
        } catch {
            throw CodexRenderedWarningDOMParserError.invalidPayload
        }

        guard dto.revision == Self.parserRevision else {
            throw CodexRenderedWarningDOMParserError.revisionMismatch
        }
        guard dto.finalOrigin == "https://codexradar.com" else {
            throw CodexRenderedWarningDOMParserError.invalidFinalOrigin
        }
        guard dto.pageState != .challenge, dto.pageState != .consent else {
            throw CodexRenderedWarningDOMParserError.blockedPage
        }
        guard dto.rootPresent else {
            throw CodexRenderedWarningDOMParserError.missingRoot
        }
        guard dto.gridPresent else {
            throw CodexRenderedWarningDOMParserError.missingGrid
        }
        guard dto.liveTimePresent else {
            throw CodexRenderedWarningDOMParserError.missingLiveTime
        }
        guard let sourceTimeLabel = dto.sourceTimeLabel,
              isBoundedDisplayText(sourceTimeLabel, maximumLength: 256) else {
            throw CodexRenderedWarningDOMParserError.invalidSourceTime
        }

        let cards: [CodexRenderedWarningCard]
        switch dto.pageState {
        case .empty:
            guard dto.cards.isEmpty else {
                throw CodexRenderedWarningDOMParserError.explicitEmptyHasCards
            }
            cards = []
        case .ready:
            guard !dto.cards.isEmpty else {
                throw CodexRenderedWarningDOMParserError.contentPending
            }
            guard dto.cards.count <= 4 else {
                throw CodexRenderedWarningDOMParserError.invalidCardCount
            }
            cards = try validatedCards(dto.cards)
        case .challenge, .consent:
            throw CodexRenderedWarningDOMParserError.blockedPage
        }

        let fingerprint: String
        do {
            fingerprint = try CodexRenderedWarningSemanticFingerprint.make(
                sourceTimeLabel: sourceTimeLabel,
                cards: cards,
                finalOrigin: dto.finalOrigin,
                parserRevision: dto.revision
            )
        } catch {
            throw CodexRenderedWarningDOMParserError.invalidPayload
        }

        return CodexRenderedWarningSnapshot(
            sourceID: .codexRadar,
            parserRevision: dto.revision,
            finalOrigin: dto.finalOrigin,
            sourceTimeLabel: sourceTimeLabel,
            capturedAt: capturedAt,
            cards: cards,
            semanticFingerprint: fingerprint
        )
    }

    private func validatedCards(_ values: [ExtractionDTO.Card]) throws -> [CodexRenderedWarningCard] {
        var identities = Set<String>()
        return try values.enumerated().map { index, value in
            guard value.sourceOrder == index,
                  isBoundedDisplayText(value.displayName, maximumLength: 64),
                  isSafeToken(value.family),
                  isSafeToken(value.effort) else {
                throw CodexRenderedWarningDOMParserError.invalidCard(cardIndex: index)
            }

            let identity = "\(value.family.lowercased())|\(value.effort.lowercased())"
            guard identities.insert(identity).inserted else {
                throw CodexRenderedWarningDOMParserError.duplicateIdentity(cardIndex: index)
            }

            let metrics = Dictionary(grouping: value.metrics, by: \.kind)
            guard metrics.keys.allSatisfy({ MetricKind.allCases.contains($0) }),
                  metrics[.iq]?.count == 1,
                  metrics[.drop24h]?.count == 1,
                  (metrics[.drop48h]?.count ?? 0) <= 1,
                  value.metrics.count == 2 + (metrics[.drop48h] == nil ? 0 : 1) else {
                throw CodexRenderedWarningDOMParserError.invalidMetrics(cardIndex: index)
            }

            let iq = metrics[.iq]![0].value
            let drop24h = metrics[.drop24h]![0].value
            let drop48h = metrics[.drop48h]?.first?.value
            guard iq.isFinite, (0...150).contains(iq),
                  drop24h.isFinite, drop24h >= 0,
                  drop48h.map({ $0.isFinite && $0 >= 0 }) ?? true else {
                throw CodexRenderedWarningDOMParserError.invalidMetricValue(cardIndex: index)
            }

            return CodexRenderedWarningCard(
                displayName: value.displayName,
                family: value.family.lowercased(),
                effort: value.effort.lowercased(),
                sourceOrder: value.sourceOrder,
                iq: iq,
                drop24h: drop24h,
                drop48h: drop48h
            )
        }
    }

    private func isBoundedDisplayText(_ value: String, maximumLength: Int) -> Bool {
        !value.isEmpty
            && value.count <= maximumLength
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private func isSafeToken(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 32 else { return false }
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
    let gridPresent: Bool
    let liveTimePresent: Bool
    let sourceTimeLabel: String?
    let pageState: PageState
    let cards: [Card]

    struct Card: Decodable {
        let sourceOrder: Int
        let displayName: String
        let family: String
        let effort: String
        let metrics: [Metric]
    }

    struct Metric: Decodable {
        let kind: MetricKind
        let value: Double
    }
}

private enum PageState: String, Decodable {
    case ready
    case empty
    case challenge
    case consent
}

private enum MetricKind: String, Decodable, CaseIterable {
    case iq
    case drop24h
    case drop48h
}
