import Foundation

enum CodexIQHistoryAvailability: Equatable, Sendable {
    case available
    case insufficientHistory
}

struct CodexIQHistoryPoint: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let value: Double
}

struct CodexIQHistorySegment: Identifiable, Equatable, Sendable {
    let effort: String
    let seriesRevision: String
    let points: [CodexIQHistoryPoint]

    var id: String {
        "\(effort)|\(seriesRevision)|\(points.first?.date.timeIntervalSince1970 ?? 0)"
    }
}

struct CodexIQHistoryLine: Identifiable, Equatable, Sendable {
    let family: String
    let effort: String
    let segments: [CodexIQHistorySegment]

    var id: String { "\(family)|\(effort)" }
}

struct CodexIQHistoryPanel: Identifiable, Equatable, Sendable {
    let family: String
    let lines: [CodexIQHistoryLine]

    var id: String { family }
}

struct CodexIQHistoryProjection: Equatable, Sendable {
    let availability: CodexIQHistoryAvailability
    let panels: [CodexIQHistoryPanel]
}

enum CodexIQHistoryAnalytics {
    static func project(history: [BenchmarkDataset]) -> CodexIQHistoryProjection {
        var observations: [Key: [Date: [Decimal?]]] = [:]

        for snapshot in history where snapshot.sourceID == .codexRadar {
            let date = snapshot.sourceUpdatedAt ?? snapshot.fetchedAt
            for model in snapshot.models where model.id.sourceID == .codexRadar {
                let family = RadarModelIdentity.family(id: model.id, displayName: model.descriptor.displayName)
                guard RadarModelIdentity.canonicalFamilies.contains(family),
                      let effort = RadarModelIdentity.effort(id: model.id, displayName: model.descriptor.displayName)
                else { continue }
                let key = Key(family: family, effort: effort, seriesRevision: snapshot.seriesRevision)
                observations[key, default: [:]][date, default: []].append(model.qualityScore)
            }
        }

        let segmentRecords = observations.flatMap { key, values in
            segments(for: key, values: values)
        }
        let groupedSegments = Dictionary(grouping: segmentRecords, by: { LineKey(family: $0.family, effort: $0.effort) })
        let lines = Set(observations.keys.map { LineKey(family: $0.family, effort: $0.effort) })
            .map { key in
                CodexIQHistoryLine(
                    family: key.family,
                    effort: key.effort,
                    segments: (groupedSegments[key] ?? [])
                        .sorted(by: segmentOrder)
                        .map { .init(effort: $0.effort, seriesRevision: $0.seriesRevision, points: $0.points) }
                )
            }
        let panels = RadarModelIdentity.canonicalFamilies.map { family in
            CodexIQHistoryPanel(
                family: family,
                lines: lines.filter { $0.family == family }.sorted(by: lineOrder)
            )
        }
        let availability: CodexIQHistoryAvailability = panels
            .flatMap { $0.lines }
            .flatMap { $0.segments }
            .contains { $0.points.count >= 2 } ? .available : .insufficientHistory
        return .init(availability: availability, panels: panels)
    }

    private static func segments(
        for key: Key,
        values: [Date: [Decimal?]]
    ) -> [SegmentRecord] {
        var result: [SegmentRecord] = []
        var points: [CodexIQHistoryPoint] = []
        for (date, values) in values.sorted(by: { $0.key < $1.key }) {
            guard case .value(let value) = resolve(values) else {
                if !points.isEmpty {
                    result.append(.init(family: key.family, effort: key.effort, seriesRevision: key.seriesRevision, points: points))
                    points = []
                }
                continue
            }
            points.append(.init(
                id: "\(key.family)|\(key.effort)|\(key.seriesRevision)|\(date.timeIntervalSince1970)",
                date: date,
                value: NSDecimalNumber(decimal: value).doubleValue
            ))
        }
        if !points.isEmpty {
            result.append(.init(family: key.family, effort: key.effort, seriesRevision: key.seriesRevision, points: points))
        }
        return result
    }

    private static func resolve(_ values: [Decimal?]) -> Resolution {
        guard values.contains(where: { $0 != nil }) else { return .missing }
        guard !values.contains(where: { $0 == nil }),
              let value = values.first!,
              Set(values).count == 1,
              NSDecimalNumber(decimal: value).doubleValue.isFinite
        else { return .conflict }
        return .value(value)
    }

    private static func lineOrder(_ lhs: CodexIQHistoryLine, _ rhs: CodexIQHistoryLine) -> Bool {
        let left = RadarModelIdentity.efforts.firstIndex(of: lhs.effort) ?? RadarModelIdentity.efforts.count
        let right = RadarModelIdentity.efforts.firstIndex(of: rhs.effort) ?? RadarModelIdentity.efforts.count
        return left == right ? lhs.effort < rhs.effort : left < right
    }

    private static func segmentOrder(_ lhs: SegmentRecord, _ rhs: SegmentRecord) -> Bool {
        let left = lhs.points.first?.date ?? .distantFuture
        let right = rhs.points.first?.date ?? .distantFuture
        return left == right ? lhs.seriesRevision < rhs.seriesRevision : left < right
    }

    private enum Resolution {
        case missing
        case value(Decimal)
        case conflict
    }

    private struct Key: Hashable {
        let family: String
        let effort: String
        let seriesRevision: String
    }

    private struct LineKey: Hashable {
        let family: String
        let effort: String
    }

    private struct SegmentRecord {
        let family: String
        let effort: String
        let seriesRevision: String
        let points: [CodexIQHistoryPoint]
    }
}
