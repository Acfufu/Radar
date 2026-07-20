# Claude Radar for macOS 26+ — Codex 执行蓝图 v2.0

> 状态：MVP 实施基线  
> 目标平台：macOS 26+  
> 语言与框架：Swift 6、SwiftUI、SwiftData、Swift Charts、Swift Testing  
> 产品类型：个人使用的 Radar 资讯浏览器  
> 不可变产品边界：只读浏览、整合与分析已发布信息
> MVP 数据源：Claude Code Radar  
> 后续数据源：Codex Radar（独立工作区，非 MVP）  
> 最后更新：2026-07-19

---

## 0. Codex 执行指令

你是本项目的实现代理。严格按照本文顺序执行，不擅自扩大范围。

### 0.1 工作方式

1. 先检查仓库现状、Xcode 工程、Bundle ID、部署目标和现有测试。
2. 对缺少的信息采用本文默认值，不因非阻断性歧义停工。
3. 每完成一个阶段：
   - 编译；
   - 运行该阶段新增的关键测试；
   - 更新 `docs/implementation-status.md`；
   - 提交一份简短变更摘要。
4. 发现第三方接口不可用、字段漂移或存在授权障碍时：
   - 不绕过访问控制；
   - 使用本地 Fixture 完成其余实现；
   - 将在线 Provider 标记为实验性；
   - 在状态文档中记录阻断原因。
5. 不实现本文“明确不做”的任何能力。
6. 优先保持代码短、清楚、可替换，不建设通用框架。

### 0.2 完成定义

MVP 完成需同时满足：

```text
应用可编译并启动
菜单栏可显示最近一次数据摘要
完整窗口可查看模型质量、基准消耗、社区评分与来源状态
同步失败时继续展示 Last-Known-Good
规范化历史按内容去重
趋势图只连接相同 seriesRevision 的记录
可导出分页 JSON 包
关键 Parser、Repository、导出测试通过
无个人 Claude 用量、OTel、后台 Agent 或跨来源聚合
```

---

# 1. 产品定义

## 1.1 一句话定位

Claude Radar 是一个 macOS 菜单栏资讯应用，用于查看 Claude Code Radar 提供的模型质量、基准消耗、社区评分和来源额度估算，并在本地保留轻量历史趋势。

## 1.2 不可变产品边界

Radar 永久定位为只读信息浏览器与本地整合分析工作台。后续增加任何来源、指标或页面时，都必须保持以下边界：

- 可以读取公开或已获授权的第三方信息，进行校验、规范化、按来源缓存、历史浏览、透明派生分析、并列呈现和导出。
- 不运行 Benchmark，不提交预测或评测任务，不生成训练/评测数据，不回写或修改上游系统。
- 不把不同测评口径合成为统一分数、统一排名或伪装成可直接比较的数据；跨来源只能并列展示事实与明确标注口径的分析。
- 不演变为执行 Agent、评测平台、任务编排器、数据生产平台或上游管理后台。
- “刷新”“同步”“筛选”“分析”“导出”属于产品能力；“运行评测”“提交任务”“生成数据”“发布回上游”不属于 Radar。

如果未来需求必须越过上述边界，应作为独立产品讨论，不得在 Radar 内以新页面、隐藏开关或 Provider 扩展实现。

## 1.3 用户价值

用户打开应用后，应能快速回答：

- 当前哪些模型质量更高？
- 最近质量、成本、Token 和耗时是否发生变化？
- 哪些模型处于质量、成本或速度的 Pareto 前沿？
- Claude Code Radar 数据是否新鲜、是否同步失败？
- Radar 来源账号公开展示的 5h/7d 额度估算是什么状态？
- 如何将本地历史导出到外部工具继续分析？

## 1.4 MVP 范围

### 必须实现

- macOS 菜单栏应用。
- 一个 Claude Code Radar 独立工作区。
- `RadarSource` 抽象和 `ClaudeCodeRadarSource` 实现。
- 模型质量数据。
- 基准消耗数据：成本、Token、耗时、Agent Steps、Cache 指标，以来源实际字段为准。
- 社区评分。
- 来源状态：5h/7d 额度估算、使用比例、重置说明，以来源实际字段为准。
- 本地规范化历史和内容去重。
- 分段 Last-Known-Good。
- 简单趋势图。
- 原始指标、透明派生指标和 Pareto 分析。
- 分页 JSON 导出包。
- 少量关键自动化测试。
- 数据来源、更新时间、新鲜度和错误状态。

### 明确不做

- Claude Code Status Line。
- 用户个人 Token、成本、上下文或额度。
- OpenTelemetry。
- Analytics Admin API。
- 后台 LaunchAgent、Daemon、Helper 或 IPC。
- 应用退出后的同步。
- 多来源统一排行榜。
- 跨来源模型映射。
- 跨来源趋势、综合评分或 Pareto。
- 动态插件系统。
- Provider 管理页面。
- Codex Radar UI 或 Adapter。
- 默认不透明综合总分。
- 完整 Canonical Model Catalog。
- 自动测评口径识别。
- 全量原始数据重放平台。
- Publication Manifest、Stage Dataset 或独立 Quarantine 数据库。
- 导出包导入、恢复、合并或应用内再处理。
- 完整 UI 自动化、截图回归、性能平台和故障注入框架。

---

# 2. 已冻结的架构决策

## ADR-001：产品是 Radar Viewer

应用只读取、展示、整理、缓存和分析第三方已发布信息，并允许用户导出本地副本；应用不自行运行或提交 Benchmark，不生成源数据，也不回写上游系统。

新增来源必须适配 Viewer 契约，而不是把执行、生产或管理能力带入 Radar。允许在同一应用中并列整合多个来源，但来源身份、测评口径、历史、派生指标和可比性边界必须保持可见。

## ADR-002：来源适配

所有远端实现遵守：

```swift
protocol RadarSource: Sendable {
    var descriptor: RadarSourceDescriptor { get }

    func fetchBenchmark() async throws -> BenchmarkDataset
    func fetchCommunity() async throws -> CommunityDataset?
    func fetchSourceStatus() async throws -> SourceStatusDataset?
}
```

MVP 仅实现 `ClaudeCodeRadarSource`。

## ADR-003：未来多来源采用独立工作区

后续 Codex Radar 复用工作区组件和存储结构，但不与 Claude 数据融合。

MVP UI 不显示来源切换器或 Codex 占位入口。

## ADR-004：来源作用域模型 ID

```swift
struct RadarSourceID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
}

struct ModelID: Hashable, Codable, Sendable {
    let sourceID: RadarSourceID
    let upstreamKey: String
}
```

优先使用上游稳定 ID。没有稳定 ID 时，对名称做保守规范化。真实改名发生后，才增加静态别名。

不建设全局模型身份注册表。

## ADR-005：不可变、内容去重的规范化历史

新内容产生新历史；重复内容不重复插入。

```text
sourceID + datasetType + contentFingerprint
```

构成主要去重依据。

## ADR-006：轻量测量序列版本

Adapter 维护：

```swift
let seriesRevision = "claude-radar-v1"
```

同一 revision 可以连线。发现上游测评口径显著变化时，人工改成 `v2`，新旧趋势断开。

不建设 Comparability Engine。

## ADR-007：分段 Last-Known-Good

仅有三个独立分段：

- `BenchmarkDataset`
- `CommunityDataset`
- `SourceStatusDataset`

新数据成功并通过校验时更新该分段；失败时保留最后良好值并记录错误。

模型质量和对应基准消耗必须作为同一个 `BenchmarkDataset` 更新。

## ADR-008：有限原始样本

长期保存规范化历史。

原始响应仅保留：

- 每个来源最近 3 个成功样本；
- 最近 30 天内最多 20 个失败样本。

不建设通用 Parser 重放平台。

## ADR-009：指标策略

提供：

- 来源原始指标；
- 公式透明的派生指标；
- 同来源、同 revision 内的 Pareto 分析。

不提供默认综合总分。

## ADR-010：应用生命周期

- 菜单栏进程存活时同步。
- 关闭 Dashboard 不停止同步。
- 用户明确退出后全部停止。
- 开机启动默认关闭，可在设置中显式启用。
- 不安装独立后台 Agent。

## ADR-011：在线来源发布边界

`ClaudeCodeRadarSource` 在开发阶段可标记为 experimental。

公开发布前必须确认第三方允许访问、合理缓存、历史留存和数据再展示；未确认时，公开构建默认关闭在线来源，不绕过任何访问控制。

## ADR-012：导出是单向能力

导出版本化分页 JSON 包。应用不重新导入、不恢复、不合并，也不负责数据再处理。

---

# 3. 推荐仓库结构

目标规模：约 30–45 个 Swift 文件，不建立多包微模块体系。

```text
ClaudeRadar/
├── ClaudeRadarApp.swift
├── App/
│   ├── AppEnvironment.swift
│   ├── AppCommands.swift
│   └── AppSettings.swift
├── Domain/
│   ├── RadarSourceID.swift
│   ├── ModelID.swift
│   ├── RadarSourceDescriptor.swift
│   ├── MetricValue.swift
│   ├── BenchmarkDataset.swift
│   ├── CommunityDataset.swift
│   ├── SourceStatusDataset.swift
│   ├── SegmentState.swift
│   └── DerivedMetrics.swift
├── Sources/
│   └── ClaudeCodeRadar/
│       ├── ClaudeCodeRadarSource.swift
│       ├── ClaudeRadarDTO.swift
│       ├── ClaudeRadarParser.swift
│       ├── ClaudeRadarValidator.swift
│       └── ClaudeRadarConfiguration.swift
├── Data/
│   ├── RadarRepository.swift
│   ├── SwiftDataModels.swift
│   ├── ContentFingerprint.swift
│   ├── RawSampleStore.swift
│   └── Export/
│       ├── RadarExportService.swift
│       ├── ExportManifest.swift
│       └── ExportPage.swift
├── Sync/
│   ├── RadarSyncCoordinator.swift
│   ├── SyncPolicy.swift
│   └── NetworkMonitor.swift
├── Features/
│   ├── MenuBar/
│   │   └── MenuBarView.swift
│   ├── Workspace/
│   │   ├── RadarWorkspaceView.swift
│   │   └── RadarWorkspaceModel.swift
│   ├── Overview/
│   │   └── OverviewView.swift
│   ├── Models/
│   │   ├── ModelListView.swift
│   │   └── ModelDetailView.swift
│   ├── Charts/
│   │   └── MetricTrendChart.swift
│   ├── SourceStatus/
│   │   └── SourceStatusView.swift
│   ├── Export/
│   │   └── ExportView.swift
│   └── Settings/
│       └── SettingsView.swift
├── Resources/
│   └── Fixtures/
│       ├── claude-radar-valid.json
│       ├── claude-radar-null-fields.json
│       └── claude-radar-invalid.json
└── ClaudeRadarTests/
    ├── ClaudeRadarParserTests.swift
    ├── RadarRepositoryTests.swift
    └── RadarExportServiceTests.swift
```

不要为了目录完全一致而创建空文件。只在实现需要时落盘。

---

# 4. 领域模型

## 4.1 来源描述

```swift
struct RadarSourceDescriptor: Sendable, Hashable {
    let id: RadarSourceID
    let displayName: String
    let supportLevel: SupportLevel
    let homepageURL: URL?
    let seriesRevision: String
}

enum SupportLevel: String, Codable, Sendable {
    case experimental
    case authorized
    case disabled
}
```

MVP：

```swift
extension RadarSourceID {
    static let claudeCodeRadar = Self(
        rawValue: "claude-code-radar"
    )
}
```

不要在 MVP 添加 `.codexRadar` 常量，直到第二个 Adapter 开发开始。

## 4.2 模型描述

```swift
struct ModelDescriptor: Identifiable, Hashable, Codable, Sendable {
    let id: ModelID
    let upstreamName: String
    let displayName: String
}
```

保守名称规范化只允许：

- trim；
- lowercased；
- 连续空白转 `-`；
- 删除不影响身份的首尾空白符号。

不要自动删除版本、日期、thinking、context 等语义后缀。

## 4.3 Benchmark 数据集

```swift
struct BenchmarkDataset: Hashable, Codable, Sendable {
    let sourceID: RadarSourceID
    let sourceUpdatedAt: Date?
    let fetchedAt: Date
    let benchmarkName: String?
    let benchmarkVersion: String?
    let seriesRevision: String
    let models: [ModelBenchmark]
}

struct ModelBenchmark: Identifiable, Hashable, Codable, Sendable {
    let id: ModelID
    let descriptor: ModelDescriptor

    let qualityScore: Decimal?
    let passedTasks: Int?
    let validTasks: Int?
    let invalidTasks: Int?

    let benchmarkCostUSD: Decimal?
    let inputTokens: Int64?
    let outputTokens: Int64?
    let cacheReadTokens: Int64?
    let cacheCreationTokens: Int64?
    let totalTokens: Int64?

    let elapsedSeconds: Double?
    let agentSteps: Int?
    let cacheHitPercent: Decimal?
}
```

只实现来源真实提供的字段。不存在的数据保持 `nil`，不得伪造或补零。

## 4.4 社区评分

```swift
struct CommunityDataset: Hashable, Codable, Sendable {
    let sourceID: RadarSourceID
    let sourceUpdatedAt: Date?
    let fetchedAt: Date
    let ratings: [CommunityRating]
}

struct CommunityRating: Identifiable, Hashable, Codable, Sendable {
    let id: ModelID
    let model: ModelDescriptor
    let average: Decimal?
    let voteCount: Int?
    let scaleMinimum: Decimal?
    let scaleMaximum: Decimal?
}
```

社区评分不参与 Benchmark 质量计算和 Pareto。

## 4.5 来源状态

```swift
struct SourceStatusDataset: Hashable, Codable, Sendable {
    let sourceID: RadarSourceID
    let sourceUpdatedAt: Date?
    let fetchedAt: Date
    let quotaEstimates: [SourceQuotaEstimate]
}

struct SourceQuotaEstimate: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let windowLabel: String
    let usedPercent: Decimal?
    let estimatedValueUSD: Decimal?
    let resetDescription: String?
}
```

UI 必须使用：

> Claude Code Radar 来源额度估算

不得使用：

> 我的额度、我的消费、剩余额度

## 4.6 分段状态

```swift
struct SegmentState<Value: Sendable>: Sendable {
    let value: Value?
    let lastSuccessfulAt: Date?
    let lastAttemptedAt: Date?
    let error: SegmentError?
    let isStale: Bool
}

struct SegmentError: Error, Hashable, Sendable {
    let kind: Kind
    let message: String

    enum Kind: String, Sendable {
        case network
        case http
        case decoding
        case validation
        case authorization
        case disabled
    }
}
```

不要建设全局 Publication 状态机。

---

# 5. 数据获取与解析

## 5.1 网络约束

使用 `URLSession`：

- 请求超时 15 秒；
- 资源超时 30 秒；
- 明确 `Accept: application/json`；
- 明确、诚实的 User-Agent；
- 支持 `ETag`、`Last-Modified`；
- 支持 `If-None-Match`、`If-Modified-Since`；
- 尊重 `Retry-After`；
- 响应体设置合理上限，例如 5 MB；
- 检查 MIME 和 HTTP 状态；
- 不保存 Cookie、Authorization 或其他敏感 Header；
- 不绕过 Cloudflare、验证码或鉴权。

候选端点必须集中放在 `ClaudeRadarConfiguration`，不得散落于 UI 或 Repository。

```swift
struct ClaudeRadarConfiguration: Sendable {
    let benchmarkURL: URL
    let communityURL: URL?
    let sourceStatusURL: URL?
}
```

若多个分段来自同一个 JSON，Source 内只请求一次并拆分，避免重复网络请求。

## 5.2 DTO 与领域模型隔离

DTO 只存在于：

```text
Sources/ClaudeCodeRadar/
```

其他模块不得引用 DTO。

流程：

```text
HTTP Data
→ DTO Decode
→ Normalize
→ Semantic Validate
→ Domain Dataset
```

## 5.3 校验范围

只实现必要校验：

- 模型名称非空；
- 百分比在合理范围内；
- Token、任务数、耗时和成本不得为负；
- `passedTasks <= validTasks`，若来源语义确实如此；
- Date 可解析或保持 `nil`；
- 至少存在一个可展示模型；
- 极端异常值拒绝更新，但阈值写成 Source 常量，便于调整。

校验失败时：

- 保存失败原始样本；
- 返回 `.validation` 错误；
- 不覆盖 Last-Known-Good。

不建设独立 Quarantine 表。

## 5.4 内容指纹

对规范化数据生成稳定指纹，而非直接依赖原始 JSON 字段顺序。

推荐：

```text
编码为 sortedKeys JSON
→ SHA-256
```

指纹不包含：

- `fetchedAt`；
- 请求耗时；
- 本机错误信息。

应包含：

- sourceID；
- seriesRevision；
- 实际领域数据；
- sourceUpdatedAt（仅在其变化具有数据语义时）。

---

# 6. 持久化

## 6.1 SwiftData 实体

保持最少实体数量：

```text
BenchmarkSnapshotEntity
CommunitySnapshotEntity
SourceStatusSnapshotEntity
RawSampleEntity
```

不为每个 Metric 建独立实体，避免 EAV 模型。

### BenchmarkSnapshotEntity 建议字段

```text
id: UUID
sourceID: String
contentFingerprint: String
sourceUpdatedAt: Date?
fetchedAt: Date
seriesRevision: String
encodedDataset: Data
```

`encodedDataset` 保存 Codable 领域数据。项目规模较小时，避免把每个可选指标拆成大量 SwiftData 列。

### 当前状态查询

每个分段的当前值：

```text
sourceID 相同
按 fetchedAt 降序
取最近成功快照
```

失败状态可保存在轻量设置或同步状态实体中，不需要创建完整事件仓库。

## 6.2 去重规则

插入前查询：

```text
sourceID + contentFingerprint
```

已存在：

- 不插入新快照；
- 更新内存中的 `lastAttemptedAt`；
- 不制造重复趋势点。

不存在：

- 插入不可变快照；
- 更新该分段 Last-Known-Good。

## 6.3 原始样本

保存目录：

```text
Application Support/ClaudeRadar/RawSamples/<sourceID>/
```

成功样本最多 3 个；失败样本最多 20 个且最多保留 30 天。

文件名：

```text
2026-07-14T18-30-00Z_success_<sha256-prefix>.json
2026-07-14T18-31-02Z_validation-failed_<sha256-prefix>.json
```

不要将原始响应存进 SwiftData，避免数据库膨胀。

---

# 7. 同步协调

## 7.1 单进程

只使用应用进程中的：

```swift
actor RadarSyncCoordinator
```

不创建 XPC、Helper、LaunchAgent 或后台服务。

## 7.2 触发条件

- 应用启动立即同步；
- 菜单栏驻留时默认每 30 分钟检查；
- 手动刷新；
- 网络恢复后，如距上次尝试超过最小间隔则刷新；
- 睡眠恢复后，如数据已过期则刷新；
- 用户退出后停止。

默认开机启动关闭。

## 7.3 并发去重

同一来源只允许一个进行中的同步：

```swift
private var activeTask: Task<Void, Never>?
```

手动刷新遇到活动任务时复用或等待，不启动第二次请求。

## 7.4 分段更新

```text
Benchmark 成功
→ 验证、去重、保存、更新 Benchmark LKG

Community 成功
→ 验证、去重、保存、更新 Community LKG

Source Status 成功
→ 验证、去重、保存、更新 Source Status LKG
```

三个分段互不阻塞。

若 Benchmark 的质量和消耗来自同一载荷，必须形成一个 Dataset 并一次性保存。

## 7.5 退避

简单退避即可：

```text
1 分钟
5 分钟
15 分钟
30 分钟
2 小时
最长 6 小时
```

有 `Retry-After` 时优先使用。

不建设通用 Scheduler Framework。

---

# 8. 派生指标与 Pareto

## 8.1 派生指标

仅在所需输入存在且分母大于 0 时计算：

```swift
costPerPassedTask = benchmarkCostUSD / passedTasks
tokensPerPassedTask = totalTokens / passedTasks
secondsPerPassedTask = elapsedSeconds / passedTasks
qualityPerDollar = qualityScore / benchmarkCostUSD
```

结果必须标注：

- 公式名称；
- 所需原始字段；
- 单位；
- 计算失败原因。

不把缺失值视为 0。

## 8.2 Pareto

MVP 支持当前 BenchmarkDataset 内的简单 Pareto。

建议预设视角：

```text
质量 ↑，成本 ↓
质量 ↑，耗时 ↓
质量 ↑，Token ↓
```

仅比较：

- 同一 `sourceID`；
- 同一 `seriesRevision`；
- 同一 BenchmarkDataset；
- 对应指标均非空。

社区评分和来源额度不参与。

UI 只标记：

```text
Pareto 前沿
被其他模型支配
数据不足
```

不提供默认总排名。

---

# 9. UI 信息架构

## 9.1 App Scene

```swift
MenuBarExtra
Window(id: "workspace")
Settings
```

关闭 Workspace 后应用继续驻留菜单栏。

## 9.2 菜单栏浮窗

目标宽度约 380–440 pt，展示：

- 标题和数据新鲜度；
- 最近一次 Benchmark 状态；
- 前 3 个模型的质量摘要；
- 来源额度估算简报；
- 同步错误提示；
- 手动刷新；
- 打开完整工作区；
- 退出。

不要在菜单栏塞完整趋势图和所有指标。

## 9.3 完整工作区

MVP 只有 Claude 工作区，不显示侧边栏来源切换。

推荐使用顶部 Tab 或 `NavigationSplitView` 的固定功能导航：

```text
概览
模型
趋势
来源状态
导出
```

### 概览

- 最近更新时间；
- 数据健康状态；
- 质量最高模型；
- 最佳成本效率；
- 质量—成本 Pareto 前沿；
- 来源额度估算。

### 模型

表格字段按数据可用性显示：

```text
模型
质量分
通过率
成本
Token
耗时
Agent Steps
Cache
社区评分
```

支持排序，但每个排序仅基于一个明确指标。

### 模型详情

- 原始指标；
- 派生指标；
- 单模型历史；
- 来源和口径；
- `seriesRevision` 边界。

### 趋势

- 指标选择；
- 模型多选；
- 时间范围；
- revision 变化时断线。

无需实现高级图表编辑器。

### 来源状态

明确标题：

> Claude Code Radar 来源状态

包含：

- 5h/7d 额度估算；
- 重置说明；
- 数据更新时间；
- 在线 Provider 支持级别；
- 最近错误；
- 数据源主页入口。

### 导出

允许选择：

- 日期范围；
- 数据集；
- 是否包含最近原始样本；
- 每页条数，默认 500，允许 100–5000。

导出完成后在 Finder 中显示文件。

## 9.4 状态文案

必须区分：

```text
刚刚同步成功
正在使用 3 小时前的最后良好数据
社区评分暂不可用
新数据未通过校验，已保留旧值
在线来源在当前构建中未启用
```

不要只显示模糊的“同步失败”。

---

# 10. 分页 JSON 导出

## 10.1 包结构

```text
ClaudeRadarExport-<timestamp>.zip
├── manifest.json
├── models/
│   └── page-000001.json
├── benchmark-runs/
│   ├── page-000001.json
│   └── ...
├── community-ratings/
│   └── page-000001.json
├── source-status/
│   └── page-000001.json
└── raw-samples/               # 用户显式选择时存在
```

## 10.2 Manifest

```json
{
  "format": "claude-radar-export",
  "formatVersion": 1,
  "exportedAt": "2026-07-14T18:30:00Z",
  "appVersion": "1.0.0",
  "pageSize": 500,
  "includesRawSamples": false,
  "sources": ["claude-code-radar"],
  "datasets": [
    {
      "name": "benchmark-runs",
      "schemaVersion": 1,
      "recordCount": 1842,
      "pageCount": 4
    }
  ]
}
```

## 10.3 Page Envelope

```json
{
  "dataset": "benchmark-runs",
  "schemaVersion": 1,
  "page": 1,
  "pageSize": 500,
  "recordCount": 500,
  "totalRecords": 1842,
  "hasNextPage": true,
  "records": []
}
```

## 10.4 规则

- UTF-8；
- ISO 8601 UTC；
- 缺失值使用 `null`；
- 金额使用十进制字符串，或采用经过测试的稳定 Decimal 编码；
- 排序固定为 `sourceUpdatedAt/fetchedAt` 升序，再按稳定 ID 升序；
- 文件名页码固定宽度；
- 导出字段与 SwiftData 内部结构解耦；
- 写入临时目录，全部成功后再压缩并移动到用户目标位置；
- 导出失败时删除临时目录；
- 不实现导入。

---

# 11. 设置

MVP 仅提供：

```text
刷新间隔：15 / 30 / 60 / 120 分钟
开机启动：关闭 / 开启
通知：关闭 / 开启
数据保留：规范化历史无限期或用户手动清除
清除历史数据
清除原始诊断样本
显示数据目录
关于与第三方声明
```

不要提供：

- 自定义 API；
- Provider 管理；
- 复杂阈值编辑器；
- 同步脚本；
- OTel 设置；
- 管理员密钥。

通知可以只实现：

- 新模型出现；
- Benchmark 数据长期过期；
- 新数据持续校验失败。

如通知实现影响排期，可延期到 MVP 后的小版本，不阻塞核心交付。

---

# 12. 测试边界

Codex 仅负责 MVP 的关键自动化测试。

## 12.1 Parser

必须测试：

- 正常 Fixture；
- 可选字段缺失；
- `null` 保持为 `nil`；
- 百分比单位正确；
- Decimal 金额正确；
- 明显负数或不合理数据被拒绝；
- 未知字段不导致失败。

## 12.2 Repository

必须测试：

- 相同内容指纹不重复插入；
- 新内容产生新历史；
- Benchmark 更新是整体的；
- 一个分段失败不影响其他分段；
- 失败保留 Last-Known-Good；
- 所有快照携带 `sourceID` 和 `seriesRevision`。

## 12.3 导出

必须测试：

- Manifest 记录数和页数；
- 零条记录；
- 刚好一页；
- 多一条跨页；
- 最后一页数量；
- 稳定排序；
- `null` 不变成 0；
- Decimal 编码不失真；
- 原始样本默认不包含。

## 12.4 构建与启动

- Debug 构建通过；
- 应用启动；
- Fixture 能渲染；
- 空状态不崩溃。

## 12.5 不测试

- Codex Radar；
- 多来源切换；
- 跨来源查询；
- 插件；
- 完整 UI 自动化；
- 截图回归；
- 长时间 Soak；
- 故障注入平台；
- 覆盖率门禁；
- 导入。

视觉、交互、文案和图表可读性由人工 Review。

---

# 13. 实施阶段

## Phase 0：仓库与契约探测

### 任务

- 建立或检查 macOS App 工程。
- 部署目标设为 macOS 26。
- 开启 Swift 6 严格并发。
- 创建 `docs/implementation-status.md`。
- 确认候选数据入口的响应结构、状态码、MIME、缓存 Header 和数据语义。
- 保存三份 Fixture：
  - 正常；
  - 缺失字段；
  - 明显异常。
- 记录第三方授权状态。

### 验收

- 工程可以编译启动；
- Fixture 已脱敏并入库；
- 未绕过访问控制；
- 数据字段映射记录在 `docs/source-contract.md`。

## Phase 1：领域模型和 Parser

### 任务

- 实现第 4 节模型；
- 实现 DTO；
- 实现 Parser 和 Validator；
- 实现来源作用域 ModelID；
- 实现 `seriesRevision`；
- 实现 Parser 测试。

### 验收

- 正常、null、异常 Fixture 测试通过；
- UI 和 Repository 不引用 DTO；
- 不存在 Canonical Identity Engine 或 Comparability Engine。

## Phase 2：Repository 和历史

### 任务

- 配置 SwiftData；
- 实现三个 Snapshot Entity；
- 实现内容指纹；
- 实现去重；
- 实现最近成功查询；
- 实现 RawSampleStore 清理；
- 实现 Repository 测试。

### 验收

- 重复同步不增加趋势点；
- 新数据可查询；
- 删除应用数据后可重新初始化；
- 原始样本符合数量和日期限制。

## Phase 3：同步

### 任务

- 实现 `ClaudeCodeRadarSource`；
- 实现条件请求和退避；
- 实现 `RadarSyncCoordinator`；
- 实现三个分段 LKG；
- 实现网络恢复和睡眠恢复触发；
- 将在线来源支持级别暴露给 UI。

### 验收

- 一个分段失败不阻塞另外两个；
- 同步并发去重；
- 失败不覆盖旧值；
- 退出应用后没有剩余后台进程。

## Phase 4：菜单栏和工作区

### 任务

- 实现 `MenuBarExtra`；
- 实现 `RadarWorkspaceView(sourceID:)`；
- 实现概览、模型、趋势、来源状态；
- 实现错误和陈旧状态；
- 实现基础排序和筛选。

### 验收

- MVP UI 只显示 Claude 工作区；
- 关闭窗口后菜单栏继续工作；
- UI 不出现“我的额度”等误导文案；
- revision 变化时趋势断开。

## Phase 5：派生指标和 Pareto

### 任务

- 实现四个透明派生指标；
- 实现三个 Pareto 视角；
- 在 UI 中显示公式或说明；
- 对缺失值显示“数据不足”。

### 验收

- 不存在默认综合总分；
- 社区评分不参与 Pareto；
- 不跨 revision 计算。

## Phase 6：分页 JSON 导出

### 任务

- 实现 Manifest；
- 实现分页写入；
- 实现 ZIP 包；
- 实现可选原始样本；
- 实现导出 UI；
- 实现导出测试。

### 验收

- 大量记录无需一次性编码为单个巨大数组；
- 包结构符合第 10 节；
- 导出失败不会留下半成品；
- 不存在导入入口。

## Phase 7：发布前收尾

### 任务

- 人工 Review UI、图表和文案；
- 完成第三方声明；
- 确认在线 Provider 授权状态；
- 清理 Debug 菜单和测试数据；
- Developer ID 签名和公证；
- 验证升级、卸载和数据清除。

### 验收

- 所有关键测试通过；
- 无个人用量或 OTel 相关代码；
- 无后台 Agent；
- 无未使用的平台化抽象；
- 若授权未确认，公开构建默认关闭在线 Provider。

---

# 14. Codex 变更约束

提交代码前检查：

```text
是否为 MVP 当前用户价值所必需？
是否已有明确的数据或 UI 使用方？
是否可以用简单值类型而不是框架解决？
是否正在为 Codex Radar 提前写不存在的功能？
是否引入了全局注册表、插件系统、事件总线或状态机？
是否让 DTO 泄漏到 UI？
是否把 null 变成了 0？
是否把来源额度写成了用户额度？
是否产生跨来源或跨 revision 比较？
是否增加了没有验收标准的抽象？
```

任何以下新增必须停止并说明理由：

```text
XPC
LaunchAgent
Daemon
Event Bus
Plugin Registry
Dependency Injection Container
Generic ETL Pipeline
Publication Manifest
Canonical Model Catalog
Comparability State Machine
Parser Replay Engine
Import Pipeline
Cross-source Merge Engine
```

---

# 15. Definition of Done

## 功能

- [ ] 菜单栏摘要正常。
- [ ] 完整工作区正常。
- [ ] 模型质量与基准消耗可查看。
- [ ] 社区评分可查看或明确显示不可用。
- [ ] 来源额度估算明确隔离。
- [ ] 历史趋势可查看。
- [ ] 派生指标公式透明。
- [ ] Pareto 标记正常。
- [ ] Last-Known-Good 正常。
- [ ] 分页 JSON 导出正常。

## 数据

- [ ] DTO 不泄漏到领域层外。
- [ ] `null` 未被转为 0。
- [ ] Decimal 未出现明显精度错误。
- [ ] 重复内容未重复插入。
- [ ] 每条数据带 `sourceID`。
- [ ] 每条趋势带 `seriesRevision`。
- [ ] 原始样本遵守保留上限。

## 范围

- [ ] 没有个人 Claude 使用数据。
- [ ] 没有 OTel。
- [ ] 没有 Analytics Admin API。
- [ ] 没有后台 Agent。
- [ ] 没有 Codex Radar 实现。
- [ ] 没有跨来源融合。
- [ ] 没有默认综合总分。
- [ ] 没有导入功能。
- [ ] 没有企业级发布流水线。

## 质量

- [ ] Parser 测试通过。
- [ ] Repository 测试通过。
- [ ] 导出测试通过。
- [ ] Debug 构建通过。
- [ ] Release 构建通过。
- [ ] 人工 UI Review 完成。
- [ ] 第三方使用边界已记录。

---

# 16. 实施状态模板

Codex 创建并持续更新：

`docs/implementation-status.md`

```markdown
# Implementation Status

## Current Phase
Phase X — Name

## Completed
- ...

## In Progress
- ...

## Blocked
- ...

## Decisions Made
- ...

## Tests
- Command:
- Result:

## Manual Review Needed
- ...

## Scope Guard
- Confirmed no out-of-scope features were added.
```

---

# 17. 最终交付物

```text
可构建的 Xcode 工程
Claude Code Radar Source Adapter
固定 Fixture
本地历史和趋势
菜单栏与完整工作区
分页 JSON 导出
三组关键自动化测试
第三方数据契约说明
实施状态文档
发布和人工验收清单
```

本蓝图是 MVP 的唯一实施基线。旧版完整开发文档仅作为历史讨论材料；发生冲突时，以本文件为准。
