# AI Radar 上游调研档案 — codexradar.com 2026-10-27 快照

- 调研时间:2026-10-27(+08:00)
- 方法:`curl` 实测数据端点/页面(大小/SHA/schema/键集 jq 逐键比对,基线 = `.lazyzcode/evidence/cr2-*` 09-22 存档)+ **ego-browser 真浏览器渲染探针**(首页渲染后 DOM 采样、deng 渲染采样、页面上下文 `fetch()` 重放 502 端点排除 curl 变体假象)——沿用 09-20/09-25 教训:服务端标记 ≠ 渲染态,渲染读取器判定一律以渲染后 DOM 为准
- 目的:为 v0.6.0 轮(软退役执行 + 额度雷达渲染 + HR 口径 + hero.gif)拍板提供上游事实基线;本档案是 `docs/ai-radar-sync-spec.md`(v1.3 冻结)的**上游重勘增量**,不替代 spec;上一轮基线见 `docs/ai-radar-upstream-recon-2026-09-22.md`
- 关联:spec v1.3、ADR-0005(渲染预警软退役,issue #5)、ADR-0004(deng 众测 IQ)

## 0. 总判断

**距 09-22 勘察 35 天,出现本轮三个结构性破坏 + 一起在线故障**,App v0.5.0 的多个数据面受直接影响:

1. **`current.json` 内 `quota_radar` 整体重构(schema 3)**:旧键(date/source/endpoint/updated_at/basis_*/cost_usd/raw_delta/tasks/rows/**trend**)全部消失,换为 plans 矩阵(Plus/Pro 100/Pro 200·新额度/Pro 500 × 4 模型)、`legacy_trend`(显式标注 historical_20x_estimates_not_current_matrix,末点 2026-08-09)、`recorded_at=2026-10-17`、来源改 **modeldial.com**(第三方,`reference_url`)。App 额度雷达数据面(trend 图/rows 三档值/`updated_at` 年龄锚)**全部断供**——直接撞上本轮已拍板的「额度雷达 trend/check/calibration 渲染」项,该项必须重新过 grill。
2. **`ie.json` 突破 App 8MiB 传输上限**:实测 **9,695,083B**(09-22:7,376,902B)。spec §5.0 的 sidecar transport 上限 8MiB 下,同步将走超限→LKG 失败路径。且 **`source_updated_at`/`history[-1].at`/points `latest_graded_at` 最大值均停在 2026-10-01——效能数据面已停更 26 天**(09-22 时 history 末条=抓取时刻,是活的)。双重问题:上限被突破(架构决策)+ 数据停更(新鲜度分层)。
3. **deng.codexradar.com 整站重建为「速蹬雷达 · 实时速蹬天梯」**:未渲染壳从 937,533B 缩到 **10,110B**(JS 模块应用 `/agent-speed/assets/*/ladder-page.mjs`),`<meta name="deng-api-origin" content="https://speed-api.codexradar.com">` 引入**新 API 域**。渲染探针:ADR-0004 众测 IQ 契约锚点 **8 类标记全部归零**(`data-iq-score`/`data-iq-p`/`.iqcard`/`#iq-body`/`data-iq-hours`/`.total-iq`/`circle[data-trend-label]`/`data-covered-tasks` = 0),页面现为实时速度天梯(在线 42 人/71 路并发,昵称行带 Codex/CC-Desk/DSH harness 分解)。**众测 IQ 渲染读取器对象不存在了**(v1 退役后 v1.2 上线的众测 IQ 读取器,ADR-0004),须按 ADR-0002 清单先例处置。
4. **在线故障(非契约变化)**:`/api/radar-insights`、`/api/visual-spatial-reasoning`、`/api/visual-spatial-reasoning-history` 三端点 **502**(Cloudflare 错误页 6,406B;curl 与页面上下文 `fetch()` 重放一致,排除 curl 变体假象;同域 `/api/model-ratings`、`/api/subscriber-count` 正常,故障限定在 insights/VSR 后端)。App 两个 sidecar 当前必然走 LKG。**注意:09-22 存档 cr2-insights.json(29,272B)/cr2-vsr.json(1,635,695B)仍为最后已知健康样本,契约形状未知是否变化,恢复后须重勘。**

其余:渲染预警面**仍死**(§3.5,软退役判定维持且服务端契约本身已缩水);fast-radar 双格式并跑持续、新格式多模型化 + 顶层新增 `ultrafast_runs` 全新数据面;model-ratings 开放集 33→50 模型/7→10 组;current.json 多处好消息(monitored_at 恢复等);Kimi 被上游从站点切换器**整体移除**;新公开端点 `/data/speed-radar.json`。**八个既接端点中:current.json 顶层/model_iq 键集零漂移、iem 顶层/point 键集零漂移、fast 顶层 +1 additive、ratings 顶层零漂移——quota_radar 一处破坏性重构。**

## 1. 线上布局与板块清单

- 首页 **923,673B**(09-22:766,595B);渲染探针 h2 结构:站点公告(现为 Agent Speed 推广「看模型在实战中的速度表现」)→ Tibo 28 天挑战 → 雷达社区知识分享 → **◎站长推荐 / ⚠降智预警 / 降智雷达 · 新版两题(#ctt)/ 历史十题成绩 · 150分(#dcn)** → 社区体感分/10 → **#speed-radar-title 全站实时均速(新板块)** → **额度雷达 4 个套餐 · 资料收录于 2026-10-17** → 重置雷达 → Codex 优惠与额度情报 → 社群。
- 鹈鹕杯 showcase **已从首页移除**(09-22:showzone 20 处 `/cup/` 链接 + JS 引 `/api/cup`;今仅剩快速入口 1 处 `cup-quick-entry` 链接;`/api/cup` 仍 404「接口不存在」)。非目标前提不变且更弱。
- **Kimi 占位从站点切换器消失**:station-switcher-runtime-v3 配置仅 aggregate/codex/dsh/zcode/grok 五键,无 kimi;「近期开放/coming」占位菜单项不复存在(全文 grep 0 命中)。数据面新候选为 `kimi-k3`(speed-radar 遥测)与 `k3`(iem)。
- EN 切换仍在(`lang="zh-CN"` + 1 处 `>EN<`);站点切换器新增 en 文案键(`data-i18n`)——站点国际化推进,App EN 本地化仍非目标。
- `/api/docs` 引用存在但**实为页面路由**(返回与首页同字节的 HTML,923,673B),非 JSON API 文档。
- `/api/agent-speed` 同为页面路由(200,HTML 81KB),非数据端点。

## 2. 数据端点实测(2026-10-27)

| 端点 | 2026-10-27 实测 | vs 09-22 存档(cr2-*) |
|---|---|---|
| `codexradar.com/current.json` | 100,353B;schema 2.0;**顶层/`model_iq` 键集逐键零漂移**;`window` +5 键(confirmation_level/occurred_on/time_precision/source_role/official_confirmation_published_at,additive);`completion_observation` **由 null 变为 18 键富对象**(event_id/kind=direct_reset/status/confirmation_level/occurred_on/evidence_zh·en/title_zh·en/announcement_url 等,10-26 实时);`prediction` 概率**由 null 变数值**(24h=0.05/48h=0.08,updated_at 10-24);`monitored_at` **恢复=2026-10-26**(09-22 时停 09-14);`model_iq.updated_at` 仍 2026-09-13(44 天);**`quota_radar` 重构,见 §3.1** | 顶层零漂移;quota_radar **破坏性重构** |
| `/data/intelligence-efficiency.json` | **9,695,083B(>8MiB)**;schema 2;顶层/point 键集零漂移;mode 仍 equal_latest_3;models 24(points 层,21→24:+claude-opus-5-5、+gpt-6-luna、+gpt-6-sol);points 89(72→89);history **416**(361→416)但 **末条/`source_updated_at` 停 2026-10-01(26 天)**;runs_total 50,530 | 键集零漂移;**停更 + 超限** |
| `/data/fast-radar-history.json` | 313,383B;schema_version 仍 1;runs **176** = 老格式 88(末条 09-08 不变)+ 新格式 88(09-22:31)——**新格式已多模型化**:astra×48、6.1-sol×19、luna×18、6-sol×2、5.6-sol×1,末条 10-25(活跃线确认);run 级键集不变;**顶层新增 `ultrafast_runs`(additive,10 条)**:ultrafast 服务档实测(run_id/started_at/completed_at/samples[]/models{}/protocol{}/cli_version/baseline_cli_version 等,samples 内含 ttft_ms/e2e_ms/decode_tps/完整 prompt 文本) | 键集 +1 additive;新格式扩容 + 多模型 |
| `/api/model-ratings?view=public&window=7d&history=14` | 75,380B;顶层键集与 09-22 一致(13 键,`my_scores`/`my_score_records` 09-22 起即缺席,D12 面继续休眠);models **33→50**;groups **7→10**(+GPT-6 Luna、+GPT-6 Sol、+GPT-6.1 Sol;§5.4 开放集合设计成立,无需改动);history 14 天,updated 10-26(活) | 同构;开放集内扩张 |
| `/api/radar-insights` | **502**(CF 错误页 6,406B;页面内 fetch 重放同) | **在线故障**,契约未知 |
| `/api/visual-spatial-reasoning` | **502**(同上) | **在线故障**,契约未知 |
| `/api/visual-spatial-reasoning-history` | **502**(同上) | **在线故障**,契约未知 |
| `/data/speed-radar.json` | **新端点,200,11,421B**:实时社区速度遥测(kind=models、status=live、unit=tok/s、5 分钟滚动窗、refreshSeconds=10、asOf 秒级新鲜);items 14 模型(gpt-6.1-sol/gpt-6-astra/gpt-6-luna/gpt-6-sol/gpt-5.6-sol/luna/deepseek-flash/deepseek-v4-pro/glm-5.3/glm-5.3-flash/claude-opus-5/claude-opus-5-5/kimi-k3/**gemini-4-argon**);键 camelCase,每 item 含 devices/requests/spark[20] | **全新公开数据面**(App 未接) |
| `/api/cup` | 404「接口不存在」 | 维持;首页引用也移除了 |
| `/api/subscriber-count` | 200 `{ok,count:4270,source:cached}` | 活;仍无消费场景 |
| 首页 HTML | 923,673B;服务端降智标记 **2/1/1**(data-radar-degradation-grid×2 / degradation-card-score×**1** / degradation-deltas×**1**;09-22/09-25 为 2/4/2) | 页面层;预警服务端契约缩水 |
| `deng.codexradar.com` | **10,110B JS 模块壳**;渲染探针:速蹬天梯(§3.4);`deng-api-origin=speed-api.codexradar.com` | **整站重建,众测 IQ 契约灭** |

## 3. 结构性变化详录

### 3.1 quota_radar 整体重构(App 额度雷达数据面断供)

键集 diff(09-22 → 10-27):`date,source,endpoint,updated_at,basis_date,basis_window,basis_window_label,seven_day_policy,five_hour_policy,cost_usd,raw_delta,tasks,rows,trend` → `schema(=3),type(=quota_reference_snapshot),source_kind(=owner_provided_screenshot),source_updated_on(null),token_unit(=100M_tokens_per_week),currency,approximate,plans,reference_note,reference_url(=modeldial.com),source_observed_at(null),recorded_at(=2026-10-17),source_sha256,source_method(null),sample_count(null),legacy_trend`。

- **`trend`(10 条)与 `rows`(App 额度三档值来源)不存在**;DataAgeBadge 锚 `updated_at` 不存在。
- `plans[]`:4 套餐(plus $20 / pro100 $100 / pro200「新额度」$200 / pro500 $500)× 4 模型(gpt-6-astra / **gpt-6.1-sol** / **gpt-6-sol** / gpt-5.6-sol),行含 weekly_tokens_100m + weekly_api_equivalent_usd,缺样本行为 null+`status:"no_comparable_sample"`。
- `legacy_trend.points[]`:字段与旧 trend 同构(five_h_20x/seven_d_20x/five_h_5x/five_h_plus/rate/offset/cost_usd/total_tokens…),10 点,**末点 2026-08-09**,`scope:"historical_20x_estimates_not_current_matrix"`——旧序列被显式降级为历史档。
- 数据来源改为 modeldial.com(第三方参考,`approximate:true`,zh/en note 随行)——与旧「站长实测」口径不同源。
- 官网额度雷达节标题同步改「4 个套餐 · 资料收录于 2026-10-17」(服务端直出)。

**App 影响**:`SourceStatusDataset` payload 里的 quota_radar 容错解码后为空壳;额度雷达页 trend 图无数据、三档值无数据、年龄徽标无锚。v0.5.0 上线的数据年龄标注(「上游 1 个月前未更新」措辞)依赖 updated_at 字段,现在连锚都没了。**本轮已拍板的「额度雷达 trend/check/calibration 渲染」项撞上此重构,须 grill 重拍**(quota_check/quota_calibration 两块键集未变,仍可渲染)。

### 3.2 ie.json:停更 26 天 + 突破 8MiB 上限

- **停更**:`source_updated_at`、`history[-1].at`、points `latest_graded_at` 最大值全部 = **2026-10-01T23:00(+08:00)**;09-22 抓取时 history 末条 = 抓取时刻(活线)。08-09(monitored_at 旧停点)→09-14→10-01,上游「主监控节奏」的停更点在迁移。
- **超限**:9,695,083B > 8MiB(8,388,608B)。App ie sidecar 的专属 transport(两处 8MiB)将拒收走 LKG。09-22→10-01 九天涨 2.3MB(history +55 条、points +17),若上游恢复更新会继续涨。
- 键集层面顶层/point 均零漂移,数据结构本身可解;问题纯在体积与新鲜度。

### 3.3 insights/VSR 三端点 502(在线故障)

- curl 与浏览器页面上下文 `fetch()` 重放一致:502 + Cloudflare 错误页(6,406B);同域其它 `/api/*`(model-ratings/subscriber-count/cup)正常响应——故障限定在 radar-insights 与 visual-spatial-reasoning(-history) 的源站服务。
- 属在线故障非契约变化;App 两侧 sidecar 当前走 LKG(fail-safe 设计)。**09-22 存档 cr2-insights/cr2-vsr 为最后已知健康样本;恢复后第一件事重勘 schema 是否漂移。**

### 3.4 deng 整站重建 → 众测 IQ 读取器对象消失(ADR-0004)

- 未渲染壳 10,110B:`data-page="ladder"`,模块脚本 `ladder-page.mjs`,`deng-api-origin` meta 指向 **`speed-api.codexradar.com`**(根路径 404 空,API-only 域,推定与 deng 旧 `/api/*` 同类提交流程,**维持禁域理解,不请求**)。
- 渲染探针(7s 等待,live pill=live):ADR-0004 冻结契约的 8 类锚点**全部 0**;页面内容 = 实时速度天梯(总榜 tok/s、按昵称的实时并发行、harness 分解 Codex/CC-Desk/DSH、42 人在线/71 路并发/7 模型/4 harness)。
- 判定:**众测 IQ 数据面在上游已不存在**(不是标记迁移,是站点换用途)。五站「众测 IQ」卡失去数据源;读取器将按 fail-safe 终态失败保 LKG。处置候选(ADR-0002 清单先例):硬退役读取器 / 软退役(停调度收卡)/ 维持失败观察——grill 拍板,倾向硬退役(数据岛不是暂缺,是整页换功能;与 ADR-0005 渲染预警「服务端还在」的前提相反)。

### 3.5 渲染预警面:软退役判定维持(ADR-0005),且服务端契约已缩水

- 渲染探针(5s 等待):grid=1(空)/cards=0/deltas=0,与 09-25 相同——**水合清空持续,渲染面仍死**。软退役(停调度+收 UI 卡)的前提没有变化。
- **新增事实**:服务端标记从 2/4/2 变 **2/1/1**(degradation-card-score 4→1、degradation-deltas 2→1)。即使上游修复水合,v1.2 冻结契约(4 卡)也将不匹配。复活三分支中「原样解冻」路径事实上已关闭;「重冻结」需等上游水合后实测新形状;「升级硬退役」仍不满足前提(服务端标记在,只是变少)。
- 官网预警区域现被「降智雷达 · 新版两题」+「历史十题成绩 · 150分」新板块填充(ctt/dcn,渲染读取器契约外的新结构,本轮不采)。
- JSON 路径(`degradation_alerts`,radar-insights)当前因 502 不可用(§3.3),恢复后照常。

### 3.6 fast-radar:新格式多模型化 + ultrafast_runs 新面

- 新格式 88 条(31→88),**不再全 astra**:gpt-6-astra×48(low/medium/high/xhigh/max 各档)、gpt-6.1-sol×19、gpt-6-luna×18、gpt-6-sol×2、gpt-5.6-sol×1;末条 10-25,活跃线确认。run 级键集与 v1.3 冻结契约一致;App 双格式容错解析(开放键字典)无需改动即可容纳多模型。
- 老格式 88 条停更不变;schema_version 仍 1——「切换新结构」仍未宣告完成,双格式解析继续正确。
- **顶层新增 `ultrafast_runs`(10 条)**:ultrafast 服务档实测,结构全新(run_id/started_at/completed_at/samples[]/models{astra,sol}/schema_version/effort/requested_service_tier/cli_version/baseline_cli_version/baseline_interval/comparison/backend_tier_evidence/protocol{});samples 行内含完整 prompt 文本与 token 计数。additive 键,App DTO 容错忽略;**是否消费为新数据面 = grill 候选**(官网有对应「Ultrafast 有多快」社区内容)。

### 3.7 model-ratings 开放集扩张(设计红利验证)

models 33→50,groups 7→10(新增 GPT-6 Luna/GPT-6 Sol/GPT-6.1 Sol 组),effort 含 ultra。§5.4 开放集合(group: String? + 未知原样渲染)无需改动。my_scores/my_score_records 持续缺席(D12 面休眠,DTO Optional 无影响)。

### 3.8 current.json 好消息面

- **`monitored_at` 恢复**(10-26,44 天停更结束);`completion_observation` 首次携带富对象(18 键,站长确认证据链含 announcement_url/evidence_zh·en);`prediction` 概率首次为数值(0.05/0.08);`window` +5 additive 键(confirmation_level/occurred_on/time_precision/source_role/official_confirmation_published_at)。
- 新鲜度分层现状(2026-10-27):window/completion_observation/monitored_at **新鲜**;prediction 3 天;quota_radar.recorded_at 10 天(且换了源);model_iq.updated_at **44 天**;comparisons 仍 gpt_55/gpt_56 11 键无 astra(35+ 天);tibo_presence.updated_at **2026-07-21(98 天)**,should_display=true。
- `api_access.requirements.attribution_text` 原串不变(「数据来自 Codex 雷达 codexradar.com」);`links` 3 键不变;quota_check/quota_calibration 键集不变。

### 3.9 新公开端点与候选模型

- **`/data/speed-radar.json`**:实时社区速度遥测(5 分钟窗,10s 刷新),camelCase 键,与既有 snake_case 数据面风格不同。App 无消费场景先例(实时遥测 vs 快照型),是否收录 = grill 候选(收录则需新 sidecar + 域名白名单 `/data/*` 已覆盖,路径族无需改 spec)。
- 白名单核对集更新(以 station 配置块为准):**六候选全部仍未入站配置**;新增候选 `k3`(iem,low 377/high 227/max 260 runs 真实体量)、`kimi-k3`(speed-radar 遥测)、`gemini-4-argon`(speed-radar 遥测)、`deepseek-flash`/`deepseek-v4-pro`(speed-radar 遥测命名)。claude-opus-5 系/gemini-3.7-flash 在 iem 有数据但无站(聚合对比视图仅并入有站白名单并集,不为此创设展示位)。

## 4. Kimi 与白名单

- **Kimi 占位被上游移除**:站点切换器(aggregate/codex/dsh/zcode/grok)无 kimi 键,占位菜单不复存在。数据面 kimi-k2.8-preview 仍帽值噪声(low 75 真实 / high 1 / max 3 runs,iq=150 帽值)。转正条件比上轮更远;**App Kimi 占位站维持**(统一文案「即将开放」),上游移除占位不构成 App 侧反证。
- 白名单(站→模型集,station 配置块实测):DSH=`dsh-deepseek-v4-flash`/`dsh-deepseek-v4-pro`、ZCode=`glm-5.3`、Grok=`grok-4.6`,**与 App 常量逐字一致,零更新**;`grok-4.6` harness 标签仍 `grok-build`。glm-5.3-flash 未入白名单(维持)。

## 5. App 影响面与候选议题(拍板在 grill)

| # | 议题 | 事实 | 候选项 |
|---|---|---|---|
| G1 | **额度雷达渲染项重拍**(原四件套②) | quota_radar schema 3 重构,trend/rows/updated_at 全断;quota_check/calibration 键集未变 | (a) 降级为「quota_check + quota_calibration 渲染」(数据在);(b) 加渲染 plans 矩阵新形态(第三方源署名随行);(c) 缓项等上游回填 |
| G2 | **ie sidecar 8MiB 上限** | 实测 9.7MB > 8MiB,且停更 26 天 | (a) 上限调升(如 16MiB,对齐 SWE-bench 惯例)+ 上限测试更新;(b) 维持 8MiB,LKG 等;(c) 改流式/截断策略(不推荐,超现有架构) |
| G3 | **众测 IQ 读取器处置**(ADR-0004) | deng 整站换功能,契约 8 锚全灭 | (a) 硬退役(ADR-0002 清单);(b) 软退役(停调度收卡,留复活口);(c) 维持失败观察 |
| G4 | **渲染预警软退役复核**(ADR-0005/issue #5) | 渲染面仍死 + 服务端标记缩水 2/1/1 | 维持软退役执行不变(原计划四件套①),档案记录「原样解冻」路径关闭;无新拍板必要,除非升级硬退役 |
| G5 | **insights/VSR 502 故障** | 三端点 502,恢复时间未知 | (a) 本轮仅档案记录 + 恢复后重勘;(b) 若发版前仍故障,release-checklist online 验收记 DEFERRED |
| G6 | **fast ultrafast_runs 消费** | 全新 ultrafast 服务档数据面 | (a) 本轮不接(档案记录);(b) 立项新数据面 |
| G7 | **speed-radar.json 收录** | 新实时遥测端点,5 分钟窗 | (a) 不接(非快照型,与 App 节奏不合);(b) 收录为新 sidecar |
| G8 | **current.json 新增字段展示** | completion_observation 富对象 + prediction 数值概率 + window 5 新键 | (a) 档案记录,DTO 容错已吃下,UI 不动;(b) 预测卡数值概率渲染增强 |
| G9 | **Kimi 占位** | 上游移除占位菜单;k2.8 仍噪声 | 维持占位(无反证) |
| G10 | **版本与跟踪** | 结构性破坏 3 处 + 原四件套 | v0.6.0(已拍板);issue 拆分 + triage label |

## 6. 结论

本轮**三个结构性破坏**(quota_radar 重构、ie 停更+超限、deng 换功能)全部命中 App 数据面,叠加一起在线故障(502);既接端点键集层面仅 quota_radar 一处破坏,其余零漂移或 additive。原四件套中②撞上 G1 须重拍,①按 G4 维持执行,③④不受影响。G1/G2/G3 是本轮 grill 的三个硬决策;G5–G8 为轻决策;无新增禁域诱惑(cup 404 维持、subscribe 写操作排除、speed-api 禁域理解维持)。领域产物(ADR-0006 候选:众测 IQ 处置;spec v1.4 候选:quota_radar/ie 上限)待拍板后落盘。

## 证据文件(.lazyzcode/evidence/,planning 期捕获)

| 文件 | 内容 | 大小 | SHA-256(前 12) |
|---|---|---|---|
| cr3-current.json | current.json 存档 | 100,353B | 53c11807383c |
| cr3-insights.json | /api/radar-insights 502 响应 | 16B | bb2fb7b51f18 |
| cr3-fast.json | /data/fast-radar-history.json 存档 | 313,383B | 4b7d7c113043 |
| cr3-ratings.json | /api/model-ratings 存档 | 75,380B | 61cb85fc8c55 |
| cr3-iem.json | /data/intelligence-efficiency.json 存档 | 9,695,083B | 5be93e045c80 |
| cr3-vsr.json | /api/visual-spatial-reasoning 502 响应 | 16B | bb2fb7b51f18 |
| cr3-vsr-history.json | /api/visual-spatial-reasoning-history 502 响应 | 16B | bb2fb7b51f18 |
| cr3-home.html | 首页存档 | 923,673B | 0c5ad2f4c258 |
| cr3-deng.html | deng 新版壳存档 | 10,110B | 252c78fd2122 |
| cr3-speed.json | /data/speed-radar.json 存档 | 11,421B | b74752e20270 |
| cr3-cup-api.json | /api/cup 404 响应 | 27B | c9c63cad3906 |
| cr3-subcount.json | /api/subscriber-count 响应 | 42B | c4c8729f6970 |
| probe-01.mjs | 渲染探针脚本(ego-browser,/tmp/radar-recon-1027) | — | — |
