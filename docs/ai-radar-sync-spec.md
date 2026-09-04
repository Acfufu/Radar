# AI Radar 全量同步重构 Spec

- 状态：**定稿 v1.0**（经 R1–R5 共 5 轮双审，10 次独立审阅，全部发现已闭环）
- 日期：2026-09-04
- 上游快照：codexradar.com（2026-09-04 抓取；页面为动态服务端渲染，字节数随内容波动，实测约 680KB）
- 决策人已确认：① 范围全量（P0–P3 + 重命名）② 架构可重议（对齐上游站点模型）③ 产品定名 **AI Radar**（中文界面「AI 雷达」；用户原话「AI Rader」为笔误，已更正）
- 本文件即终版落盘：`docs/ai-radar-sync-spec.md`

---

## 1. 背景

本项目（原 Claude Radar）是 macOS 26+ / Swift 6.2 原生菜单栏 + 工作台 app，读取三个公开模型基准源（Claude Code Radar、Codex Radar、SWE-bench Verified），三房间隔离，无统一排名。设计系统冻结在 2026-07-25 的 claudecoderadar.com 旧版视觉（`docs/design-qa.md`）。

上游 codexradar.com 已多次迭代：品牌改为「AI 雷达」，客户端多站点切换（aggregate/codex/dsh/zcode/grok/kimi 预告），视觉体系全面改版，`current.json` 升至 schema 2.0 并新增多个结构化端点。本 spec 定义将上述迭代同步进本项目的完整重构。

### 1.1 上游调研结论（2026-09-04 实测）

**品牌/架构**
- 站点切换器：aggregate（聚合站 预览）/ codex（当前）/ dsh（预览）/ zcode（预览）/ grok（预览）+ kimi「近期开放」占位；导航为 `./?station=X` 链接 + `data-station` 属性（导航项 5 处，共 29 处 data-station 标记），纯客户端切换
- **非 Codex 站目前无独立内容与数据端点**（`current.json?station=grok|zcode|dsh` 均忽略参数返回同一 Codex 数据；`?station=aggregate` 页面与首页字节级相同）——多站点是前瞻脚手架
- 页面为单份 HTML（2026-09-04 实测 679,867B，动态波动），全部样式内联，无外部 CSS/JS 资源（仅 Cloudflare beacon）

**视觉 token（内联 CSS 提取，:root 默认 / [data-theme=light] / [data-theme=dark] 三套）**

| Token | 默认(:root，light 语义) | light | dark |
|---|---|---|---|
| --bg | #f3f6f9 | #edf4ff | #0d1420 |
| --panel | #ffffff | rgba(255,255,255,.90) | #111827 |
| --panel-soft | #f8fafc | rgba(242,247,255,.92) | #172033 |
| --ink | #17202b | #12213b | #e5edf7 |
| --muted | #667085 | #53647e | #a7b2c3 |
| --soft | #8a94a6 | #71809a | #8794a8 |
| --line | #dce3ed | rgba(111,137,177,.25) | #263449 |
| --line-strong | #cbd5e1 | rgba(78,111,163,.38) | #35465f |
| --green | #13865d | #047857 | #34d399 |
| --green-soft | #e2f4ec | rgba(5,150,105,.12) | rgba(16,185,129,.16) |
| --amber | #a86600 | #b45309 | #fbbf24 |
| --amber-soft | #fff0d0 | rgba(245,158,11,.13) | rgba(251,191,36,.14) |
| --blue | #2d65c8 | #245fc5 | #93c5fd |
| --blue-soft | #e7efff | rgba(37,99,235,.11) | rgba(96,165,250,.16) |
| --red | #c0392b | #be3144 | #f87171 |
| --red-soft | #ffe8e5 | rgba(225,29,72,.10) | rgba(248,113,113,.16) |
| --shadow | 0 18px 44px rgba(31,43,59,.08) | 0 22px 60px rgba(40,72,122,.13) | 0 18px 44px rgba(0,0,0,.34) |

- 补充色：--green-dark #0f684e/#065f46/#6ee7b7；站长推荐绿 #22c55e、降智预警琥珀 #f59e0b（--insight-color 局部变量）
- 几何：主面板圆角 15px、卡片 7–11px、胶囊 999px；卡片 = 1px var(--line) 边框 + 大柔影 + `color-mix` 染色变体；强调卡为左缘 5px 色条（station-rec / degradation-card）
- 字体：声明 `Inter, ui-sans-serif, system-ui, -apple-system, ...`，无 webfont 加载，macOS 实际回退系统字体；h1 26px / weight 780；字号密度 8–34px；等宽用 ui-monospace
- 组件版图（页面顺序）：site-announcement（深色渐变横幅）→ station-preview（双面板速览排行）→ community-knowledge（知识文章卡）→ 站长推荐 + 降智预警（radar-insights-panel）→ intelligence-efficiency（效能 PK + 详情面板）→ quota-radar → fast-radar（+ history）→ intelligence-efficiency-history → desktop-tibo-radar → ai-radar-community（action-hub，二维码）→ footer

**数据契约**
- `current.json` schema **2.0**，顶层键全集：`schema_version/service/type/monitored_at/timezone/window_open/status/recommended_action/window/prediction/tibo_presence/links/api_access/model_iq`
  - 新增顶层结构：`window`（**9 键**：open/status/action/message/title/scope/opened_at/closed_at/source_url）、`prediction`（level/probability_24h/probability_48h/summary/summary_en/updated_at）、`tibo_presence`（17 键，含 `safety_note_en`/`safety_note_zh` 两个本地化键——无裸 `safety_note` 键）、`links`（html/rss/full_api）、`api_access`（status/full_api_status/message_zh/message_en/contact/requirements；requirements 含 `attribution_required=true` 与署名原串「数据来自 Codex 雷达 codexradar.com」）
  - `model_iq` 保留 `{latest,comparisons,quota_radar}` 核心并新增：`recent_days`（latest + 11 个 comparisons 各 10 天）、`data_source`（溯源：type/url/selection/checked_at/valid_cells/model_task_counts）、`quota_calibration`（schema_version/date/source/status/primary_window/calibration_policy/global_concurrency/cost 字段/windows.primary_5h/secondary_7d）、`quota_check`（plan_type/rate_limit_reset_credits_available_count/limit_reached/allowed/windows）、`quota_radar.trend`（10 条：five_h_20x/five_h_5x/five_h_plus/rate/offset）
  - Run 级新增：`wall_time_human/average_cost_usd/average_task_seconds/average_task_time_human/cost_usd_basis`
  - 模型换代：comparisons 11 键（gpt_56_sol_xhigh/high/medium/low、gpt_56_terra_max/xhigh_distributed/high、gpt_56_luna_max/high、gpt_55_xhigh_distributed/high_distributed）
- 新端点 `/data/intelligence-efficiency.json`（**实测 4.07MB**，history 249 条、runs_total 42646，持续增长）：顶层 15 键 `schema/mode/type/source/metrics_source/source_updated_at/models/runs_24h_total/runs_48h_total/runs_total/points/history/fingerprint/activity_fingerprint/method`；`source/metrics_source` 指向 `api.codexradar.com/api/v1/*`（该域**不得**请求，见 §5 传输政策）；**两新端点 JSON 内容均不内嵌 attribution/requirements 要求**（实测 0 命中），attribution 义务来自 current.json 站点级声明
- 新端点 `/data/fast-radar-history.json`（顶层 5 键 `schema_version/type/timezone/updated_at/runs`）：schema_version=1，runs[82]，run={run_id,measured_at,completed_at,cli_version,models:{sol|terra|luna:{standard|fast:{ttft_seconds,tps,e2e_seconds}}}}；页面内嵌同名 JSON（type=fast_radar_history）一致
- `model-ratings?history=N`（**history 参数实际生效**，返回对应天窗）：顶层 15 键 `ok/day/timezone/refresh_seconds/updated_at/models/history/my_scores/my_score_records/window/window_hours/since/until/source/cached_at`
  - `models[27]`：{id,label,group,average,count}；**group 全集 6 个**：GPT-5.6 Sol / GPT-5.6 Terra / GPT-5.6 Luna / GPT-5.5 / DSV4 Flash / DSV4 Pro；**effort 后缀全集 7 个**：ultra/max/xhigh/high/medium/low/**off**（id 形如 gpt-5.6-sol-xhigh、deepseek-v4-flash-off）
  - `history[]`：14 条逐日 {day, models, updated_at}——7 天/24h 矩阵可直接取用（见 §5.4）
- `quota_check.plan_type`、`window`、`prediction`、`status/recommended_action` 共同支撑公告横幅与状态徽章（§4.2）

**本地渲染读取器契约存活状态（实测）**
- 降智预警读取器（codexradar.com 主页，revision `codex-radar-rendered-dom-v1`）：`data-radar-degradation`(6)/`data-radar-degradation-grid`(2)/`degradation-card-score`(4)/`degradation-deltas`(2) 均存活；`data-radar-metric`(0) 回退分支失效 → 需清理 + revision bump
- deng IQ 历史读取器（deng.codexradar.com，revision `codex-radar-rendered-iq-history-v1`）：**实质失效**——`data-iq-hours`(0)、`.iqcard.total-iq`(0) 消失；deng 已重建为「众测雷达」（2026-09-04 实测 865,607B，station-dashboard/site-overview/ticker 等新结构；`iq-body`(9)/`iq-range`(7)/`iqcard`(121) 部分残留；页面 `application/ld+json` 仅为 schema.org 站点元数据，全部 `/api/` 端点为 Bearer-token 提交流程（credential-protected，属排除域）→ **D9 确定落入「重写 v2」分支**）

## 2. 目标 / 非目标

**目标**
1. 产品更名 AI Radar（用户可见层 + Swift module/target 层全量重命名；bundle identifier 保持不变，见 D5；生产类型名去留见 §8 类型名条款）
2. 视觉体系对齐上游 2026-09-04 快照（明暗双主题、四语义色、新几何语言）
3. 架构站点化：聚合站 + Codex 站 + Claude Code 站 + SWE-bench 站 + 即将开放占位
4. Codex 站数据面对齐上游全部结构化板块：**4 个数据适配器（2 全新 + 2 升级）+ 1 项导出扩围**，字段处置逐项见 §5.1
5. 渲染读取器修复/升级（deng v2、降智预警 v2）
6. 全程保持测试基线绿（现 367 tests / 46 suites 实测；`docs/implementation-status.md` 记载的 364 为陈旧数字，收尾时对齐）

**非目标**
- 不复刻上游 web 前端代码；不搬运上游文案/图片/二维码/logo 及任何视觉资产（一律链接化）
- 不转载上游「站长推荐」正文，不做任何本地派生推荐（见 D4 修订）
- 不实现打分提交、任何写操作；不接入 credential-protected API（`api_access.full_api`、`api.codexradar.com` 域与 deng 的 `/api/*` 提交端点继续排除，见 §5 传输政策）
- 不为 dsh/zcode/grok 实现真实数据适配器（上游无数据，仅占位）
- 不做跨源自建排名、组合分数或跨源指标对比（聚合站硬边界见 §4.1/D10）
- 不做本地文案派生（Tibo 摘要等一律用上游自带字段原文，见 §4.2 行 7）

## 3. 决策记录

| # | 决策 | 理由 |
|---|---|---|
| D1 | 定名 AI Radar；可执行/bundle `AIRadar`；中文界面「AI 雷达」 | 用户决定；拼写更正 Rader→Radar |
| D2 | 同名混淆缓解：README（英文与中文两份均含）/关于页/数据来源行全链路 non-affiliation + 上游署名；**不使用上游 logo/图标/任何视觉资产**；关于页与 README 注明「AI Radar is an independent open-source project and is not affiliated with codexradar.com（AI 雷达）; the name is an independent choice. / AI Radar 为独立开源项目，与 codexradar.com 的 AI 雷达无关联，命名系独立选择」 | 与上游完全同名，需显式切割；英文为主文档需英文等价句（R5 审定） |
| D3 | 三房间 → 站点工作台；站名保留 Claude Code Radar / Codex Radar / SWE-bench Verified | 对齐上游概念；既有 source contract 与品牌承诺实质保留 |
| D4（修订） | 站长推荐 = **上游链接卡**：固定卡片导流 codexradar.com 对应板块（显著署名），无正文转载、无本地派生推荐 | R1 审定：上游无推荐 JSON，派生呈现即自建推荐、正文转载有版权与维护成本；链接卡是唯一同时满足 D4 初衷与可维护性的形态。§2 非目标措辞已同步 |
| D5 | 数据目录 `~/Library/Application Support/ClaudeRadar/` → `AIRadar/`；首启**复制**迁移，旧目录保留；**`CFBundleIdentifier` 保持 `com.acfufu.ClaudeRadar` 不变**（仅改 Name/DisplayName/ExecutableName/Icon），偏好（UserDefaults 域）与 SMAppService 登录项随 bundle ID 原样保留 | 符合「移除 app 不删数据」承诺且可回滚；bundle ID 若同步改会静默重置偏好并失效登录项（R3 审定） |
| D6 | 社区块放上游社区链接，不搬运二维码图片 | 版权与资产卫生 |
| D7 | 社区体感分只读展示 + 跳转上游打分 | read-only 产品边界 |
| D8 | 字体维持系统字体（不内嵌 Inter） | 上游声明 Inter 但 Mac 实际回退 system-ui；原生 HIG 合规 |
| D9 | deng 重写渲染读取器 v2（实测确定无结构化数据岛可用，§1.1） | 渲染抓取是最后手段，符合隐私边界承诺 |
| D10 | 聚合站硬边界：**无 runtime、无新持久化实体、不挂载公告横幅、无导出目的地**，仅视图层组合各站已有最新投影的「状态/新鲜度点」，禁止跨源指标对比、排名或组合分数 | source-contract「三源从不共享 identities/history/exports/trends/rankings/analysis」的限界放宽：放宽的只有「视图层状态聚合」，其余边界原样保留；PRODUCT.md「clear source boundaries over a generic aggregation layer」原则按此限界继续成立 |
| D11 | AppAppearance 默认值保持「跟随系统」（`.system`），不改 dark 默认；色板以明暗双套对齐上游，深色观感以上游 dark token 为基准 | 上游 dark 默认是网页静态属性；原生遵循 HIG，D8 同理。AppSettings 现有三态（system/light/dark）与默认值均不变 |
| D12 | `my_scores`/`my_score_records`（上游匿名端点返回的「本人打分态」）**只读展示、不持久化**，不建立任何个人身份关联；source-contract 现有「personal data is outside scope」条款改写为「仅展示、不存储、不关联」 | R2 审定：完全跳过该字段会丢失矩阵「我的评分」态；消费但不存储是现有隐私边界内最窄的可用形态 |
| D13 | `tibo_presence` 为**上游发布的关于第三方账号的公开观测**（含 `location_label_zh/en`、`source_urls` 等人别关联字段）：Radar 仅**原文转存、展示与导出**，不做本地推断或派生、不与本地任何数据建立关联；上游 `safety_note` 与 `should_display` 门控原样随行；`docs/third-party-notices.md` 增加对应披露（数据为上游对第三方公开帖的国家/时区级推测，边界以随行 safety_note 为准） | R5 审定：该字段与人别关联且上游自带安全边界说明，是唯一无隐私条款的归一化字段，须与 D12 同级对待 |

## 4. 架构（目标态）

### 4.1 站点模型

| 站 | 内容 | 数据 |
|---|---|---|
| 聚合站 | 各站状态卡（新鲜度点）+ 导航；无统一排名、无横幅、无导出目的地（D10） | 视图层组合各站已有最新投影的状态/新鲜度 |
| Codex 站 | §4.2 全板块 | §5 适配器全家 |
| Claude Code 站 | 现有三房间能力原样迁移 | 现适配器不变 |
| SWE-bench 站 | 现有数据面原样迁移 | 现适配器不变 |
| DSH/ZCode/Grok/Kimi | 「即将开放」静态占位卡（统一文案「即将开放」，副文案列站名；**有意不逐字复刻上游「近期开放」**） | 无（无 runtime，永不同步） |

**命名约定（写死）**：Station Swift case 为 `aggregate/codex/claudeCode/sweBench/upcoming`，`upcoming(DSH|ZCode|Grok|Kimi)` 关联值为嵌套枚举；**三实站 Station rawValue 一律复用既有 `RadarSourceID` rawValue**（`claude-code-radar`/`codex-radar`/`swe-bench-verified`），占位站为 `dsh/zcode/grok/kimi`、聚合站为 `aggregate`（小写连字符）；路由 storageKey 前缀**保持 `source:` 不变**、第二段为站 rawValue（如 `source:aggregate`），保旧持久化兼容；新目的地 rawValue 沿用现有中文串惯例；`RADAR_UI_SOURCE` 新增值 `aggregate` 与 `upcoming-dsh|zcode|grok|kimi`。`WorkspaceRoute(storageKey:)` 现为非 failable、malformed 回落初始路由——**保留该语义**，契约测试同步改写。

**无 runtime 站的旁路改造点（全清单，含强解包消费面）**：
- (a) `RadarWorkspaceModel.runtime` 强解包：`RadarWorkspaceView.swift:109/136` 的 `?? model.projection`/`?? model.runtime` 回落链、`refresh()`（`RadarWorkspaceModel.swift:102→:15`）——全部改为可空 + 旁路
- (b) `normalizedRoute`（`RadarWorkspaceModel.swift:71-84`）对站 selectedSourceID 的恒等回路；`.export` 回落需站级导出目的地定义（**聚合站与占位站均无导出目的地**，回落该站初始页）
- (c) `defaultDestination(for:)`（`RadarWorkspaceModel.swift:52-54`）需为各站新增默认目的地
- (d) `RadarWorkspaceModel.swift:10` 的 `precondition(runtimes[selectedSourceID] != nil)`
- (e) `SettingsView.swift:11` 的 `private var runtime: RadarAppRuntime { model.runtime }` 强依赖
- (f) `MenuBarView` 的 `model.source.displayName`/`model.projection` 消费面
- (g) `AppCommands.swift:17` 的 `model.projection.supportLevel`
- 工具栏刷新按钮与 App CommandMenu「刷新」语义一致：实站 → 刷新该站 runtime；聚合站 → 依次刷新三实站；占位站 → 禁用（带解释 tooltip）

**侧栏结构（写死）**：Section 顺序固定——聚合站（置顶单项）→ 三实站（站名分组，站内目的地按 §4.2 序）→ 「即将开放」组（DSH/ZCode/Grok/Kimi 按上游 nav 顺序）。

**状态点四态（写死，映射表入 design-qa）**：最近同步成功且新鲜 = --green；stale/LKG = --amber；错误/校验失败 = --red；禁用或无数据 = --soft 灰；占位站恒灰。MenuBarExtra 显示各站状态点（model 已持有全部 runtimes 且有 `projection(for:)`）。

### 4.2 Codex 站页面矩阵（新页序 × 既有目的地去留）

**公告横幅**挂载层级：仅 Codex 站页顶部（聚合站与占位站不挂载，D10）。**行为（写死）**：仅当 `window` 字段存在时渲染——`window_open=true` 用 --green-soft 底 + --green 左缘条，`false` 用 --amber-soft 底 + --amber 左缘条；`window`/`status` 字段整体缺失（v1 旧 payload）时横幅与状态徽章不渲染。数据驱动字段：`window`（9 键：标题/消息/开闭状态）+ `status` + `recommended_action`（来自 §5.1 状态快照实体）。

| 新页序（主轴，对齐上游） | 既有目的地/面板去向 |
|---|---|
| 1. 速览排行（benchmark 速览 + 模型档位详情）+ **官网 24h IQ 趋势卡（官网 24h vs 本地拟合 toggle，原 Codex 概览官方区含 `OfficialOverviewTrendSections` 整体保留于此）** | 原「概览」官方区 + 原「模型」列表融合 |
| 2. 站长推荐链接卡 + 降智预警（语义强调卡）+ **预测卡**（`prediction` 6 键：24/48h 概率 + 摘要，字段缺失时隐藏） | 原 Overview 内降智预警区升级；推荐/预测为新增卡（D4/§5.1） |
| 3. 效能 PK（intelligence-efficiency） | **「智力中心」目的地取消**；其 5 面板去向：CostVersusIQ/EfficiencyMatrix/ScenarioRecommendations → 效能 PK 页（3 个）；HistoryComparisonPanel → 历史对比页（行 6）；IQHistorySmallMultiplesPanel（**纯本地拟合数据，不含官方曲线**）→ 历史对比页（行 6） |
| 4. 额度雷达（含 10 天 trend 图 + quota_check/quota_calibration 详情） | 原 Overview 内额度区升级扩容 |
| 5. Fast 雷达（当前对比 + 82 run 历史 + **月份计数表**：runs 按 `measured_at` 所在月份分桶计数，列=月份、值=run 数，**按月升序、缺月补零列**） | 全新页面 |
| 6. 历史对比（history comparison + 本地 IQ small multiples） | HistoryComparisonPanel + IQHistorySmallMultiplesPanel 归入（见行 3）；官方 24h 曲线不在此页（在行 1） |
| 7. Tibo 雷达（reset 时段分布 + presence 卡；**数据仅来自 current.json `tibo_presence` 归一化字段，与渲染读取器无关**） | 全新页面。「动态摘要」= 上游自带摘要字段（`evidence_summary_zh/en`）**原文展示**，无则不展示，不做本地语句拼接；`safety_note_zh` 优先、`safety_note_en` 兜底；`should_display=false` 时整卡隐藏（含 safety_note）；隐私语义见 D13 |
| 8. 工具组：决策透镜 / 趋势 / 来源状态 / 导出 | 四个既有目的地**原样保留**，集中置于主轴之后 |
| 9. 社区入口（上游链接卡，D6/D7）+ **社区知识文章列表卡**（§12 已决：标题 + 上游自带摘要 + 外链，无摘要则仅标题+外链，不本地生成） | 全新 |

- 主轴顺序为验收基准（§9 P1）；工具组内部顺序实现期可调，不影响验收
- 原「智力中心」路由下线需同步 `WorkspaceRouting` 契约测试与 design-qa 路由矩阵
- §6 deng 渲染读取器的展示归宿 = 行 1 的官网 24h IQ 趋势卡（官方曲线唯一挂载点）
- **空态策略（P1 适用）**：所有新组件必须实现并验收 nil-data 空态（每组件至少 1 个 nil-data 单测）；公告横幅 snapshot 缺失时不占位渲染；新面板的种子状态 + 种子截图验收在 P2 各项执行（§9 P2）

## 5. 数据面（Codex 站）

统一模式：DTO（容错解码）→ Validator → Repository 实体（fingerprint 去重）→ Projection → View + fixture 测试；SyncMetadata/RawSamples/Export 逐面扩围；revision 常量逐面定义。
清单口径：**4 个数据适配器（2 全新：IntelligenceEfficiencyDataset、FastRadarHistory；2 升级：CodexCurrentV2、ModelRatings）+ 1 项导出扩围**。
**通用约束：所有新增 DTO 字段一律 Optional**——旧 payload 可解码（合成 Codable encodeIfPresent）、ContentFingerprint canonical JSON 对旧行稳定（指纹不漂移的前提）。

### 5.0 传输、接线与契约政策

**接线模式（sidecar）**：主链 `RadarSyncCoordinator`→`RadarHTTPSource` 为 benchmark/community/sourceStatus 三段专用（端点资格 `SyncEndpointEligibility` 仅两标志，持具体类型非协议），**两个全新适配器不进主链**，沿用 rendered 读取器已验证的 sidecar 先例：各自独立 Coordinator + 独立 triggerObserver + `RadarDatasetType` 新 case，自行接线 raw-sample、SyncMetadata datasetType、生命周期 stop/clear/resume 与导出。**在线门控（写死）**：新 sidecar 生命周期挂入 `RadarAppRuntime.performStart`、经 triggerObserver 转发、以 `AppEnvironment.synchronizationEnabled(for:)` 为总闸（与 rendered sidecar 同法）——保证 `RADAR_FIXTURE_MODE=ui/disabled` 下零网络请求（测试断言）。

**传输实例**：大小上限是传输实例级常量（`URLSessionHTTPTransport.maxBodyBytes` / source 级 `maximumResponseBytes`），无 per-endpoint 机制——IntelligenceEfficiency 与 FastRadarHistory 两个 sidecar 均使用**专属 transport 实例，两处（transport + source）均设 8MiB**（§10 统一口径）；**其余既有面维持现值（Claude/Codex 5MiB、SWE-bench 16MiB），不变**。超限按现有 raw-sample 失败路径处理（保留 LKG），配 8MiB 上限与超限→LKG 路径测试（§10）。

**RawSample 策略（写死）**：新 sidecar 数据集纳入既有 raw-sample prune（按源全局 3 成功/20 失败），接受样本互相挤占，不做 per-dataset 配额（与现状一致，防实现者扩 store）。

**域名与端点白名单**：仅 `codexradar.com`（`/data/*` 路径）与既有端点。**明令禁止请求 `api.codexradar.com`**（intelligence-efficiency.json 的 `source/metrics_source` 指向该域）与 deng 的 `/api/*` 提交端点（Bearer-token，credential-protected）；现架构无传输层 host 黑名单，禁令落在三处：URL 构造点、sidecar 适配器测试的 transport 层 host 白名单断言（`request.host == "codexradar.com"`，防「从响应数据字段构造 URL」路径）、契约测试否定断言（§10）。

MIME/重定向政策、UA、超时沿用现有 `HTTPTransport`；署名串逐字取 current.json `api_access.requirements.attribution_text` 原串「数据来自 Codex 雷达 codexradar.com」（无括号），入各新面板来源行与 Settings 关于页（§8）。每个新端点的 canonical fixture（含 SHA-256）入档 `docs/source-contract.md`（收尾统一更新）。

### 5.1 CodexCurrentV2 升级 —— 字段逐项处置表

**持久化口径**：payload 扩展（既有实体 JSON payload 加 Optional 字段）**免 store schema 迁移**；新实体走 SwiftData **加性 schema 变更**（SwiftData 自动轻量迁移），并在 P2① 落「旧 store + 新 schema 重开」迁移测试初版（复用 `ReleaseReadinessTests.upgradePreservesHistory` 模式），P2②③ 各自增量更新该测试。

| 字段 | 处置 | 落点 |
|---|---|---|
| `window`（9 键）/ `status` / `recommended_action` / `window_open` / `timezone` / `prediction`（6 键） | 归一化新实体；公告横幅/状态徽章/预测卡展示。**P2① 不新增 `RadarDatasetType` case**（不牵动主链三段结构与 eligibility），新实体随 sourceStatus 主链同步落库 | **新实体 `CodexRadarStatusSnapshotEntity`**（含 prediction，单实体快照） |
| `tibo_presence`（17 键，`safety_note_en`/`safety_note_zh`） | 归一化实体；Tibo presence 卡（§4.2 行 7 行为）；**隐私语义按 D13**（原文转存/展示/导出，不推断不关联，safety_note 与 should_display 门控随行） | `CodexRadarStatusSnapshotEntity` 同表内字段（同一 current.json 快照） |
| `quota_radar.trend`（10 条）/ `quota_check` / `quota_calibration` | 归一化入库；额度雷达 trend 图、「当前核查」卡、「校准信息」详情（quota 数值语义沿用既有「source-account estimate, never personal user usage」口径）。**连锁更新**：`ContentFingerprint.sourceStatus`（**trend 保持时序、不排序**）、`DebugUISeed` 种子构造点、`verifiedSourceStatus` 读回路径与测试构造点 | **既有 SourceStatusDataset payload 扩展**（Optional，免迁移）。注：若 P2① 实现中发现该落点不自洽需改，P1 额度雷达页消费窄 view-model（trend 点数组 + check/calibration 展示结构），不直接绑定 SourceStatusDataset 类型，返工不波及视图 |
| `model_iq.data_source` | 归一化入库；来源行展示 | **既有 BenchmarkDataset payload 扩展**（Optional，免迁移） |
| `recent_days` + Run 级 `wall_time_human/average_cost_usd/average_task_seconds/average_task_time_human/cost_usd_basis` | 随 Run 解码入库；效能 PK/历史对比/对比表新列（human 可读值直接展示，`cost_usd_basis` 作脚注）。**新列不走 `CodexHistoryMetric` 封闭枚举**（独立展示列，现 `count == 6` 断言存活） | **既有 BenchmarkDataset/ModelBenchmark payload 扩展**（Optional，免迁移）；连锁更新 `CodexRadarParser.project`、`ContentFingerprint.benchmark`（规范化重建纳入新字段）、`DebugUISeed` 及测试构造点 |
| `links`（html/rss/full_api）/ `api_access` | **不入实体**；仅 Settings 关于页与来源行静态引用（full_api 维持排除） | 无实体 |
| 旧字段（latest/comparisons/quota_radar 原有部分） | 解析行为不变；fixture 新旧双向保留（v1 兼容回归测试） | 不变 |

**导出 schemaVersion 决策（写死）**：payload 扩展为 additive 字段，导出 manifest/page envelope 的 schemaVersion **不 bump**（维持 1）；扩面事实记录于收尾的 source-contract 更新。

### 5.2 IntelligenceEfficiencyDataset 适配器（全新）

`/data/intelligence-efficiency.json`；`points`/`history`（249 条，8MiB 上限 §5.0）+ `fingerprint`/`activity_fingerprint`/`method`/`source_updated_at` 溯源入库。**命名避让**：`DerivedMetrics.swift` 已有同名 `IntelligenceEfficiency` enum（本地智力-成本派生分析），新适配器类型一律带 `Dataset/Adapter` 后缀（`IntelligenceEfficiencyDataset`/`IntelligenceEfficiencyAdapter`）；`Phase4SourceContractTests` 现有 `!package.contains("intelligence-efficiency")` 否定断言随新 fixture/资源入包同步改写（§10）。新实体 `IntelligenceEfficiencySnapshotEntity`。

### 5.3 FastRadarHistory 适配器（全新）

`/data/fast-radar-history.json` schema v1（§1.1 全键）；派生指标（fast vs standard 的 ΔTTFT/ΔTPS/ΔE2E 倍率）入 DerivedMetrics 层——**新建独立入口类型与 evaluate 函数**，勿复用语义为 per-passed-task 比值的 `DerivedMetricFormula`。新实体 `FastRadarRunEntity`：**每 sync 按 dataset fingerprint 整体替换（不跨 sync 累积），本地不无界增长**，配替换/不累积正负向测试（§10）。支撑 Fast 雷达页（当前对比卡 + 82 run 历史 + 月份计数表，§4.2 行 5）。

### 5.4 ModelRatings 升级

- 解析升级为**开放集合**：group 6 个已知值（GPT-5.6 Sol/Terra/Luna、GPT-5.5、DSV4 Flash、DSV4 Pro）+ effort 后缀 7 个（ultra/max/xhigh/high/medium/low/off）；实现取 `group: String?` + computed property 映射已知组、未知值原样分组渲染（**不做封闭 enum**，防上游换代即断）；effort 后缀从 id 字符串切分，同样原样保留。现 DTO 根本未解码 group，此次补齐
- 星评分矩阵：**7 天矩阵直接取 `history[]` 尾部 7 天，24h 用当日 `day` 桶**（已决）；`my_scores`/`my_score_records` 只读展示、不持久化、不建立个人身份关联（D12，配负向测试 §10）
- 只读 + 「去上游打分」链接（D7）

### 5.5 导出扩围

3 个新实体（`CodexRadarStatusSnapshotEntity`、`IntelligenceEfficiencySnapshotEntity`、`FastRadarRunEntity`）入 ExportManifest/ExportPage；**新实体导出 payload 跟随既有 per-dataset envelope 惯例**；既有 dataset 的 additive 字段不 bump schemaVersion（§5.1 决策）；导出仍按站隔离；聚合站不可导出（D10，配负向测试 §10）。

## 6. 渲染读取器（P3）

- **deng IQ 历史读取器 v2**：按新 DOM 重写 extraction script（revision `codex-radar-rendered-iq-history-v2`；**revision 字面量触点以全仓 grep `codex-radar-rendered-iq-history-v1` 为准**——2026-09-04 实测 `.swift` 9 处 + fixture JSON 10 处，fixture 随重录自然更新），展示归宿 = §4.2 行 1 官网 24h IQ 趋势卡。**隐私边界重申（写死）**：继续强制 `WKWebsiteDataStore.nonPersistent()`，仅持久化 bounded 归一化字段，净化禁词沿用现契约测试清单（含 `"<script"`、`"@"`、`"/api/"`）。fixture 处置：**仅重录 DOM 派生 fixture**（live 跑读取器取 bridge-DTO 输出 → 按净化规则脱敏 → 重算 SHA256SUMS → 更新契约测试 revision 断言）；**合成错误 fixture（challenge/off-host/oversized/partial/prompt-like-text 等）保留并按 v2 解析形态适配**。`Tests/ClaudeRadarTests/Fixtures/CodexRenderedIQHistory`（Package.swift exclude 值 `Fixtures/CodexRenderedIQHistory` 不变）为 fixture 根。注意：渲染走 WKWebView，与 `CodexFixtureTransport`（仅 current.json/model-ratings 两 URL）无关
- **降智预警读取器 v2**：清理 `data-radar-metric` 失效回退（`CodexRenderedWarningPageReader.swift:193-196`）；契约锚定存活的 4 个 data-radar-degradation* 标记；revision bump 至 `-v2`（触点同样以全仓 grep 为准）；Cloudflare challenge 检测逻辑保留。随回退分支删除，对应 fixture（`missing-metric.json`、`duplicate-metric.json`）与 fixtureNames 清单（位于 `CodexRenderedWarningDOMParserTests.swift:271-275`）同步移除
- 两读取器的 origin 硬守卫（codexradar.com / deng.codexradar.com）不变

## 7. 视觉系统（P0 落地）

- `RadarPalette` 重定义：§1.1 token 表 light/dark 全量映射（SwiftUI Color + ColorSchemeContrast；现 12 token 扩至含四语义色 + soft 变体 + line/line-strong 双级边框；`RadarColorToken` 自带 opacity，rgba soft 变体直译）；light `--panel: rgba(255,255,255,.90)` 用半透明实色，**勿用 material 模糊**
- **无障碍对比度轴（写死）**：上游无 increased-contrast 变体；现 `ColorSchemeContrast.increased` 语义由 **`line`/`line-strong` 双级边框承接**（increased 下 divider 用 line-strong），无对应 token 处 `increased == standard`；取舍随 design-qa 入档
- 上游 `color-mix` 染色变体 SwiftUI 无对应 API：**预计算混合色或 opacity 叠加近似**（实现期定，两法取一并在 design-qa 记录）
- `RadarStyle` 几何：cornerRadius 梯度 panel 15 / card 11 / inline 7；胶囊 badge（Capsule）；shadow(soft/strong)（现 `RadarPanelModifier` 已有 .shadow，换参）；强调卡修饰器 `radarAccentCard(color:)`（overlay 左缘 5px）
- **胶囊 badge 使用白名单（写死）**：仅用于公告横幅状态词（status/recommended_action）、模型组 effort 后缀标签、quota_check 的 limit_reached/plan_type 标签；其余位置禁用，新增须回 spec；以契约测试锚定（§10）
- `RadarAnalyticsColors` 图表色板：现 5 色 family → 映射四语义色 + 1 中性色（muted/soft 灰），映射表随 design-qa 入档
- 新共享组件（公告横幅、状态点、星评分矩阵、月份计数表）落 `Features/Shared/`；**组件 API 只接受本地定义的展示 view-model，不引用 repository 数据集/实体类型**（P2 落点变化不波及 P0 视觉基线；输入类型冻结推迟到消费方落地）
- 同步更新：`RadarStyleTests`（token 断言按新表重写，含 increased-contrast 断言按本节对比度轴）、`docs/design-qa.md`（冻结参考改钉 codexradar.com 2026-09-04，token 全表 + color-mix 近似规则 + family 映射 + 状态点四态映射 + 对比度轴入档 + 路由矩阵更新）
- 默认外观保持「跟随系统」（D11）；AppAppearance 三态保留

## 8. 重命名（R0 清单——仅纯机械项）

> 归属修订（R3）：原 v3 混入 R0 的「环境变量值域扩展」「DebugUISeed 新面板种子」**移出 R0**——分别归属 P1（station/目的地存在后）与 P2（repository insert API 落地后），见 §9 各阶段条目。

- `Package.swift`：name ClaudeRadar→AIRadar、executableTarget/testTarget 同步
- 目录 `Sources/ClaudeRadar/`→`Sources/AIRadar/`、`Tests/ClaudeRadarTests/`→`Tests/AIRadarTests/`（git mv 保历史）；全部 `import ClaudeRadar`→`import AIRadar`（Tests 下 42 个文件）
- **生产类型名条款（写死，R5 审定）**：`ClaudeRadarParser`/`ClaudeRadarConfiguration`/`ClaudeRadarValidator` 等 Claude 站生产类型**随站名保留、R0 不更名**（「Claude Radar」是上游站名，受 D3 保护；§2「模块层」指 Swift module/target，不指类型名）；Tests 内仅替换字符串字面量与路径断言，**类型引用一律不动**
- `Config/ClaudeRadar-Info.plist`→`AIRadar-Info.plist`：**CFBundleIdentifier 保持 `com.acfufu.ClaudeRadar` 不变（D5）**；改 CFBundleName/DisplayName/ExecutableName；同步 `CFBundleIconFile=AIRadar.icns`（plist 其余键无品牌承载，不改）
- Assets：`ClaudeRadar.icns/png` → `AIRadar.icns/png`（git mv 改名；**现 icon 为纯雷达图形、无文字元素**，图像内容初始逐字节沿用；真正的 AI Radar 视觉变体列入人工核验清单，由人工出图后经 `iconutil -c icns` 重生成并接线；不得使用上游任何资产）；`Scripts/build-app.sh` **及 `script/build_and_run.sh`（APP_NAME，BUNDLE_ID 不变）**内 `ClaudeRadar` 字面量**全量机械替换**（APP_NAME、Info.plist 路径、icon、`:39` 的 `RESOURCE_BUNDLE="$BIN_DIR/ClaudeRadar_ClaudeRadar.bundle"`——改名后 SPM 资源包为 `AIRadar_AIRadar.bundle`，漏改则 debug 打包直接失败）
- UA：硬编码于 `ClaudeCodeRadarHTTP.swift:8`，改为字面量 `AIRadar/0.3.0 (macOS; +https://github.com/Acfufu/Radar)`（**不读 bundle 版本**——SPM swift run/test 下 Bundle.main 无 Info.plist；版本号随发版手动步进，release-checklist 增加该手动更新步 + 契约测试加 UA 字面量断言防漂移）
- 导出默认文件名前缀 `.ClaudeRadarExport-`（`RadarExportService.swift:124` 带点临时目录前缀、`ExportView.swift:142` 无点用户可见文件名前缀）→ `.AIRadarExport-`/`AIRadarExport-`（随重命名，属本节列明行为变更；联动断言在 R0 机械替换清单内）
- 数据目录迁移（D5）：逻辑内嵌 `AppEnvironment.current()`（必须先于任何 `makeModelContainer()`/`SyncMetadataStore(root:)`；app init 后立即建 metadataStore，故此为唯一安全时序）：检测旧目录存在且新目录不存在 → 整目录复制（Radar.store/RawSamples/SyncMetadata.json 同根，整目录复制即完整覆盖；store 为自定义文件名，bundle ID 不变故无路径漂移）→ 原子标记迁移完成；失败不阻塞（退回全新目录）；**DEBUG 下 `RADAR_DATA_ROOT` 覆盖时跳过迁移**；三 runtime 共享同一 AppEnvironment 实例，天然单次 + 幂等；迁移本身有单元测试
- **R0 包含测试的纯机械替换（全仓口径）**：grep `ClaudeRadar` 于 Tests/ 的路径与字符串字面量断言全部机械替换（实测命中 **19 个测试文件**，含但不限于 Phase4SourceContractTests 的 `Sources/ClaudeRadar/...` 相对路径与 `Window("Claude Radar")` 品牌串、ReleaseReadinessTests 的 plist/icns/png 路径与 CFBundleIconFile、Phase0SmokeTests、SWEBenchParserTests、RadarLifecycleRaceTests、CodexRenderedIQHistoryOverviewContractTests、ClaudeCodeRadarSourceTests、CodexRadarParserTests、ClaudeRadarParserTests、RadarSyncCoordinatorTests、CodexAnalyticsPanelsContractTests、CodexIQHistoryPanelContractTests、CodexRenderedIQHistorySourceContractTests 的 fixture 路径、以及 `.ClaudeRadarExport-` 联动断言；生产类型名引用不在此列，见上方类型名条款）——替换后既有 367 项全绿，此为 §9 R0 验收的组成部分
- 用户可见串：窗口标题、菜单栏、Settings（含**关于页边界段落**——按 D2 措辞更新（英文+中文），注明独立项目与命名说明；新增端点的边界披露随 P2 落地补充）、导出默认文件名（见上）
- 环境变量名**保留不变**（脚本与文档依赖）
- 文档同步（R0 内）：README/README_zh/PRODUCT.md 品牌、D2 声明；历史文档 `docs/Claude_Radar_Codex_v2.0.md`、`docs/deep-check-2026-08-03.md` **标注「历史存档，不随更名更新」，不改内容**
- 硬约束：除本节及 §9 R0 验收列明项（UA、导出文件名、数据目录迁移、用户可见串）外，R0 **不改任何行为**

## 9. 分阶段交付与验收

流程约束（AGENTS.md）：每阶段开工前建跟踪 issue（`gh` CLI，docs/agents/issue-tracker.md），使用五规范标签（docs/agents/triage-labels.md）无旁路；收尾前以 /domain-modeling 固化「station/站」词汇落 `CONTEXT.md`，并为本架构变更（三房间→站点工作台）落一篇 ADR。

| 阶段 | 内容 | 验收标准（可客观判定） |
|---|---|---|
| R0 | §8 重命名（拆 2 commit：①纯机械重命名+测试替换 ②数据目录迁移+迁移测试；各自全绿）。**R0 结束时捕获视觉基线**（供 P0 验收）：按 design-qa 惯例（app 1080x720、明暗双版、`RADAR_FIXTURE_MODE=ui` + `RADAR_UI_STATE=fresh|stale`）对「当时全部目的地 × 主题 × seed」全矩阵截图，矩阵清单以表格存 `docs/design-qa/baseline/manifest.md` | 既有 367 测试全绿（含机械替换后）+ 新增迁移测试绿；app 可构建可启动（含 debug 打包 = 资源包路径正确）；迁移核验=`AIRadar/` 含 Radar.store/SyncMetadata.json/RawSamples 且 `ClaudeRadar/` 原样（哈希比对）；偏好核验=迁移前后 `defaults read com.acfufu.ClaudeRadar` 逐键一致；登录项以 SMAppService 状态查询或系统设置人工核验并记录；`git mv` 历史保留 |
| P0 | §7 视觉（允许单 commit 或两 commit：palette+RadarStyleTests / 重摄+design-qa） | 明暗双主题 token 与 §1.1 表一致（RadarStyleTests 断言为证）；P0 结束按 R0 基线同参数（目的地 × 主题 × seed）重摄全矩阵；**「无基线缺失项」由脚本文件名集合比对在 P0 内判定（AUTO）**；design-qa 建立逐张比对条目（文件对/两侧字节数），**人工并排判定结论为 HUMAN-PENDING，随发版硬门（人工核验清单清零）统一闭环** |
| P1 | §4 架构 + 组件（拆 3 commit：①station 枚举+路由泛化+model 旁路（**含编译联动文件：ClaudeRadarApp.swift、AppEnvironment.debugInitialSourceID、MenuBarView、InformationOverviewView、AppCommands**）+ `RADAR_UI_SOURCE`/`RADAR_UI_DESTINATION` 值域扩展（含契约测试）②Codex 页矩阵重组+智力中心下线 ③聚合站+占位站+MenuBarExtra 状态点+侧栏分组+README fixture 命令更新） | §4.2 矩阵逐项可达（主轴 1–9 顺序一致，工具组 4 页保留）；占位站显示「即将开放」；侧栏 Section 三组顺序正确；MenuBarExtra 状态点四态；**aggregate/占位站选中态下 Workspace/Settings/MenuBarExtra/CommandMenu 均不崩溃（旁路 (a)–(g) 全部生效，有对应测试）**；新组件全部实现 nil-data 空态（每组件 ≥1 nil-data 单测）；路由契约测试更新绿 |
| P2 | §5 数据面（①→⑤ 逐个，每项独立 commit） | ①CodexCurrentV2：§5.1 处置表全项落地（3 实体落点、SourceStatusDataset/BenchmarkDataset 连锁、重开迁移测试初版）②IntelligenceEfficiencyDataset ③FastRadarHistory（重开迁移测试随 **②③** 增量更新）④ModelRatings ⑤导出扩围；**①–⑤ 每项含新面板种子状态 + 种子截图（seed 名入 commit message）**；每项 fixture 测试绿；**online 验收：优先程序化代理判定（隔离 `RADAR_DATA_ROOT` 下启动，`SyncMetadata` 对应 datasetType 的 lastSuccessfulAt 非 nil 且归一化实体计数 >0，等效「面板非空」）；网络瞬时失败记 DEFERRED、发版前闭环；无法程序化处保留 manual 步骤入 release-checklist**；**fixture 隔离（自动测试）**：`ui/disabled` 模式下 sidecar 零网络请求；契约测试 + transport 层 host 白名单断言证实不触碰 `api.codexradar.com` 与 deng `/api/*` |
| P3 | §6 读取器 | deng v2 契约测试绿（DOM 派生 fixture 重录 + 合成 fixture 适配 + revision 断言，nonPersistent 与净化清单重申落地）；降智预警 v2 绿（含回退分支删除后的 fixtureNames 收缩）；LKG 兜底行为不变 |
| 收尾 | 文档/发版 | README/zh（D2 英文+中文声明）、**source-contract**（新端点 fixture SHA-256 与大小政策、**两新端点各补 Release and authorization boundary 条目**（公开 GET、无认证、站点级 attribution 适用、禁域明示）、my_scores 条款改写（D12）、tibo_presence 披露（D13）、additive 字段不 bump 记录、署名原串核对）、**third-party-notices**（应用名 AI Radar + 新增两端点披露（ie.json 为上游基于受保护 API 派生的公开数据，Radar 仅消费公开 /data/ JSON）+ tibo_presence 第三方观测披露 + quota 口径继承）、**release-checklist**（产物/安装/数据/偏好路径、UA 版本手动步、online QA 步骤、路由矩阵、升级步骤改 AI Radar）、**plist 版本步进（CFBundleShortVersionString→0.3.0、CFBundleVersion+1）**、implementation-status（364→实测值）、design-qa 全更新；CONTEXT.md + ADR 落盘；hero.gif/截图重录（页面清单=聚合站 + Codex 站 §4.2 九页 + MenuBarExtra，明暗双版）；发 v0.3.0 |

执行顺序：C0-pre(文档保护 docs commit) → R0(2 code commits + 基线捕获 docs commit) → P0 → P1(3 commits) → P2(①→⑤ 逐个) → P3 → 收尾；每 commit 测试绿后合入；HUMAN-PENDING 类验收项随「人工核验清单」跟踪、发版硬门清零（守则见执行计划 `docs/ai-radar-refactor-plan.md`）。

## 10. 测试影响

- 必改（行为变更对应）：RadarStyleTests（token 重写 + 对比度轴）、WorkspaceRoutingContractTests（含 storageKey 回落语义）、WorkspacePresentationContractTests、WorkspaceProjectionTests、MultiSourceWorkspaceTests、WorkspaceSupportSurfaceTests（+聚合站不可导出断言）、CodexAnalyticsPanelsContractTests、CodexIQHistoryPanelContractTests、**CodexRenderedIQHistoryOverviewContractTests（P1②：官方趋势迁挂新页 + 路径更新）**、**RadarRepositoryTests（P2②③：RadarDatasetType.allCases 计数数组扩展 + 新实体 insert/clear 路径）**、**RadarExportServiceTests（R0：`AIRadarExport-` 机械替换；P2⑤：ExportDataset.allCases 精确表 + 新 dataset manifest/page）**、CodexRenderedWarning/IQHistory 的 DOMParser+PageReader+Projection+DebugFixture 系列（含 fixtureNames 收缩与 DOM 派生 fixture 重录、合成 fixture 适配）、ReleaseReadinessTests（品牌串 + 重开迁移测试）、Phase4SourceContractTests（路径/品牌/UA 字面量断言新增/`intelligence-efficiency` 否定断言改写/`api.codexradar.com` 与 deng `/api/*` 新否定断言/P3：渲染读取器 revision 与解析形态断言随 v2 改写）、Phase0SmokeTests（codex fixture 断言 + plist 路径）、Phase4RuntimeSettingsTests、RadarAppRuntimeTests（sidecar 接线 + fixture 隔离零网络断言）
- 新增：2 个新适配器全套（parser/validator/repository/projection，含 8MiB 上限与超限→LKG 路径测试、**transport 层 host 白名单断言**）、2 个升级适配器的增量测试、迁移测试（目录复制 + 旧 store 重开）、Station 枚举与路由测试、CommandMenu 语义测试、`CodexRadarStatusSnapshotEntity` 实体测试、ContentFingerprint（benchmark + sourceStatus）新字段连锁测试、**FastRadarRunEntity 每 sync 整体替换/不累积正负向测试**、**4 个新共享组件的 view-model 映射 + nil-data 空态单测（横幅 v1-payload 不渲染、月份升序补零分桶）**、**badge 白名单契约测试（源码扫描锚定）**、**my_scores 不持久化负向断言（D12）**、**tibo_presence 不本地推断/不关联断言（D13）**
- 机械替换（R0 内）：42 个测试文件 import、19 个测试文件的路径与字面量断言（§8；生产类型名引用不动）
- 基线策略：每 commit 全量 `xcrun swift test` 绿（既有 367 项不删改断言，除非对应行为按本 spec 变更——变更记录于 commit message；总数随新增递增）

## 11. 风险与对策

| 风险 | 对策 |
|---|---|
| 上游 schema 再漂移 | 逐面 revision 常量 + 容错解码 + fingerprint 校验（现状已证明有效：2.0 升级未破坏 v1 解析）；ModelRatings 开放集合容错（§5.4）；新字段全 Optional 保指纹稳定（§5） |
| deng DOM 再改 | 读取器 revision 化 + LKG 兜底 + fixture 锚定（合成 fixture 保留适配） |
| 同名品牌混淆 | D2 全链路署名（英+中）+ 独立项目声明；不使用上游任何资产（D6/§2） |
| 重命名破坏基线 | R0 纯机械（含测试机械替换、类型名不动的明确边界）、拆 2 commit、全量验证后才进 P0 |
| 重命名破坏偏好/登录项 | bundle ID 不变（D5）；R0 验收含 defaults 逐键比对 + SMAppService 核验 |
| 迁移丢数据 | 复制式迁移（非移动）+ 失败回退全新目录 + 单测覆盖（目录复制 + 旧 store 重开两类） |
| intelligence-efficiency.json 增长超 8MiB | 大小政策单列 + 专属 transport 实例 + 上限测试（§5.0/§10）；超限走 LKG；收尾在 source-contract 记录增长观测 |
| FastRadar 历史无界增长 | 每 sync 按 fingerprint 整体替换、不跨 sync 累积（§5.3，配测试） |
| 渲染抓取隐私边界 | nonPersistent + bounded 字段 + 净化清单重申（§6）；my_scores 只读不存储（D12，负向测试）；tibo_presence 原文转存不推断不关联（D13，断言） |
| SwiftData 加性 schema 变更 | 3 个新 @Model + Optional 字段；旧 store 重开测试 P2① 初版、②③ 增量（§5.1/§9） |
| P2 落点推翻波及 P1 视图 | 新组件只消费窄 view-model（§5.1/§7），不绑定实体类型 |
| sidecar 破坏 fixture 隔离 | 在线门控挂 `synchronizationEnabled(for:)` 总闸 + ui/disabled 零网络自动断言（§5.0/§10） |

## 12. 已决微项（无阻塞开放项）

R1–R5 审定后，原「开放项」全部收敛为已决：
- 社区知识文章 → 「标题 + 摘要 + 外链」列表卡；**摘要用上游文章卡自带摘要，上游无摘要则只留标题+外链**（不本地生成）
- 星评分矩阵维度 → 7 天取 `history[]` 尾部、24h 取当日桶（§5.4）
- 站长推荐 → 上游链接卡（D4 修订）
- 官网 24h IQ 趋势卡 → 挂速览排行（§4.2 行 1，唯一挂载点）
- 聚合站横幅 → 不挂载（D10）
- my_scores → 只读展示不持久化（D12）；tibo_presence → 原文转存不推断不关联（D13）
- 月份计数表 → 挂 Fast 雷达页，runs 按月分桶，**升序、缺月补零**（§4.2 行 5）
- 横幅两态与 v1 payload 行为、预测卡位置 → §4.2 首段与行 2
- 占位卡文案 → 统一「即将开放」（§4.1）
- 胶囊 badge 白名单、状态点四态、侧栏分组顺序、命名约定（含三实站 rawValue 复用、新站 storageKey `source:` 前缀）→ §7/§4.1
- 历史对比新列 → 不走 `CodexHistoryMetric` 枚举（§5.1）
- 新实体导出 payload → 跟随既有 per-dataset envelope 惯例（§5.5）
- 无障碍对比度轴 → line/line-strong 承接，无对应处 increased==standard（§7）
- FastRadar 历史 → 每 sync 整体替换不累积（§5.3）
实现期允许的仅剩不影响验收的排版微调（如卡片列宽、color-mix 近似两法取一、**无 runtime 站在 Settings/MenuBarExtra 的显示回落占位（如「—」）**），无须回 spec 流程。

## 附录 A · 调研证据

- 快照（2026-09-04）：codexradar.com 首页 HTML（679,867B，动态波动）、current.json（94,723B，schema 2.0）、model-ratings（41,516B，27 模型/6 组）、deng.codexradar.com（865,607B）、intelligence-efficiency.json（4.07MB，history 249 条）、fast-radar-history.json（82 runs）
- 关键实测：station 参数被 JSON 端点忽略；`?station=aggregate` 与首页字节级相同；非 Codex 站为预览占位；`model-ratings?history=N` 生效；ie.json `source/metrics_source` 指向 `api.codexradar.com`；两新端点 JSON 无内嵌 attribution 要求；deng 无结构化 IQ 数据岛
- 本地契约检查计数见 §1.1「渲染读取器契约存活状态」；token 表经 R1 逐值复核；代码落点（sidecar 先例与在线门控、transport 上限常量、AppEnvironment 时序、测试硬断言清单 19 文件、无 runtime 旁路七改造点、bundle ID/偏好/登录项链路、raw-sample prune 策略、fixtureNames 位置、revision 字面量触点）经 R1–R5 逐项核实

## 附录 B · 审阅记录

| 轮次 | 审 A | 审 B | 结果 |
|---|---|---|---|
| R1 | 事实核查（仓库+上游实测） | 完整性/一致性/决策落实 | FAIL 1 P1 + 1 P0 + 若干 → v2 |
| R2 | 技术可行性（代码级） | 修订核验 + 新问题扫描 | FAIL 3 P1 + 2 P2 → v3 |
| R3 | 阶段依赖/返工风险 | 冷读执行者完备性/决策保真 | FAIL 3 P1 + 6 P1 → v4 |
| R4 | 验收可判定性/测试映射 | R3 落实核验 + 自洽终检 | FAIL 4 P1 + 3 P2 → v5 |
| R5 | 合规/隐私/数据边界 + 事实抽查 | 全阶段执行干跑 | 3 项条款级 + 10 项条款级 → v1.0 定稿 |
