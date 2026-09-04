import Foundation

enum RadarModelIdentity {
    static let canonicalFamilies = ["Sol", "Terra", "Luna", "GPT-5.5"]
    static let efforts = ["ultra", "max", "xhigh", "high", "medium", "low"]

    static func family(id: ModelID, displayName: String) -> String {
        let key = id.upstreamKey.lowercased()
        if key.contains("-sol-") { return "Sol" }
        if key.contains("-terra-") { return "Terra" }
        if key.contains("-luna-") { return "Luna" }
        if key.hasPrefix("gpt-5.5") { return "GPT-5.5" }
        guard effort(in: key, separator: "-") == nil,
              let displayEffort = effort(in: displayName, separator: " ")
        else { return displayName }
        return displayName.dropLast(displayEffort.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func effort(id: ModelID, displayName: String) -> String? {
        effort(in: id.upstreamKey, separator: "-") ?? effort(in: displayName, separator: " ")
    }

    static func family(for row: WorkspaceModelRow) -> String {
        family(id: row.id, displayName: row.name)
    }

    static func effort(for row: WorkspaceModelRow) -> String? {
        effort(id: row.id, displayName: row.name)
    }

    static func familySummaries(_ rows: [WorkspaceModelRow]) -> [RadarFamilySummary] {
        let grouped = Dictionary(grouping: rows, by: family)
        return grouped.compactMap { family, rows in
            guard let row = rows.compactMap({ $0.benchmark.qualityScore == nil ? nil : $0 })
                .max(by: { ($0.benchmark.qualityScore ?? 0) < ($1.benchmark.qualityScore ?? 0) })
            else { return nil }
            return RadarFamilySummary(family: family, row: row)
        }
        .sorted {
            let left = canonicalFamilies.firstIndex(of: $0.family) ?? canonicalFamilies.count
            let right = canonicalFamilies.firstIndex(of: $1.family) ?? canonicalFamilies.count
            if left != right { return left < right }
            return $0.family.localizedStandardCompare($1.family) == .orderedAscending
        }
        .prefix(4)
        .map { $0 }
    }

    private static func effort(in value: String, separator: String) -> String? {
        efforts.first { value.lowercased().hasSuffix("\(separator)\($0)") }
    }
}
