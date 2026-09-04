import SwiftUI

// Shared presentation components introduced by the upstream visual sync
// (spec §7). Every component consumes locally-defined view models only —
// never repository datasets or entities — so P2 data-landing changes cannot
// ripple into the P0 visual baseline.

/// Codex station announcement banner (spec §4.2): renders only when window
/// content exists; green band when the reset window is open, amber when
/// closed. A missing snapshot is the caller's concern — pass nil and nothing
/// renders.
struct AnnouncementBanner: View {
    struct Content: Equatable, Sendable {
        let title: String
        let message: String?
        let isOpen: Bool
        let statusWord: String?

        init(title: String, message: String? = nil, isOpen: Bool, statusWord: String? = nil) {
            self.title = title
            self.message = message
            self.isOpen = isOpen
            self.statusWord = statusWord
        }
    }

    @Environment(\.radarPalette) private var palette
    let content: Content?

    var body: some View {
        if let content {
            VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
                HStack(spacing: RadarStyle.compactSpacing) {
                    Image(systemName: content.isOpen ? "bolt.horizontal.circle" : "clock.badge.checkmark")
                    Text(content.title).font(.headline)
                    if let statusWord = content.statusWord {
                        Text(statusWord)
                            .radarPill(accent: content.isOpen ? palette.green : palette.amber,
                                       soft: content.isOpen ? palette.greenSoft : palette.amberSoft)
                    }
                }
                if let message = content.message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText.color)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RadarStyle.cardSpacing)
            .background(
                (content.isOpen ? palette.greenSoft : palette.amberSoft).color,
                in: .rect(cornerRadius: RadarStyle.cardCornerRadius)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: RadarStyle.inlineCornerRadius)
                    .fill((content.isOpen ? palette.green : palette.amber).color)
                    .frame(width: RadarStyle.accentBarWidth)
            }
            .overlay {
                RoundedRectangle(cornerRadius: RadarStyle.cardCornerRadius)
                    .stroke((content.isOpen ? palette.green : palette.amber).color.opacity(0.27))
            }
        }
    }
}

/// Station status dot (spec §4.1): four states mapped to semantic colors;
/// placeholder stations are always muted. Mapping table recorded in design-qa.
enum StationStatusLevel: Equatable, Sendable {
    case fresh
    case stale
    case error
    case muted
}

extension StationStatusLevel {
    /// Status-dot mapping (design-qa table): fresh -> green; stale/LKG/
    /// validation-failed -> amber; error -> red; loading/empty/unavailable/
    /// disabled/none -> muted.
    static func map(_ state: WorkspaceState) -> StationStatusLevel {
        switch state {
        case .fresh: .fresh
        case .stale, .usingLastKnownGood, .validationFailed: .stale
        case .error: .error
        case .loading, .empty, .unavailable, .disabled: .muted
        }
    }
}

struct StationStatusDot: View {
    @Environment(\.radarPalette) private var palette
    let level: StationStatusLevel
    var diameter: CGFloat = 9

    var body: some View {
        Circle()
            .fill(color.opacity(level == .muted ? 0.45 : 1))
            .frame(width: diameter, height: diameter)
    }

    private var color: Color {
        switch level {
        case .fresh: palette.green.color
        case .stale: palette.amber.color
        case .error: palette.red.color
        case .muted: palette.secondaryText.color
        }
    }
}

/// Star rating matrix (spec §5.4, read-only; upstream submission stays a link).
/// Rows are model groups; columns are arbitrary labeled buckets (24h / 7-day
/// days). Cells render a 0-5 star fill with a count suffix.
struct StarRatingMatrix: View {
    struct Cell: Equatable, Sendable {
        let average: Double
        let count: Int

        static let empty = Cell(average: 0, count: 0)
    }

    struct Row: Equatable, Sendable {
        let title: String
        let subtitle: String?
        let cells: [Cell?]

        init(title: String, subtitle: String? = nil, cells: [Cell?]) {
            self.title = title
            self.subtitle = subtitle
            self.cells = cells
        }
    }

    @Environment(\.radarPalette) private var palette
    let columnTitles: [String]
    let rows: [Row]

    var body: some View {
        if rows.isEmpty || columnTitles.isEmpty {
            Text("暂无评分数据")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText.color)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(RadarStyle.cardSpacing)
        } else {
            VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
                header
                ForEach(rows, id: \.title) { row in
                    rowView(row)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: RadarStyle.compactSpacing) {
            Text("").frame(width: 130, alignment: .leading)
            ForEach(columnTitles, id: \.self) { title in
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText.color)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: RadarStyle.compactSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.primaryText.color)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText.color)
                }
            }
            .frame(width: 130, alignment: .leading)
            ForEach(row.cells.indices, id: \.self) { index in
                cellView(row.cells[index])
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.divider.color).frame(height: 1)
        }
    }

    private func cellView(_ cell: Cell?) -> some View {
        let cell = cell ?? .empty
        return HStack(spacing: 3) {
            stars(fill: cell.average)
            Text(cell.count > 0 ? "\(cell.average, format: .number.precision(.fractionLength(1)))" : "暂无")
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.color)
        }
    }

    private func stars(fill: Double) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { star in
                Image(systemName: symbol(for: fill, star: star))
                    .font(.caption2)
                    .foregroundStyle(palette.amber.color)
            }
        }
    }

    private func symbol(for fill: Double, star: Int) -> String {
        let threshold = Double(star) + 0.75
        if fill >= threshold { return "star.fill" }
        if fill >= Double(star) + 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Zero-fill and bucket logic for the monthly table, kept outside the View
/// struct so it carries no MainActor isolation (View protocol conformance).
enum MonthlyCountSeries {
    struct MonthCount: Equatable, Sendable {
        let monthLabel: String
        let count: Int
    }

    /// Zero-fills calendar months between the first and last observed labels
    /// (ascending order; spec §4.2 row 5). Input labels use "yyyy-MM".
    static func zeroFilled(from counts: [String: Int]) -> [MonthCount] {
        let keys = counts.keys.sorted()
        guard let first = keys.first, let last = keys.last else { return [] }
        guard let start = parse(first), let end = parse(last) else {
            return keys.map { MonthCount(monthLabel: $0, count: counts[$0] ?? 0) }
        }
        var output: [MonthCount] = []
        var year = start.year, month = start.month
        while year < end.year || (year == end.year && month <= end.month) {
            let label = String(format: "%04d-%02d", year, month)
            output.append(MonthCount(monthLabel: label, count: counts[label] ?? 0))
            month += 1
            if month > 12 { month = 1; year += 1 }
        }
        return output
    }

    private static func parse(_ label: String) -> (year: Int, month: Int)? {
        let parts = label.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else {
            return nil
        }
        return (year, month)
    }
}

/// Monthly run-count table (spec §4.2 Fast 雷达): columns are calendar
/// months in ascending order with zero-filled gaps; values are run counts.
struct MonthlyCountTable: View {
    @Environment(\.radarPalette) private var palette
    let entries: [MonthlyCountSeries.MonthCount]

    var body: some View {
        if entries.isEmpty {
            Text("暂无历史记录")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText.color)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(RadarStyle.cardSpacing)
        } else {
            VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
                ForEach(entries, id: \.monthLabel) { entry in
                    HStack {
                        Text(entry.monthLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.secondaryText.color)
                            .frame(width: 84, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: RadarStyle.inlineCornerRadius)
                                    .fill(palette.greenSoft.color)
                                RoundedRectangle(cornerRadius: RadarStyle.inlineCornerRadius)
                                    .fill(palette.green.color)
                                    .frame(width: barWidth(in: proxy.size.width, count: entry.count))
                            }
                        }
                        .frame(height: 14)
                        Text("\(entry.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.primaryText.color)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func barWidth(in available: CGFloat, count: Int) -> CGFloat {
        let maximum = entries.map(\.count).max() ?? 0
        guard maximum > 0 else { return 0 }
        return available * CGFloat(count) / CGFloat(maximum)
    }
}

/// Community knowledge list card (spec §12): title + upstream summary +
/// external link; without an upstream summary only title and link. Never
/// generates local copy.
struct CommunityKnowledgeList: View {
    struct Article: Equatable, Sendable, Identifiable {
        let title: String
        let summary: String?
        let url: URL

        var id: String { title + url.absoluteString }
    }

    @Environment(\.radarPalette) private var palette
    let articles: [Article]

    var body: some View {
        if articles.isEmpty {
            Text("暂无知识文章条目；上游文章卡接入后按「标题 + 摘要 + 外链」显示。")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(RadarStyle.cardSpacing)
        } else {
            VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
                ForEach(articles) { article in
                    VStack(alignment: .leading, spacing: 2) {
                        Link(article.title, destination: article.url)
                            .font(.subheadline.weight(.medium))
                        if let summary = article.summary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText.color)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
