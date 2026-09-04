import Foundation

enum WorkspaceDestination: String, CaseIterable, Identifiable, Sendable {
    case overview = "概览"
    case decisionLens = "决策透镜"
    case models = "模型"
    case trends = "趋势"
    case intelligenceCenter = "智力中心"
    case efficiencyPK = "效能 PK"
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
        case .efficiencyPK: "bolt.shield"
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
        case .efficiencyPK: "efficiency-pk"
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
        case "efficiency-pk": self = .efficiencyPK
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
            [.overview, .decisionLens, .models, .trends, .intelligenceCenter, .sourceStatus, .export]
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
/// content yet (spec §4.1): 预览占位 only, never synchronized.
enum UpcomingStation: String, CaseIterable, Hashable, Sendable, Identifiable {
    case dsh
    case zcode
    case grok
    case kimi

    var id: Self { self }

    var displayName: String {
        switch self {
        case .dsh: "DSH 站"
        case .zcode: "ZCode 站"
        case .grok: "Grok 站"
        case .kimi: "Kimi 站"
        }
    }
}

/// Workspace navigation unit (spec §4.1). Real stations reuse the existing
/// `RadarSourceID` raw values so persisted route keys stay compatible; the
/// aggregate station keeps the legacy "information-overview" storage key.
enum WorkspaceStation: Hashable, Sendable {
    case aggregate
    case source(RadarSourceID)
    case upcoming(UpcomingStation)

    static let realSources: [RadarSourceID] = [.claudeCodeRadar, .codexRadar, .sweBenchVerified]

    var rawValue: String {
        switch self {
        case .aggregate: "aggregate"
        case .source(let sourceID): sourceID.rawValue
        case .upcoming(let station): station.rawValue
        }
    }

    init(rawValue: String) {
        if rawValue == Self.aggregate.rawValue {
            self = .aggregate
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
}

enum WorkspaceRoute: Hashable, Sendable {
    case informationOverview
    case source(RadarSourceID)
    case sourcePage(RadarSourceID, WorkspaceDestination)
    case export
    case upcoming(UpcomingStation)

    static let initial = Self.informationOverview

    static func storageKey(for station: WorkspaceStation) -> String {
        switch station {
        case .aggregate: WorkspaceRoute.informationOverview.storageKey
        case .source(let sourceID): WorkspaceRoute.source(sourceID).storageKey
        case .upcoming(let upcoming): WorkspaceRoute.upcoming(upcoming).storageKey
        }
    }

    var sourceID: RadarSourceID? {
        switch self {
        case .source(let sourceID), .sourcePage(let sourceID, _): sourceID
        case .informationOverview, .export, .upcoming: nil
        }
    }

    var storageKey: String {
        switch self {
        case .informationOverview: "information-overview"
        case .source(let sourceID): "source:\(sourceID.rawValue)"
        case .sourcePage(let sourceID, let destination):
            "source:\(sourceID.rawValue):\(destination.storageKey)"
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
