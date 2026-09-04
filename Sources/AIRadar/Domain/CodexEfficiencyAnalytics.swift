import Foundation

struct CodexEfficiencyCoordinate: Hashable, Sendable {
    let family: String
    let effort: String
}

struct CodexEfficiencyMatrixCell: Identifiable, Equatable, Sendable {
    let coordinate: CodexEfficiencyCoordinate
    let point: IntelligenceEfficiencyPoint

    var id: CodexEfficiencyCoordinate { coordinate }
    var family: String { coordinate.family }
    var effort: String { coordinate.effort }
    var quality: Double { point.quality }
    var averageCostUSD: Double { point.averageCostUSD }
    var averageMinutes: Double { point.averageMinutes }
}

struct CodexCostVersusIQPoint: Identifiable, Equatable, Sendable {
    let family: String
    let point: IntelligenceEfficiencyPoint

    var id: ModelID { point.id }
    var x: Double { point.combinedCostIndex }
    var y: Double { point.quality }
}

enum CodexEfficiencyAnalytics {
    static func matrix<S: Sequence>(points: S) -> [CodexEfficiencyMatrixCell]
    where S.Element == IntelligenceEfficiencyPoint {
        let cells = points.compactMap { point -> CodexEfficiencyMatrixCell? in
            let family = RadarModelIdentity.family(id: point.id, displayName: point.modelName)
            guard let effort = RadarModelIdentity.effort(id: point.id, displayName: point.modelName) else {
                return nil
            }
            return .init(coordinate: .init(family: family, effort: effort), point: point)
        }
        .sorted(by: matrixOrder)
        var seen = Set<CodexEfficiencyCoordinate>()
        return cells.filter { seen.insert($0.coordinate).inserted }
    }

    static func costVersusIQ<S: Sequence>(points: S) -> [CodexCostVersusIQPoint]
    where S.Element == IntelligenceEfficiencyPoint {
        points.map {
            .init(
                family: RadarModelIdentity.family(id: $0.id, displayName: $0.modelName),
                point: $0
            )
        }
        .sorted {
            let familyOrder = compareFamilies($0.family, $1.family)
            if familyOrder != .orderedSame { return familyOrder == .orderedAscending }
            return $0.id.upstreamKey < $1.id.upstreamKey
        }
    }

    private static func matrixOrder(
        _ lhs: CodexEfficiencyMatrixCell,
        _ rhs: CodexEfficiencyMatrixCell
    ) -> Bool {
        let familyOrder = compareFamilies(lhs.family, rhs.family)
        if familyOrder != .orderedSame { return familyOrder == .orderedAscending }
        let leftEffort = RadarModelIdentity.efforts.firstIndex(of: lhs.effort)!
        let rightEffort = RadarModelIdentity.efforts.firstIndex(of: rhs.effort)!
        if leftEffort != rightEffort { return leftEffort < rightEffort }
        return lhs.point.id.upstreamKey < rhs.point.id.upstreamKey
    }

    private static func compareFamilies(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = RadarModelIdentity.canonicalFamilies.firstIndex(of: lhs)
        let right = RadarModelIdentity.canonicalFamilies.firstIndex(of: rhs)
        switch (left, right) {
        case let (left?, right?):
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case (_?, nil):
            return .orderedAscending
        case (nil, _?):
            return .orderedDescending
        case (nil, nil):
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        }
    }
}
