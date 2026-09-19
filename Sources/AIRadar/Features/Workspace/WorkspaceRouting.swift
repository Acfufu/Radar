import Foundation

enum WorkspaceDestination: String, CaseIterable, Identifiable, Sendable {
    case overview = "概览"
    case decisionLens = "决策透镜"
    case models = "模型"
    case trends = "趋势"
    case intelligenceCenter = "智力中心"
    case alertsRecommendations = "预警与推荐"
    case quotaRadar = "额度雷达"
    case efficiencyPK = "效能 PK"
    case efficiencyRanking = "效能排行"
    case fastRadar = "Fast 雷达"
    case historyComparison = "历史对比"
    case tiboRadar = "Tibo 雷达"
    case communityHub = "社区入口"
    case sourceStatus = "来源状态"
    case export = "导出"
    var id: Self { self }
    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .decisionLens: "scope"
        case .models: "list.bullet.rectangle"
        case .trends: "chart.xyaxis.line"
        case .intelligenceCenter: "brain.head.profile"
        case .alertsRecommendations: "exclamationmark.triangle"
        case .quotaRadar: "gauge.with.dotted.needle"
        case .efficiencyPK: "bolt.shield"
        case .efficiencyRanking: "chart.bar.fill"
        case .fastRadar: "hare"
        case .historyComparison: "clock.arrow.circlepath"
        case .tiboRadar: "antenna.radiowaves.left.and.right"
        case .communityHub: "person.3"
        case .sourceStatus: "antenna.radiowaves.left.and.right"
        case .export: "square.and.arrow.up"
        }
    }

    func title(for sourceID: RadarSourceID) -> String {
        guard sourceID == .sweBenchVerified else { return rawValue }
        return switch self {
        case .models: "榜单"
        case .sourceStatus: "来源与口径"
        default: rawValue
        }
    }

    fileprivate var storageKey: String {
        switch self {
        case .overview: "overview"
        case .decisionLens: "decision-lens"
        case .models: "models"
        case .trends: "trends"
        case .intelligenceCenter: "intelligence-center"
        case .alertsRecommendations: "alerts-recommendations"
        case .quotaRadar: "quota-radar"
        case .efficiencyPK: "efficiency-pk"
        case .efficiencyRanking: "efficiency-ranking"
        case .fastRadar: "fast-radar"
        case .historyComparison: "history-comparison"
        case .tiboRadar: "tibo-radar"
        case .communityHub: "community-hub"
        case .sourceStatus: "source-status"
        case .export: "export"
        }
    }

    fileprivate init?(storageKey: String) {
        switch storageKey {
        case "overview": self = .overview
        case "decision-lens": self = .decisionLens
        case "models": self = .models
        case "trends": self = .trends
        case "intelligence-center": self = .intelligenceCenter
        case "alerts-recommendations": self = .alertsRecommendations
        case "quota-radar": self = .quotaRadar
        case "efficiency-pk": self = .efficiencyPK
        case "efficiency-ranking": self = .efficiencyRanking
        case "fast-radar": self = .fastRadar
        case "history-comparison": self = .historyComparison
        case "tibo-radar": self = .tiboRadar
        case "community-hub": self = .communityHub
        case "source-status": self = .sourceStatus
        case "export": self = .export
        default: return nil
        }
    }

    static func destinations(for sourceID: RadarSourceID, hasComparableHistory: Bool) -> [Self] {
        switch sourceID {
        case .claudeCodeRadar:
            [.overview, .decisionLens, .models, .trends, .sourceStatus, .export]
        case .codexRadar:
            // Spec §4.2 main axis: speed overview (row 1, includes the row-2
            // alert/recommendation cards), efficiency PK, quota radar,
            // history comparison, Tibo radar, then the tool group; community
            // hub closes the axis. The former intelligence center
            // destination is retired (spec §4.2 row 3). Fast radar is hidden
            // from navigation since v1.2 (spec §5.3 note): the page code and
            // sidecar sync stay, but no nav entry exists while the upstream
            // JSON lags the Astra UI cohort.
            [
                .overview, .alertsRecommendations, .efficiencyPK, .quotaRadar,
                .historyComparison, .tiboRadar, .communityHub,
                .decisionLens, .trends, .sourceStatus, .export,
            ]
        case .sweBenchVerified:
            hasComparableHistory
                ? [.models, .trends, .sourceStatus, .export]
                : [.models, .sourceStatus, .export]
        default:
            []
        }
    }

    static func supportsPersistedRoute(_ destination: Self, for sourceID: RadarSourceID) -> Bool {
        destinations(for: sourceID, hasComparableHistory: true).contains(destination)
    }
}

/// Stations that mirror the upstream AI 雷达 navigator but have no upstream
/// content yet (spec §4.1): 预览占位 only, never synchronized. v1.1 (ADR-0003)
/// elevated DSH/ZCode/Grok to whitelist view stations, so Kimi remains the
/// only upcoming station.
enum UpcomingStation: String, CaseIterable, Hashable, Sendable, Identifiable {
    case kimi

    var id: Self { self }

    var displayName: String {
        switch self {
        case .kimi: "Kimi 站"
        }
    }
}

/// Whitelist view stations (spec §4.1 v1.1, ADR-0003): same data plane as
/// the Codex station's intelligence-efficiency sidecar, cropped by a static
/// model whitelist mirroring the upstream front-end station config. No
/// runtime and no independent sync — the status follows the shared sidecar
/// dataset freshness, and a refresh drives the shared sidecar (same effect
/// as refreshing the Codex station).
enum WhitelistStation: String, CaseIterable, Hashable, Sendable, Identifiable {
    case dsh
    case zcode
    case grok

    var id: Self { self }

    var displayName: String {
        switch self {
        case .dsh: "DSH 站"
        case .zcode: "ZCode 站"
        case .grok: "Grok 站"
        }
    }

    /// Model whitelist frozen from the upstream station config probe
    /// (2026-09-20, .lazyzcode/evidence/v040-implementation/station-whitelist-
    /// probe.json). Spec v1.2's extra checklist models (`dsh-deepseek-v4.1-
    /// flash`, `dsh-deepseek-v4-flash-vision-exp`, `glm-5.3-flash`) exist in
    /// the data plane but not in the upstream station whitelists, so they do
    /// not join a station view.
    var modelWhitelist: Set<String> {
        switch self {
        case .dsh: ["dsh-deepseek-v4-flash", "dsh-deepseek-v4-pro"]
        case .zcode: ["glm-5.3"]
        case .grok: ["grok-4.6"]
        }
    }

    /// Four-station union for the aggregate comparison view (spec §4.1 v1.2
    /// note): Codex + DSH + ZCode + Grok. `kimi-k2.8-preview` etc. have no
    /// station and never render. Codex models come from the upstream
    /// `modelStation` mapping in the same probe.
    static let aggregateComparisonModels: Set<String> = [
        "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5",
        "deepseek-v4-flash", "deepseek-v4-pro",
        "dsh-deepseek-v4-flash", "dsh-deepseek-v4-pro",
        "glm-5.3", "grok-4.6",
    ]

    /// Source-station label for a model inside the union (probe's
    /// `modelStation` mapping, 2026-09-20).
    static func comparisonSourceLabel(for model: String?) -> String {
        switch model {
        case "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "deepseek-v4-flash", "deepseek-v4-pro":
            "Codex"
        case "dsh-deepseek-v4-flash", "dsh-deepseek-v4-pro":
            "DSH"
        case "glm-5.3":
            "ZCode"
        case "grok-4.6":
            "Grok"
        default:
            "—"
        }
    }
}

/// Workspace navigation unit (spec §4.1). Real stations reuse the existing
/// `RadarSourceID` raw values so persisted route keys stay compatible; the
/// aggregate station keeps the legacy "information-overview" storage key.
enum WorkspaceStation: Hashable, Sendable {
    case aggregate
    case source(RadarSourceID)
    case whitelist(WhitelistStation)
    case upcoming(UpcomingStation)

    static let realSources: [RadarSourceID] = [.claudeCodeRadar, .codexRadar, .sweBenchVerified]

    var rawValue: String {
        switch self {
        case .aggregate: "aggregate"
        case .source(let sourceID): sourceID.rawValue
        case .whitelist(let station): station.rawValue
        case .upcoming(let station): station.rawValue
        }
    }

    init(rawValue: String) {
        if rawValue == Self.aggregate.rawValue {
            self = .aggregate
        } else if let whitelist = WhitelistStation(rawValue: rawValue) {
            self = .whitelist(whitelist)
        } else if let upcoming = UpcomingStation(rawValue: rawValue) {
            self = .upcoming(upcoming)
        } else {
            self = .source(RadarSourceID(rawValue: rawValue))
        }
    }

    var isRealSource: Bool {
        if case .source = self { return true }
        return false
    }

    var isWhitelistStation: Bool {
        if case .whitelist = self { return true }
        return false
    }
}

enum WorkspaceRoute: Hashable, Sendable {
    case informationOverview
    case source(RadarSourceID)
    case sourcePage(RadarSourceID, WorkspaceDestination)
    case whitelist(WhitelistStation)
    case whitelistPage(WhitelistStation, WorkspaceDestination)
    case export
    case upcoming(UpcomingStation)

    static let initial = Self.informationOverview

    static func storageKey(for station: WorkspaceStation) -> String {
        switch station {
        case .aggregate: WorkspaceRoute.informationOverview.storageKey
        case .source(let sourceID): WorkspaceRoute.source(sourceID).storageKey
        case .whitelist(let station): WorkspaceRoute.whitelist(station).storageKey
        case .upcoming(let upcoming): WorkspaceRoute.upcoming(upcoming).storageKey
        }
    }

    var sourceID: RadarSourceID? {
        switch self {
        case .source(let sourceID), .sourcePage(let sourceID, _): sourceID
        case .informationOverview, .export, .whitelist, .whitelistPage, .upcoming: nil
        }
    }

    var storageKey: String {
        switch self {
        case .informationOverview: "information-overview"
        case .source(let sourceID): "source:\(sourceID.rawValue)"
        case .sourcePage(let sourceID, let destination):
            "source:\(sourceID.rawValue):\(destination.storageKey)"
        // Same shape as the pre-elevation placeholder keys, so persisted
        // routes keep working after ADR-0003 (spec §4.1 naming).
        case .whitelist(let station): "source:\(station.rawValue)"
        case .whitelistPage(let station, let destination):
            "source:\(station.rawValue):\(destination.storageKey)"
        case .export: "export"
        case .upcoming(let station): "source:\(station.rawValue)"
        }
    }

    init(storageKey: String) {
        if storageKey == "information-overview" {
            self = .informationOverview
            return
        }
        if storageKey == "export" {
            self = .export
            return
        }
        let parts = storageKey.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2, parts[0] == "source" else {
            self = .initial
            return
        }
        if let upcoming = UpcomingStation(rawValue: parts[1]) {
            self = .upcoming(upcoming)
            return
        }
        if let whitelist = WhitelistStation(rawValue: parts[1]) {
            // Persisted deep links land on the station root; the single
            // ranking page is its default destination.
            self = .whitelist(whitelist)
            return
        }
        let sourceID = RadarSourceID(rawValue: parts[1])
        if parts.count == 3,
           let destination = WorkspaceDestination(storageKey: parts[2]),
           WorkspaceDestination.supportsPersistedRoute(destination, for: sourceID) {
            self = .sourcePage(sourceID, destination)
        } else {
            self = .source(sourceID)
        }
    }
}

enum WorkspaceCopy {
    static let sourceStatusTitle = "Claude Code Radar 来源状态"
    static let quotaTitle = "Claude Code Radar 来源额度估算"
    static let exportPlaceholder = "Phase 6 将提供分页 JSON 导出"

    static func sourceStatusTitle(for source: RadarSourceDescriptor) -> String {
        "\(source.displayName) 来源状态"
    }

    static func quotaTitle(for source: RadarSourceDescriptor) -> String {
        "\(source.displayName) 来源额度估算"
    }
}

enum WorkspaceState: Equatable, Sendable {
    case loading, empty, fresh, stale, usingLastKnownGood
    case validationFailed(hasLastKnownGood: Bool)
    case unavailable(String), disabled(String), error(String)
}

enum MenuBarAction: CaseIterable { case refresh, openWorkspace, quit }
enum AppLifecycleAction { case closeWorkspace, quit; var terminatesProcess: Bool { self == .quit } }
enum RefreshActionAvailability {
    static func isEnabled(supportLevel: SupportLevel) -> Bool { supportLevel != .disabled }
}
