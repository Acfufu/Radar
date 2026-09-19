# AI Radar 上游调研档案 — codexradar.com 2026-09-20 快照

- 调研时间:2026-09-20(凌晨)
- 方法:`curl` 实测各数据端点(schema/键集/模型集)+ ego-browser 匿名渲染探针(deng.codexradar.com,whoami=404 未登录态)
- 目的:为「AI Radar App 下一步迭代」拍板提供上游事实基线;本档案是 `docs/ai-radar-sync-spec.md`(v1.1 冻结 2026-09-09)的**上游重勘增量**,不替代 spec;上一轮基线见 `docs/ai-radar-upstream-recon-2026-09-08.md`
- 关联:spec v1.1(v0.4.0 冻结范围)、issue #3(v0.4.0 总跟踪,ready-for-agent)、ADR-0002(deng 退役)、loop:`.lazyzcode/plans/next-iteration-recon-grill.md`

## 0. 总判断

**距 09-08 勘察 12 天,上游 4 处实质变化;spec v1.1 冻结的全部数据端点契约零破坏**——radar-insights 仍 11 键 schema 1、VSR 仍 12 键 schema 1、iem 仍 schema 2、model-ratings 端点同构、fast-radar JSON 仍 schema 1。变化全部发生在「开放集内的数据扩张」与新页面板块层,不动 App 适配器骨架。

## 1. 线上布局与板块清单

- 首页单文件 HTML 实测 **729,156B**(09-04 为 679,867B,页面体量随内容波动);站点菜单**仍 5 项**:`./?station=aggregate|codex|dsh|zcode|grok`,Kimi 仍为菜单内占位项(`<div class="station-item station-item-coming station-item-kimi" aria-disabled="true">` + 「近期开放」徽标)。
- 公告条(site-announcement)在位,当前内容为站务/推广类文案(渲染读取摘要:二手账号交易推广,附 QQ 联系方式);属页面内容而非结构化数据,App 不消费(公告横幅消费者仍是 current.json window/status,P2-1 契约不变)。
- 快速入口四链接:加入雷达社区 / 模型主观打分 / 前往众测雷达 / **参加鹈鹕杯**(新增)。
- Codex 站自上而下(渲染读取):站速览图 → 雷达社区知识分享(新增「遇到降智后的自救和求救方法」「GPT-6 Astra 长上下文与个人订阅额度:Support 回复修正」等卡)→ 站长推荐 + 降智预警 → 综合智能排行(模型已换 **GPT-6 Astra** 世代)→ 成本×IQ 散点 → IQ 历史数据(折叠区) → 历史数据比较 → 社区体感分(GPT-6 Astra ultra/max/xhigh…low 全档在列)→ 额度雷达(**9月13日更新**:$1,847 Astra / $1,919.83 Sol / $1,145.10 Luna 三档)→ **Fast 加速雷达(Astra low/medium/high,体感 ~1.87×)** → Tibo 雷达(9月13日更新:重置次数月表、时段分布 62% 落 00:00–08:59、X 动态 feed 带中文翻译与信号标签)→ 页脚二维码区。
- **新增板块:鹈鹕杯 showcase**——「鹈鹕杯优秀作品 · 站长推荐」,六件作品同场 PK 画廊,链接 8 处指向 `/cup/`(#gallery + 6 个作品永久链 `#work/<uuid>`)。`/cup/` 为独立活动页(200,2,508B):`<title>鹈鹕杯 2026 · Pelican Pedal Jam — CodexRadar</title>`,JS 壳页,作品画廊 + 星级投票(每会话/每作品限票,共享每日 30 票池)。**投票属写操作、活动数据无公开读端点**——App 只读边界下无可接数据面。

## 2. 数据端点实测(2026-09-20 curl)

| 端点 | schema/键集 | 2026-09-20 实测 | vs spec v1.1 冻结契约 |
|---|---|---|---|
| `codexradar.com/current.json` | schema_version 2.0 | status=community_confirmed、window_open=false、**monitored_at=2026-09-14T13:05:52+08:00(主监控停更 6 天)**;comparisons 11 键仍 gpt_55/gpt_56_sol\|terra\|luna 世代,**无 astra**;recent_days 在;links{html,rss,full_api} | 键集零漂移;comparisons 模型世代未跟随站点换代,实现期留意 |
| `/api/radar-insights` | schema 1,11 键 | models=[gpt-5.5, gpt-5.6-luna, gpt-5.6-sol, gpt-5.6-terra, **gpt-6-astra**];efforts 含 **ultra**;rec_keys 仍 4 场景;degradation_alerts.items 当日为空;recommendation_mode=comprehensive_weighted_mean;source_updated_at 2026-09-19 | 零漂移;模型/effort 开放集扩张(§5.6 契约天然容纳) |
| `/data/intelligence-efficiency.json` | schema 2 | models **20**/points 70/history **345**/runs_total 47288/runs_24h 436;**新增:gpt-6-astra、deepseek-v4.1-flash、dsh-deepseek-v4.1-flash、dsh-deepseek-v4-flash-vision-exp、gemini-3.8-flash、kimi-k2.8-preview**;source_updated_at 2026-09-20T02:08+08:00 | 零漂移;P2-2 sidecar 已在同步该文件 |
| `/api/visual-spatial-reasoning` | schema 1,12 键 | pompeii-adjacency;points 25;models 含 gpt-6-astra;runs_total 4974 | 零漂移 |
| `/api/model-ratings?view=public&window=7d&history=14` | 同构 | models **33**;groups **7**(新增 GPT-6 Astra);efforts 含 **ultra** 与 off;history 14 天 | 零漂移;组/模型开放集扩张 |
| `/data/fast-radar-history.json` | schema 1 | runs **114**;models **仍 sol/terra/luna**;updated_at **2026-09-14**;官网 UI 却已展示 Astra low/medium/high ≈1.87×——**UI 与公开 JSON 脱节持续 12+ 天(09-08 发现的过渡态未收敛)** | 契约未变;展示层分叉(见 §5 拍板 5) |
| 首页 HTML | — | 729,156B;鹈鹕杯 showcase 区新增 | 页面层,无数据契约 |
| `/cup/` | — | 2,508B JS 壳;无公开作品读端点 | 无契约,App 不接 |
| `deng.codexradar.com` | 渲染页 | 913,834B「众测雷达」;`/api/v1/*` 全 Bearer 提交流程(whoami/oauth/leaderboard/assignments,**禁域维持**);**IQ 区以新 DOM 复活**,见 §4 | 渲染态新契约(见 ADR-0004) |

不存在性复核:未发现 `/data/stations.json` 类新静态分站文件;无 `api.codexradar.com` 主机请求迹象。

## 3. 官网 vs App 现状差距表(以 spec v1.1 冻结范围为基线复核)

| # | 官网功能 | 9/20 复核 | 差距处置 |
|---|---|---|---|
| G1 | 四预览站真实数据 | iem 模型集 17→20;DSH 家族新增 `dsh-deepseek-v4.1-flash`、`dsh-deepseek-v4-flash-vision-exp`;`kimi-k2.8-preview` 进入数据面但 Kimi 站仍占位 | v0.4.0 转正(ADR-0003)照实施;**白名单核对集扩充**(v1.2 注记 ⑥);聚合站对比视图在 Kimi 转正前仅并入四实站白名单并集(注记 ⑦) |
| G2 | IQ 历史数据板块 | iem history 264→**345** 点,数据面持续增长 | 维持 v1.1 方案(既有数据集 + 趋势卡 UI),无新端点 |
| G3 | 综合智能三能力 tab | radar-insights 实测含 gpt-6-astra(ultra 档);VSR 25 points/4974 runs | v0.4.0 实施范围(§5.6/§5.7),开放集容纳 astra(注记 ⑧) |
| G4 | 站长推荐 4 场景卡 | rec_keys 仍 daily_development/hard_problems/background_automation/lobster_tasks | v0.4.0 实施范围,无变化 |
| G5 | degradation_alerts JSON 化 | 当日 alerts.items 为空 | v1.1 决策(alerts 双路径并存)维持 |
| G6 | 社区体感分 | 7 组 33 模型(新增 GPT-6 Astra 组);efforts +ultra | P2-4 已接,开放集解析无破坏(注记 ⑧) |
| G7 | 额度雷达/Fast 雷达/Tibo 雷达 | 额度雷达 9/13 三档(Astra/Sol/Luna);**Fast 雷达 UI 与 JSON 脱节 12+ 天**;Tibo 9/13 更新 | 额度/Tibo 维持;**Fast 雷达页面隐藏 + sidecar 同步继续**(拍板 5) |
| G8 | Kimi Code 站预告 | 菜单仍 `station-item-coming`「近期开放」 | Kimi 占位卡维持(§4.1),零差距 |
| G9(新) | GPT-6 Astra 换代 | radar-insights/VSR/ratings/iem 全含 astra;current.json comparisons 未跟 | 开放集内扩张,契约零破坏;Codex 站 UI 需容纳(注记 ⑧) |
| G10(新) | 鹈鹕杯(/cup/ + showcase) | 活动页,投票写操作,无公开读端点 | **本轮不收录**(拍板 2);非目标清单记一行(注记 ⑨) |
| G11(新) | deng 众测 IQ 复活 | 匿名渲染可读,新 DOM 契约(§4) | **接众测 IQ 渲染读取器,五站对齐**(拍板 3/4,ADR-0004) |

## 4. deng 渲染探针(匿名,ego-browser,2026-09-20)

探针前提:`whoami` 返回 404(未登录态);页面加载后 `#iq-body` 由 JS 挂载(初始「加载中……」),约 20s 内完整出数据。证据:`.lazyzcode/evidence/cr-deng-rendered.png`(渲染截图)、`.lazyzcode/evidence/cr-deng-iq-rendered.html`(渲染后 iq-body outerHTML,223,630B)。

- **规模**:70 个 `[data-iq-score]` 数据格;20 张 harness 卡(`.iqcard`)。
- **每格结构**(`type=button` `.class=eff`):`data-model`(如 `gpt-6-astra`)、`data-effort`(ultra/max/xhigh/high/medium/low)、`data-strength-rank`、`data-iq-score`、`data-iq-p`、`data-iq-n`、`data-count-p`、`data-count-n`、`data-covered-tasks`、`data-total-tasks`、`data-coverage-insufficient`、方法论 `title`(「IQ:每格最近 3 次,全部任务等权;价格和时间:最近 3 次有效运行,普通平均。价格为 API 等价成本…」)。
- **趋势**:252 个 `<circle data-trend-label="09/19 05:00 · 106.5 IQ">`,时间窗 09/19 05:00 → 09/20 04:24(≈24h 逐小时)——旧 v1 读取器的「24h IQ 曲线」概念以**内嵌 SVG 标注**形态回归。
- **harness 卡全集**(20 卡类名):model-iq / baseline-iq / stable-subscription-iq / zcode-iq / deepseek-iq / dsh-iq / claude-code-iq / grok-iq / kimi-iq / codebuddy-iq / antigravity-iq(-card);系列标签形如「with Codex」「with ZCode」。与 App 站点可对齐的五张:**codex、claude-code、dsh、zcode、grok**;kimi 对应占位站(不挂),deepseek/codebuddy/antigravity 无对应站(不采)。
- **旧 v1 契约标记**:`data-iq-hours`=0、`.total-iq`=0——v1 读取器维持终态失败,ADR-0002 对旧 iq-history 契约的退役判断不变。
- **数据来路**:deng 前端从 `/api/v1/*`(Bearer 凭据域)拉取后渲染进 DOM;合规路径仅渲染读取(最后手段,CONTEXT.md 定位),禁域不放宽。

## 5. 拍板记录(2026-09-20 grill 六题,grilling 逐题确认)

1. **总方向**:照实施 v0.4.0(spec v1.1 + issue #3);9/20 重勘以本档案 + spec v1.2 微修注记吸收,冻结决策 ④⑤⑥⑦ 不动。
2. **鹈鹕杯**:本轮不收录;本档案记录板块与理由,非目标清单补一行(链接化选项保留)。
3. **deng**:接「众测 IQ」——新增渲染读取器(对 ADR-0002「未来新开读取器但不再是 deng」条款的实质修订 → ADR-0004);匿名探针坐实可行。
4. **deng 范围**:五站对齐多卡(Codex/Claude Code/DSH/ZCode/Grok 各一张「众测 IQ」卡);kimi/deepseek/codebuddy/antigravity 卡不采。
5. **Fast 雷达**:页面从导航/路由隐藏;sidecar(FastRadarHistoryAdapter)同步继续;恢复条件 = 上游 JSON 切新结构(以实测为准,不猜契约)。
6. 机械项随 ①:spec v1.2 注记 astra/ultra 容纳、DSH 白名单核对集扩充、聚合站 Kimi 转正前仅四实站并集。

## 6. 结论

v0.4.0 **照实施**(spec v1.1 架构与契约全部维持),增量以 spec v1.2 九处注记落盘:①状态头 v1.2;②§1.1 增补行指向本档案;③新增 deng 众测 IQ 读取器契约节;④§4.1 五站「众测 IQ」卡注记;⑤Fast 雷达隐藏+同步继续注记;⑥DSH 白名单核对集扩充;⑦聚合站四实站并集注记;⑧astra/ultra 容纳 + current.json 停更留意;⑨非目标补鹈鹕杯一行。领域产物:ADR-0004(deng 众测 IQ 渲染读取器)+ CONTEXT.md「众测 IQ」术语。issue #3 追加本档案增量小节,状态与标签不动。

## 证据文件(.lazyzcode/evidence/,planning 期捕获)

| 文件 | 内容 | 大小 |
|---|---|---|
| cr-deng-rendered.png | deng 渲染探针整页截图 | 675,248B |
| cr-deng-iq-rendered.html | 渲染后 `#iq-body` outerHTML | 223,630B |
| cr-current.json | current.json 存档 | 94,731B |
| cr-insights.json | /api/radar-insights 存档 | 29,345B |
| cr-fast.json | /data/fast-radar-history.json 存档 | 132,875B |
| cr-iem.json | /data/intelligence-efficiency.json 存档 | 6,741,812B |
| cr-vsr.json | /api/visual-spatial-reasoning 存档 | 1,586,382B |
| cr-ratings.json | /api/model-ratings 存档 | 50,420B |
| cr-cup.html | /cup/ 活动页存档 | 2,508B |
