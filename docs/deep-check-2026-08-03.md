# ClaudeRadar 深度检查报告

- **日期**：2026-08-03
- **分支**：`dev`（与 `origin/dev` 同步；工作区仅有 untracked `PRODUCT.md`）
- **范围**：`Sources/**`（~14.5k LOC，88 个编译模块）、`Tests/**`（~11.8k LOC，321 用例 / 41 suites）、`Config/ClaudeRadar-Info.plist`、`docs/**`、构建脚本、全部 fixture
- **方法**：6 个并行只读审查 agent（Data/Sync、Parsers、Domain、UI/App、Security、Tests）+ 基线构建验证。所有发现均引用真实代码（file:line），并经人工核对。

## 结论总览

| 层 | Blocker | Major/High | Minor/Med | 裁决 |
|---|---|---|---|---|
| D: UI/App | **1** | 3 | 12 | ⚠️ REQUEST CHANGES |
| A: Data/Sync | 0 | 2 | 16 | COMMENT |
| B: Parsers/Sources | 0 | 4 | 11 | COMMENT |
| C: Domain 数学 | 0 | 3 | ~8 | COMMENT |
| E: 安全（全库） | 0 | 2 | 5 | 风险 MEDIUM |
| F: 测试审计 | 0 | 2 真实问题 | 多 | 强，无假测试 |
| **合计** | **1** | **16** | **~52** | |

**总体判断**：高质量 Swift 6 代码库——actor 隔离、fail-closed 解析、LKG 恢复、321 个确定性测试、零第三方依赖、零硬编码密钥。**1 个数据丢失级 Blocker，16 个 Major 均为「潜伏缺陷 / 加固缺口」而非正在发作的 bug**。问题集中在两块：**Codex 渲染页面读取路径** 与 **三源共存的边界（隔离 / 保留 / 持久化）**。

---

## 基线验证

- ✅ `swift build`（Xcode 工具链，即 `Scripts/build-app.sh` 的标准路径）88 模块编译链接成功。
- ⚠️ **环境陷阱**：`xcode-select -p` 指向 `/Library/Developer/CommandLineTools`。裸 `swift build`（未设 `DEVELOPER_DIR`）会失败：`SwiftDataMacros` 插件找不到（`@Attribute(.unique)`）→ 级联 `Schema([Any])` 类型错误。**不是源码问题**，但任何忘设 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 的 CLI/CI 都会踩坑。建议 `sudo xcode-select -s /Applications/Xcode.app` 以消除该陷阱。

---

## 🔴 Blocker

### B1. 「设置 → 数据 → 清除规范化历史」清掉全部三个来源的持久化历史 + 同步元数据
- **位置**：`SettingsView.swift:29-30` → `RadarAppRuntime.swift:311` → `RadarRepository.swift:393-403`；`SwiftDataModels.swift`
- **置信度**：HIGH（代码事实）
- **问题**：`RadarRepository.deleteAll()` 删除 store 内**所有**来源的 `BenchmarkSnapshotEntity` / `CommunitySnapshotEntity` / `SourceStatusSnapshotEntity` / warning / IQ-history 实体 + `metadataStore.deleteAll()`，不按 `sourceID` 过滤。三个 runtime 各自打开指向**同一个** `dataRoot/Radar.store` 的 `ModelContainer`（`RadarAppRuntime.swift:121`），故任一来源的删除会抹掉其他两个来源的持久化数据。
- **触发**：设置 → 数据 → 「清除规范化历史」，此时选中任意来源。
- **后果**：按钮文案暗示只清当前工作区（"规范化历史…已清除"），实际清掉全部三个来源的历史与 LKG。兄弟 runtime 内存中继续显示数据，重启后 LKG 快照消失（直到下次联网）。直接违背产品承诺「各来源口径独立」。
- **修复**：按 `sourceID` 过滤删除（含按来源的 `SyncMetadataStore` 元数据）；或明确该按钮为全局，并通过 `RadarWorkspaceModel` 广播清空所有 runtime 的内存态。

---

## 🟠 Major（16）

### 主题 1：Codex 渲染页面读取路径（3）

**M1. IQ 历史读取把瞬时 hydration 态当成终态失败，24h 点击 fallback 救不回来**
- `CodexRenderedIQHistoryPageReader.swift:191-199,244` + `CodexRenderedIQHistoryDOMParser.swift:48-52` + `CodexRenderedIQHistoryPageReader.swift:103-114`
- 抽取脚本在 `aria-pressed != 24h` 时点击 24h 按钮，但 `selectedRange` 在同一趟同步计算；DOM 解析器把非 `"24h"` 一律当终态 `invalidSelectedRange`；stabilizer 只对 `.contentPending` 轮询，其他解析错误 `isComplete = true; .failure(...)`。若站点默认非 24h 高亮（fixture 恰模拟 48h）或 range bar 未 hydration，读取终态失败。修复：把 range/root 瞬时态当可 poll 态，或让 stabilizer 对 `invalidSelectedRange`/`missingRoot` 重试至总期限。

**M2. 任何 iframe/子框架导航终结整次读取**
- `CodexRenderedPageLifecycle.swift:273-316`
- `decidePolicyForNavigationAction` 要求 `isMainFrame == true`、response 要求 `isForMainFrame`；任何非主框架加载（广告/嵌入/tracker iframe）→ `fail(.navigationDenied)` → 整个观察失败。修复：非主框架导航静默 `.cancel` 而不 fail，仅主框架违规才失败。

**M3. 警告解析对 explicit-empty 态仍强制 grid/liveTime 元素**
- `CodexRenderedWarningDOMParser.swift:50-58`
- 守卫先于 `pageState` 分支执行；显式空页若省略 grid 元素或无 live-time 元素 → `missingGrid`/`missingLiveTime` 而非成功空快照。与抽取脚本自身的 empty 定义（`CodexRenderedWarningPageReader.swift:238-244`）不一致。修复：empty 态只要求 `rootPresent` + 有效 `sourceTimeLabel`。

### 主题 2：新鲜度承诺两处漏洞（2）

**M4. 无上游时间戳新鲜度门槛，stale 200 被呈现为新鲜**
- `ClaudeRadarParser.swift:83`、`CodexRadarParser.swift:70`、`RadarSyncCoordinator.swift:275-284`
- 新鲜度仅由本地 `lastSuccessfulAt` 推导，不看上游 `updated_at`。CDN 返回 7 天旧缓存的 200（`s-maxage=604800`，见 `docs/source-contract.md:100`）会被接受、持久化、UI 翻转成「新鲜」；未来时间戳同样接受。`ClaudeRadarValidator` 无任何时间戳边界校验。与「无效/过期数据绝不呈现为新鲜」的硬承诺冲突。修复：持久化成功前拒绝/降级过旧（或超容差未来）的 `sourceUpdatedAt`，或 `isStale` 由 `max(lastSuccessfulAt, sourceUpdatedAt + tolerance)` 推导。

**M5. 无-LKG 的错误被渲染成通用空态**
- `ModelListView.swift:61`、`MetricTrendChart.swift:29-33`、`OverviewView.swift:855-862`（DecisionLens）
- 这些路由只判 `projection.rows.isEmpty` → "暂无数据"/`ContentUnavailableView.search`。当 benchmark 段为 `.error` 或 `.validationFailed(hasLastKnownGood: false)`（验证失败且无缓存——恰是「无效数据不呈现」场景），用户看到无害空态、无解释、无「查看来源状态」入口。Overview 与 Codex 中心已正确使用 `StateBanner`（`CodexIntelligenceCenterView.swift:14-23`）。修复：这些路由在空表/图表前渲染 `StateBanner(healthState)`，空态仅留给真正的 `.empty`/`.loading`。

### 主题 3：三源共存边界 / 并发（3 + 1 低置信 HIGH）

**M6. 手动刷新加入「被退避跳过」的周期刷新时被静默丢弃**
- `CodexRenderedWarningCoordinator.swift:51-73` / `CodexRenderedIQHistoryCoordinator.swift:51-73`
- join 路径 `if let activeTask { activeTrigger = strongest(...); await activeTask.value; return }` 只升级 trigger，不重估 eligibility、不重跑。运行中任务可能因 `isEligible(.periodic)` 为 false（退避）已提前返回，手动调用者随之返回、什么都没做。主 `RadarSyncCoordinator.swift:92-100` 有残差 eligibility 重跑逻辑并有测试（`lateManualJoinRetriesSkippedEndpointGroup`），Codex 协调器无。触发：用户刷新落在 30 分钟退避窗口内 → Codex 段静默 no-op。修复：join 后若合并 trigger 为 `.manual`，重算 eligibility 并带残差重跑。

**M7. 改刷新间隔只作用于当前选中来源的 runtime**
- `SettingsView.swift:11,60-63`；`RadarAppRuntime.swift:298-304`
- `SettingsView.runtime` 是 `model.runtime`（选中来源），picker setter 只更新该 runtime。切到其他来源后，菜单栏「自动刷新 每 X 分钟」、Overview 监控卡、Settings picker 全显示新值，但实际仍走旧节奏，重启才自愈（间隔在 `ClaudeRadarApp.init` 从 `UserDefaults` 读取）。修复：`RadarWorkspaceModel.updateRefreshInterval(minutes:)` 广播到所有 `runtimes.values`。

**M8.（低置信 HIGH）三 runtime 共享一个 store 文件的跨源写竞态**
- 每个 runtime 独立 `RadarRepository`/`ModelContext` 但同一 `Radar.store`；export lease 不跨 repository 共享。两 runtime 同时持久化可能产生保存冲突或快照陈旧。受 `waitForExportLease`（每 repository）缓解但不跨 repository。需压测。

### 主题 4：Domain 数学正确性（3）

**M9. 基线冲突守卫作用域过宽，窗口外重复也清空基线**
- `CodexHistoryComparison.swift:105-106`
- 具体输入：`current`@T IQ100（r1）；历史含 `{T−25h, IQ90}`、`{T−2h, IQ100}`、`{T−2h, IQ101}`；基线 `.hours24` → cutoff T−24h。当前输出 `baseline = nil`（T−2h 对解析为 `.conflict` 触发 line 105 guard）；期望 `baseline = 90`（T−25h 组干净且在窗口内）。后果：历史中任何重复（哪怕距 now 30 分钟）都会让「变化」列假显示"不可用"。修复：把 `.conflict` 拒绝限定到候选组（`date ≤ cutoff && cutoff - date ≤ tolerance`），或把冲突组当非候选而非毒化整体结果。

**M10. IQ 历史按 (family, effort, seriesRevision) 聚合但不带 model id，不同型号被并成一条线**
- `CodexIQHistoryAnalytics.swift:48-58`
- 同快照含 `gpt-5.6-sol-max`(IQ98) 与另一 Sol/max SKU(IQ88) → 该日 `resolve([98,88])` → `.conflict` → 静默缺口；不同日期只出现其一 → 单条线混拼两个型号的 IQ。IQ 趋势是产品核心「是否退化」信号。修复：观察键加入 `model.id`，每坐标选确定性代表，或每 model id 一条线。

**M11. 效率矩阵去重保留字典序首个型号，可能是更弱那个**
- `CodexEfficiencyAnalytics.swift:39-42 (+59-69)`
- 测试自带例子：Sol/high 有 91.25 与 99 两个型号，矩阵保留 91.25 丢弃 99。智能中心显示「Sol/high IQ 91.25」，而成本散点与场景推荐都显示 99——同一坐标三个面板三个代表，且代表可能低估 IQ。修复：按坐标分组后选显示轴上最优（确定性），`upstreamKey` 仅作最终 tie-break。

### 主题 5：安全加固（2）

**M12. App 未沙箱化却渲染远端网页内容（WKWebView + evaluateJavaScript）**
- `Scripts/build-app.sh:60`；`Config/ClaudeRadar-Info.plist`（无 `com.apple.security.app-sandbox`）；仓库无任何 `.entitlements`
- 加载 `https://codexradar.com/` 与 `https://deng.codexradar.com/` 到 JS 启用的 `WKWebView`（`CodexRenderedPageLifecycle.swift:147`）并执行 DOM 抽取脚本。WebKit WebContent 进程有沙箱，但**宿主 app 进程无沙箱**——逃逸后落在可全权访问用户账户（文件/钥匙串/其他 app 数据）的进程。`--options runtime`（hardened runtime）提供部分保护但不提供隔离。修复：加 entitlements（`app-sandbox` + `network.client` + `files.user-selected.read-write`）并用其签名；外部发行应换 Developer ID + 公证。

**M13. WebKit 子资源/脚本自由，无 CSP、无用户控制**
- `CodexRenderedPageLifecycle.swift:85-90`
- 文档已披露「页面可自行执行 JS 与子资源请求」（`docs/source-contract.md:232,244`），但第三方 CDN/tracker 可见用户 IP/UA 且无 app 内披露/关闭；被攻破的第三方脚本可 DOM-clobber 抽取输入，数据完整性仅靠下游严格校验兜底。修复：app 内披露边界（`SettingsView.swift:47` 已部分披露）；考虑 `contentRuleLists`/CSP 注入；根治靠 M12 沙箱。

---

## 🟡 Medium / Minor（按层）

### A: Data/Sync（7 Med + 9 Low，要点）
- **无超时的 `SystemZipArchiver`**：挂死 `zip` 永不 resume → export lease 无限持有、阻塞所有 sync 写入（`RadarExportService.swift:230-258`）；`kill(processID, SIGKILL)` 有 PID 复用竞态。
- **`recordFailure` 无条件覆盖 `Retry-After`**：无该头的后续失败抹掉服务端背压期限（`RadarRepository.swift:335-348`）。
- **规范化历史无保留上限**：benchmark/community/sourceStatus 永不剪枝；渲染段 256 上限**按 revision**，老 revision 不清（`RadarRepository.swift:21-88` vs `566-616`）。
- **manifest `dateRange` 用未限定 `request.range`**，可能夸大导出区间（`RadarExportService.swift:173-183`）。
- **`.models` 导出数据集语义误导**：一个快照一条记录（含整个 models 数组），而非每模型一条（`RadarRepositoryExport.swift:22-23,190-202`）。
- **join 后缺 `Task.checkCancellation()`**：取消的调用者继续走残差手动刷新，多一次网络往返（`RadarSyncCoordinator.swift:87-101`）。
- **`.success(nil)` 社区拉取**：既不记成功也不清失败，退避被错误延长（`RadarSyncPersistence.swift:30-45`）。
- **全精度 vs ms 截断日期比较**：`verified*` 用解码后 ms 截断日期比对全精度存储日期，未来亚毫秒/带小数秒时间戳会让 LKG 验证失败（`RadarRepository.swift:440-467`）。
- Low：`RawSampleStore.flush()` 空 no-op 死 API；export 物化最多 ~115MB 内存；`createDirectory` 副作用创建目标父目录；`SyncMetadataStore` 把任意 I/O 错误当"corrupted"并清空；`repairChronology` 每次 init 全表扫；`ContentFingerprint` 排序非严格弱序（同 ModelID 时不稳定）；实体便捷构造器与 insert 逻辑双源真相；`RadarSyncPersistencePipeline.persist()` 不检查 `Task.isCancelled`（有意为之，需注释防误改）；`deleteAll` 与 `clearRawSamples` 双调用点需同步。

### B: Parsers/Sources（11 Minor，要点）
- `Math.abs` 把上升误记为 drop（`CodexRenderedWarningPageReader.swift:209`）。
- `seriesKey` 用未归一化 `data-model`，含空格的型号令整快照失败（`CodexRenderedIQHistoryPageReader.swift:235`）。
- 小数秒 `latest_at` 使 `parseDate` 返回 nil → 段验证失败（`ClaudeRadarParser.swift:139-161,229-232`；`CodexRadarParser.swift:187-192` 已容错）。
- Codex `modelKey` 不归一化，大小写/空格漂移产生重复历史身份（`CodexRadarParser.swift:178-185`）。
- `cancelAll()` 永久杀灭 transport（`HTTPTransport.swift:69-71`）。
- 原始采样持久化未脱敏的响应 body（无 header，但有被回显凭据类文本风险）。
- warning reader `handle` 缺 generation 守卫（`CodexRenderedWarningPageReader.swift:379-390`）。
- 空 labels 可让仅含标量 score 的模型通过验证（`ClaudeRadarParser.swift:77-80,97-136`）。
- 空 tier 产生退化配额估算 id（`CodexRadarParser.swift:94-103`）。
- `RadarDecimal` 拒绝带空白/本地化格式字符串（`RadarSourceDTO.swift:12-18`）。
- empty-state 正则可能对卡片文本误报（`CodexRenderedWarningPageReader.swift:240-241`）。

### C: Domain（~8 Minor）
- `DerivedMetrics.swift:90-97` 非有限 `elapsedSeconds` → "缺少必需字段：" 空列表；`:102` 负成本误报 `.zeroDenominator`。
- `RadarModelIdentity.familySummaries` 相等 IQ 无全序 tie-break，依赖输入顺序（`RadarModelIdentity.swift:34-36`）；`family()` 对非规范模型的不对称剥离（`:7-17`）。
- `CodexScenarioRecommendations` 四组场景 raw/rounded 混合口径（`:91-93`）。
- 单快照内重复型号不冲突检测（`CodexHistoryComparison.swift:122-125` 等）。
- 死代码/重复：`MetricValue.swift` 空文件应删除；`.missing/.value/.conflict` 枚举三分裂（HistoryComparison / IQHistoryAnalytics / RadarDeclineAnalysis）；`semanticTime`/`baselineTolerance=6h` 重复。
- 「本地 IQ 拟合」实为插值折线，无拟合/24h 投影（`OverviewView.swift:356-395`）——要么实现要么改名。

### D: UI/App（12 Minor，要点）
- 配额卡片与订阅 Picker 永不匹配（fixture "5h"/"7d" vs "5x Pro"）（`OverviewView.swift:818-822,631-647`）。
- ⌘R 只刷选中来源，信息总览工具栏刷全部——同一视觉不同行为（`AppCommands.swift:15-16` vs `RadarWorkspaceView.swift:169-175`）。
- `MenuBarLaunchLabel` `.task` 可被系统重建而重开已关闭窗口（`ClaudeRadarApp.swift:92`）。
- 概览 `Dictionary(uniqueKeysWithValues:)` 遇重复 model id 会 trap（`OverviewView.swift:1030`）；`CodexEfficiencyAnalytics.swift:65-66` force-unwrap。
- 硬编码颜色与 `palette` 语义 token 混用（`OverviewView.swift:147-154,1090-1096,685`）。
- 启动失败为终态，无重试路径（`RadarAppRuntime.swift:281-283,73`）。
- SWE-bench `LabeledContent("成本 / 解决任务", value: "benchmarkCostUSD / resolvedTasks")` 显示字面公式串（`SWEBenchLeaderboardView.swift:369`）。
- 官方 IQ Picker 选择在快照丢弃型号后悬空（`OverviewView.swift:12,188-199,312-321`）。
- 死代码：`WorkspaceCopy.sourceStatusTitle/quotaTitle/exportPlaceholder`（`RadarWorkspaceModel.swift:100-112`）、`AppSettings.publicOnlineAccessEnabled`（`:38`）从未写入。
- `MetricTrendChart.swift:35` 数百行 toggle 全量 eager 创建，应 `LazyHStack`。
- 「关闭工作区」关闭的是当前 key window（`AppCommands.swift:18-21`）；⌘O/⌘R 跨两个 scene 重复注册。

### E: Security（5 Minor）
- 本地数据文件 0644 世界可读（`RawSampleStore.swift:53`、`SyncMetadataStore.swift:87`、`RadarExportService.swift:167,184`、`AppEnvironment.swift:27`）。
- HTTP 派生历史无保留上限（同 A 项）。
- JSON 适配器字符串长度无上限（`ClaudeRadarValidator.swift:14-56`、`CodexRadarParser.swift:178-185` 等）。
- Release 描述符 `.disabled` vs 环境 `.authorized` 矛盾（`ClaudeCodeRadarSource.swift:263-275` vs `AppEnvironment.swift:64-68`）。
- `codesign --deep` 反模式 + ad-hoc 签名、无公证（`Scripts/build-app.sh:60`、`README.md:46`）。

---

## 测试套件（F）

321 用例 / 41 suites（Swift Testing）。**无假测试**：无 `test.skip`/`.only`/占位/`XCTAssertTrue(true)`。fixture 经 `#filePath` 读取，故 `Package.swift` 对 `Fixtures/CodexRenderedWarning|IQHistory` 的 exclude 无害，且 `CodexRenderedIQHistorySourceContractTests.swift:92-97` 用 `SHA256SUMS` 冻结其存在。

**真问题（2）**：
1. `Phase0SmokeTests.swift:44-45` 用 `try` 读取 gitignored 且 untracked 的 `.codex/environments/environment.toml` → **干净检出/CI 必挂**（本机侥幸通过因文件恰好存在）。修复：`.codex` 断言前加 `fileExists`。
2. `RadarExportServiceTests.swift:670` `throws: (any Error).self` 匹配任意错误，导出完整性路径未被钉住。修复：断言具体类型（`RepositoryIntegrityError`，见 `RadarRepositoryTests.swift:149`）。

**覆盖缺口（优先）**：
- `ClaudeRadarValidator`（92 行）全部边界常量（500 模型 / 10M 任务 / 1M 成本 / 100k 小时 / 10k 质量分 / 1B 投票 / token 上限）无直接单测。
- 新分析面板 formatter（`不可用`/货币/分钟路径）无单测（`CodexCostVersusIQPanel.swift:146`、`CodexEfficiencyMatrixPanel.swift:105-141`、`CodexScenarioRecommendationsPanel.swift:89-100`、`CodexIQHistoryPanel.swift:217-221`）。
- `CodexIQHistoryAxisPolicy.projection` 的 nil-domain / 零时长分支、`label(for:)` 未知日期路径。
- `RadarFormatters` 的 `decimal/integer/seconds/date`。
- M1（IQ hydration 首 poll 48h/null 应重试而非终态）无 stabilizer 驱动测试。
- Codex 协调器 manual-join-into-backoff 无测试（对应 M6）。
- 子毫秒时间戳 round-trip（对应全精度/ms 截断问题）。

**闪断风险**：
- `CodexRenderedIQHistoryPageReaderTests.swift:86` 与 `CodexRenderedWarningPageReaderTests.swift:135-184` 用固定 300ms 真实 sleep 的未 gated WebKit 测试，慢渲染/无头 CI 最易闪断。
- `CodexHistoryComparisonTests.swift:195-196` 断言 `"96.0"`/`"+6.0"`，在逗号小数分隔 locale（de_DE/fr_FR）下失败——locale 敏感。
- `RadarLifecycleRaceTests` 的 `while { await Task.yield() }` 忙等理论上有界但属协作式（实际确定性良好）。

**Minor**：`RadarLifecycleRaceTests.swift:114-146,200-227` 临时数据根无 `defer` 清理；`ReleaseReadinessTests.swift:37` 等脆字符串计数断言；测试 helper 里 force-unwrap 崩溃而非干净失败；`independentClearOperations` 一个 `@Test` 塞两个行为；`RadarRepositoryTests.swift:270-297` 从单测写入 `.omo/evidence/`；`CodexAnalyticsPanelsContractTests.swift:66-75` 负面文本扫描过于脆弱；`docs/implementation-status.md` 声称 "133 tests/16 suites" 实际 321/41（过期）；fixture `try!` 缺失时崩溃而非诊断。

---

## 安全（E）

**无 CRITICAL**，风险 MEDIUM。密钥扫描（含 git 历史、全部 fixture、plist、脚本）：**零硬编码密钥**，无需轮换。无 SQL/命令/AppleScript/`system()` 注入；无存储/反射 XSS（纯 SwiftUI `Text`，无 `AttributedString(markdown:)`，远端错误串先剥 HTML 再显示）；无 SSRF（URL 全为冻结 `https://` 常量 + 同源重定向并剥离 `Authorization`/`Cookie`）；无凭证（app 不携带任何凭据）；无无限解析（响应体硬上限 5MB/16MB）。

**已验证的 13 条承诺**（全部有代码证据）：
1. 非持久 WebKit（`CodexRenderedPageLifecycle.swift:87` `websiteDataStore = .nonPersistent()`）。
2. 请求无 Cookie/凭据（`HTTPTransport.swift:40-43`；重定向剥离）。
3. 渲染 reader 只持久化有界规范化字段，永不存 HTML/脚本/Cookie/响应体（16KB/64KB 桥上限）。
4. HTTP + WebKit 双重同源 HTTPS 重定向遏制。
5. 响应体大小上限流式 + 校验双重执行。
6. 原始采样保留上限（3 成功 + 20 失败 / 30 天）。
7. 数据在 app 删除后仍存于 `~/Library/Application Support/ClaudeRadar`（文档化行为）。
8. 历史/原始采样独立清除操作。
9. Release 包排除 fixture/Debug 资源（构建失败而非绕过）。
10. 从不调用受保护/需凭证 API。
11. 导出目标校验（`.zip`、拒路径分隔符/符号链接）。
12. fixture 消毒 + SHA-256 冻结。
13. 零第三方依赖，最小供应链面。

**密钥扫描命中均为良性**：测试用 `Bearer must-not-persist` / `Set-Cookie: secret=value`（断言不持久化）、forbidden 子串断言列表、文档 prose、GPL 文本、fixture 的 `*_tokens`（token 计数指标）、`Config/ClaudeRadar-Info.plist`/脚本/生产 fixture 无匹配。

---

## 亮点（各层共性）

1. **LKG 状态机**：`state()`（`RadarWorkspaceModel.swift:823-838`）与 `benchmarkPresentation`（`:506-520`）清晰区分 fresh/stale/LKG/validationFailed/disabled/error；analytics 一律 gated on `.fresh`（`:570-579`），绝不用陈旧数据算信号。
2. **Codex 智能中心路由隔离三层强制**：`WorkspaceRoute.init(storageKey:)` 拒非 Codex 键（`:90-97`）+ `destinations(for:)` 不产生（`:932-942`）+ DEBUG 覆写不可绕过，并有专门测试。
3. **Actor 隔离完整**：repository/metadata/raw-store/export/coordinator 全为 actor，`ModelContext` 不逃逸，回调 `@Sendable`，去重 check+insert actor 内原子。
4. **Fail-closed 解析**：任何错位（重复身份、乱序点、越界 IQ、未知指标种类）整段拒绝，坏卡片连坐，无部分快照逃逸。
5. **确定性**：所有返回列表全序（display name → `upstreamKey`），输入顺序无关性显式测试；`SemanticFingerprint` `.sortedKeys`+SHA-256；时间注入全链路（`RadarClock`/`IQTestClock`/`DeterministicHarness`）。
6. **对抗性测试纪律**：DOM fixture 原地变异（`1e999`、65 字符名、`"\n"` 标签、33 字符 token、25 点序列），`SHA256SUMS` 冻结；生产 WebKit 边界以源码文本断言（无 `fetch(`/`XHR`/`outerHTML`/`webkit.messageHandlers`）。
7. **数学保守**：无隐式零——缺失显式建模（`nil`/`.dataInsufficient`/`.missingRequiredFields`/`.zeroDenominator`/冲突缺口），除零全部守卫，非有限值过滤。
8. **导出 lease 设计正确**：一致时间点快照、`shortPage` 守卫、原子安装、失败/取消清理、字节级确定复现。
9. **可访问性纪律**：每图表有 `accessibilityRepresentation`，稳定标识符，`RadarStyle` 尊重 increased-contrast 且冻结测试值。

---

## 建议修复顺序

1. **B1 Blocker**：`clearHistory` 按来源隔离（数据丢失，最优先）。
2. **M12/M13 安全**：沙箱 entitlements + 签名；子资源 CSP/拦截（外部分发前）。
3. **M4/M5 新鲜度承诺**：上游时间戳门槛 + 无-LKG 错误态渲染。
4. **M1/M2/M3 Codex 渲染读取**：hydration 可重试、iframe 不终结、empty 态守卫。
5. **M6/M7 + zip 超时**：Codex 协调器手动 join 残差重跑；`SystemZipArchiver` 看门狗。
6. **保留上限**：规范化表按来源设上限、跨 revision 清理。
7. **M9/M10/M11 Domain**：基线冲突作用域、IQ 历史按 model 聚合、矩阵代表型号选择。
8. **M7/D 性能**：`ModelListView` Pareto 记忆化（照抄 `SWEBenchLeaderboardView.swift:279-286`）、间隔广播。
9. **测试**：修 `Phase0SmokeTests` 的 `.codex` 依赖、收紧 `RadarExportServiceTests:670`、补 validator 边界 + formatter 单测、gated 真实 WebKit sleep。
10. **环境**：`sudo xcode-select -s /Applications/Xcode.app`，消除裸 `swift build` 陷阱。

---

*本报告由 6 个并行只读审查 agent 产出并人工合成；全部 file:line 引用经代码核对。*
