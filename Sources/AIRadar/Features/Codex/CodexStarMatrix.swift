import SwiftUI

/// Star rating matrix wiring (spec §5.4): builds the shared
/// `StarRatingMatrix` view-model from the community dataset — the 7-day
/// columns take the trailing `history[]` days, the 24h column uses the
/// current `day` bucket, and "我的评分" comes from the read-only
/// `my_scores` field (D12: display-only, never persisted).
enum CodexStarMatrixModel {
    struct Matrix {
        let columnTitles: [String]
        let rows: [StarRatingMatrix.Row]
    }

    static func build(dataset: CommunityDataset) -> Matrix {
        let history = (dataset.history ?? []).sorted { ($0.day ?? "") < ($1.day ?? "") }
        guard !history.isEmpty else {
            return Matrix(columnTitles: [], rows: [])
        }

        // 24h column = the bucket matching the payload `day` label; fallback
        // to the newest bucket. Trailing 7-day columns exclude that bucket.
        let dayKey = dataset.day ?? history.last?.day
        let current = history.first { $0.day == dayKey } ?? history.last
        let trailing = history.filter { $0.day != current?.day }.suffix(7)

        var titles: [String] = []
        if current != nil { titles.append("24h") }
        titles.append(contentsOf: trailing.compactMap(\.day))

        // Star fill normalized against the scale maximum (0-5 stars).
        let divisor = dataset.ratings.first.map { NSDecimalNumber(decimal: $0.scaleMaximum ?? 10).doubleValue / 5.0 } ?? 2.0
        let starDivisor = divisor > 0 ? divisor : 2.0

        func cell(_ rating: CommunityHistoryRating?, mine: Double?) -> StarRatingMatrix.Cell? {
            guard let rating, let average = rating.average else { return nil }
            let value = NSDecimalNumber(decimal: average).doubleValue
            return StarRatingMatrix.Cell(
                average: value,
                count: rating.count ?? 0,
                starFill: value / starDivisor,
                mine: mine
            )
        }

        func ratingsByDay(_ day: CommunityHistoryDay?) -> [String: CommunityHistoryRating] {
            var map: [String: CommunityHistoryRating] = [:]
            for entry in day?.ratings ?? [] {
                guard let id = entry.id else { continue }
                map[id] = entry
            }
            return map
        }

        let currentRatings = ratingsByDay(current)
        let trailingRatings = trailing.map { ratingsByDay($0) }

        let rows: [StarRatingMatrix.Row] = dataset.ratings
            .sorted {
                if $0.group != $1.group { return ($0.group ?? "") < ($1.group ?? "") }
                return $0.model.displayName.localizedStandardCompare($1.model.displayName).rawValue < 0
            }
            .map { rating in
                let key = rating.id.upstreamKey
                let mine = dataset.myScores?[key].map { NSDecimalNumber(decimal: $0).doubleValue }
                var cells: [StarRatingMatrix.Cell?] = []
                if current != nil { cells.append(cell(currentRatings[key], mine: mine)) }
                cells.append(contentsOf: trailingRatings.map { cell($0[key], mine: mine) })
                return StarRatingMatrix.Row(
                    title: rating.model.displayName,
                    subtitle: rating.group,
                    pill: rating.effortSuffix,
                    cells: cells
                )
            }

        return Matrix(columnTitles: titles, rows: rows)
    }
}

/// Speed-overview star matrix card (spec §5.4/D7/D12): read-only matrix,
/// upstream scoring link, effort pills on the whitelisted labels.
struct CodexStarMatrixCard: View {
    @Environment(\.radarPalette) private var palette
    let dataset: CommunityDataset
    let attributionText: String

    var body: some View {
        let matrix = CodexStarMatrixModel.build(dataset: dataset)
        VStack(alignment: .leading, spacing: RadarStyle.cardSpacing) {
            ViewHeader(title: "体感评分矩阵", subtitle: "当日 24h 桶 + 尾部 7 天；只读展示，打分请前往上游")
            if matrix.rows.isEmpty || matrix.columnTitles.isEmpty {
                Text("暂无评分数据")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText.color)
            } else {
                StarRatingMatrix(columnTitles: matrix.columnTitles, rows: matrix.rows)
            }
            HStack(spacing: RadarStyle.cardSpacing) {
                Link("去上游给模型体感打分", destination: URL(string: "https://codexradar.com/")!)
                    .font(.subheadline.weight(.medium))
                if let day = dataset.day {
                    Text("当日桶：\(day)")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText.color)
                }
            }
            Text(attributionText)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }
}
