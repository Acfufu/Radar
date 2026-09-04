import Foundation

enum WorkspaceDestination: String, CaseIterable, Identifiable, Sendable {
    case overview = "概览"
    case decisionLens = "决策透镜"
    case models = "模型"
    case trends = "趋势"
    case intelligenceCenter = "智力中心"
    case sourceStatus = "来源状态"
    case export = "导出"
    var id: Self { self }
    var icon: String { switch self { case .overview: "rectangle.grid.2x2"; case .decisionLens: "scope"; case .models: "list.bullet.rectangle"; case .trends: "chart.xyaxis.line"; case .intelligenceCenter: "brain.head.profile"; case .sourceStatus: "antenna.radiowaves.left.and.right"; case .export: "square.and.arrow.up" } }

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

enum WorkspaceRoute: Hashable, Sendable {
    case informationOverview
    case source(RadarSourceID)
    case sourcePage(RadarSourceID, WorkspaceDestination)
    case export

    static let initial = Self.informationOverview

    var sourceID: RadarSourceID? {
        switch self {
        case .source(let sourceID), .sourcePage(let sourceID, _): sourceID
        case .informationOverview, .export: nil
        }
    }

    var storageKey: String {
        switch self {
        case .informationOverview: "information-overview"
        case .source(let sourceID): "source:\(sourceID.rawValue)"
        case .sourcePage(let sourceID, let destination):
            "source:\(sourceID.rawValue):\(destination.storageKey)"
        case .export: "export"
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
