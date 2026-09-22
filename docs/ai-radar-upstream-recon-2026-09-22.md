# AI Radar 上游调研档案 — codexradar.com 2026-09-22 快照

- 调研时间:2026-09-22 23:18–23:40(+08:00)
- 方法:`curl` 实测 10 个数据端点/页面(schema/键集/模型集/更新时间)+ 首页 HTML 结构化 grep;deng.codexradar.com 本轮仅做未渲染壳探针(渲染探针留待迭代验证期,上轮 09-20 匿名渲染探针仍有效)
- 目的:为「AI Radar App 下一步迭代」拍板提供上游事实基线;本档案是 `docs/ai-radar-sync-spec.md`(v1.2 冻结)的**上游重勘增量**,不替代 spec;上一轮基线见 `docs/ai-radar-upstream-recon-2026-09-20.md`
- 关联:spec v1.2、ADR-0003(白名单转正)、ADR-0004(deng 众测 IQ)、issue #3(v0.4.0 已发版但仍 open)

## 0. 总判断

**距 09-20 勘察 2 天,v0.4.0 冻结的全部数据端点契约零漂移**(radar-insights 仍 11 键 schema 1、VSR 仍 12 键 schema 1、iem 仍 schema 2、model-ratings 同构、current.json 顶层/`model_iq` 键集逐键比对与 09-20 存档一致)。实质变化有三类:

1. **fast-radar-history.json 新旧格式混跑成形**:老格式(sol/terra/luna 三件套,88 条)自 09-08 停更;新格式(逐 run 带 `model`/`effort`/`profile`/`valid_pairs`,31 条,全部 gpt-6-astra)持续增量至 09-21(昨日),`schema_version` 仍为 1、无版本提升。上轮拍板 5 的「恢复条件 = 上游 JSON 切新结构」出现**实测新事实**:新格式已是活跃写入线。
2. **额度雷达 UI/JSON 脱节(新发现)**:官网额度雷达 9/13 三档数值(`$1,919.83 Sol / $1,463.00 Astra / $1,145.10 Luna`)**服务端直出内嵌在首页 HTML**,而 current.json 内 `model_iq.quota_radar` 副本 `updated_at` 停在 **2026-08-09**(43 天)。fast-radar 式「展示层与公开 JSON 分叉」在额度雷达复现。
3. **页面层**:首页 766,595B(09-20:729,156B);头部新增 **EN 语言切换**;其余板块结构与 09-20 一致。

## 1. 线上布局与板块清单

- 站点菜单**仍 5 实站 + Kimi 占位**(`station-item-coming station-item-kimi` + 「近期开放」,grep 实证 coming 类仅 kimi 一处,其余为 CSS 规则),分站仍是前端白名单裁剪。
- 头部:logo、站点切换、主题切换、**EN 切换**(`<html lang="zh-CN">` + `>EN<` 按钮)。
- 快速入口四链接不变:加入雷达社区 / 模型主观打分 / 前往众测雷达 / 参加鹈鹕杯。
- 公告位当前为**官方重置预告**:「官方预告北京时间 9月22日 12:31」;实测 `window.opened_at=2026-09-22T12:31:32+08:00`、`status=open`、`window_open=true`、message「速蹬窗口开启」——**预告窗口当日已真实开启**(预告 vs 实开仅差 32 秒)。`prediction.level=low`,probability_24h/48h 均为 null。
- 鹈鹕杯:showzone 20 处 `/cup/` 链接;首页 JS 引用 **`/api/cup` 但实测 404「接口不存在」**——公开读端点仍不存在,上轮拍板 2 前提不变。
- 新发现公开 GET:**`/api/subscriber-count`** → `{"ok":true,"count":4271,"source":"cached"}`(订阅者计数;配套 `/api/subscribe` 推定为写操作,不采)。

## 2. 数据端点实测(2026-09-22 curl)

| 端点 | schema/键集 | 2026-09-22 实测 | vs spec v1.2 冻结契约 |
|---|---|---|---|
| `codexradar.com/current.json` | schema_version 2.0 | 顶层与 `model_iq` 键集与 09-20 存档逐键一致;window 今日开启(见 §1);**`monitored_at` 仍 2026-09-14(停更 8 天)**;`completion_observation=null`;`model_iq.comparisons` 仍 11 键 gpt_55/gpt_56 世代无 astra(换代滞后 14+ 天);`quota_radar.updated_at=2026-08-09` | 零漂移;数据新鲜度分层:window 新鲜、monitored/comparisons/quota_radar 陈旧 |
| `/api/radar-insights` | schema 1,11 键 | models=[gpt-5.5, gpt-5.6-luna/sol/terra, gpt-6-astra];efforts 含 ultra;alerts.items 当日空;source_updated_at 2026-09-22T15:02Z(抓取前 16 分钟) | 零漂移 |
| `/data/intelligence-efficiency.json` | schema 2 | 模型 **21**(新增 grok-4.7、hy4-preview、k3、gemini-3.8-flash 等);points 72;history **361**;runs_total 48,020;runs_24h_total 127;source_updated_at 2026-09-22T18:21+08:00 | 零漂移;开放集继续扩张 |
| `/api/visual-spatial-reasoning` | schema 1,12 键 | points 25;models 5(含 astra);runs_total 4,976(09-20:4,974);runs_24h_total=0 | 零漂移;24h 增量趋零 |
| `/api/model-ratings?view=public&window=7d&history=14` | 同构 | models **33**;含 GPT-6 Astra 组(如 gpt-6-astra-ultra 6.2 分/95 人);efforts 含 ultra/off | 零漂移 |
| `/data/fast-radar-history.json` | schema_version **1**(未提升) | runs **119** = 老格式 88 条(末条 09-08)+ 新格式 31 条(全 astra,末条 **09-21T10:20**);新格式字段:`model`/`effort`/`profile`/`batch_run_id`/`valid_pairs`/`sample_count`/`tps_available`/`tps_unavailable_reason`/`models.<key>{standard,fast}{ttft,tps,e2e}`;updated_at 2026-09-21 | **键集未变但内容双格式并存**;新格式即活跃线(见 §0.1) |
| 首页 HTML | — | 766,595B;EN 切换;额度雷达数值内嵌(见 §0.2) | 页面层,无数据契约 |
| `/api/cup` | — | **404「接口不存在」** | 无契约,维持不接 |
| `/api/subscriber-count` | — | 200,`{ok,count,source}` | 新公开 GET;暂无消费场景 |
| `deng.codexradar.com` | 未渲染壳 | 937,533B;`iq-body` ×14、`data-iq-score` ×3(JS 模板),无 `data-iq-hours`/`total-iq`(v1 契约仍亡) | 渲染态契约以 09-20 探针 + ADR-0004 为准,本轮无反证 |

## 3. 「UI/JSON 脱节」面盘点(本轮重点)

| 面 | 官网 UI | 公开数据面 | 判定 |
|---|---|---|---|
| Fast 加速雷达 | Astra low–max 全档 ~1.87× | 同文件双格式:老格式停更、新格式(astra)活跃 | 分叉**收窄中**:数据面已跟上 UI,唯格式过渡未宣告完成 |
| 额度雷达 | 9/13 三档(HTML 内嵌) | current.json 副本停在 08-09 | 分叉**新出现**:数据面不再承载额度最新值 |
| monitored_at | — | 09-14(8 天) | window 块仍在当日更新,「主监控」字段疑似弃维护 |
| comparisons | 站点排行已是 Astra 世代 | 仍 gpt_55/gpt_56 11 键 | 滞后 14+ 天,同 09-20 判断 |

## 4. Kimi 与白名单核对集

- **Kimi 不具备转正条件**:iem 中 `kimi-k2.8-preview` 仅 3 点——low(iq 64.86,runs_total 74)为真实数据;high/max(iq 150.0,runs_total **1**)为帽值噪声。上游站菜单仍「近期开放」。ADR-0003 白名单转正判断维持:**Kimi 占位卡不动**。
- 白名单核对集扩充候选(spec v1.2 注记 ⑥ 的再扩充):`grok-4.7`、`hy4-preview`、`k3`、`gemini-3.8-flash`、`deepseek-v4.1-flash`(非 DSH 前缀)、`dsh-deepseek-v4-flash-vision-exp`(09-20 已记)。

## 5. 官网 vs App 差距与候选议题(仅列事实与选项,拍板在 grill)

| # | 议题 | 事实 | 候选项 |
|---|---|---|---|
| C1 | Fast 雷达页面恢复 | 新格式活跃线成形(§0.1/§3);上轮恢复条件「切新结构」出现实测新事实 | (a) 维持隐藏,条件细化为 schema_version 提升或老格式清除;(b) 双格式容错解析,恢复页面 |
| C2 | 额度雷达数据源脱节 | current.json 副本 43 天未更新,官网改 HTML 直出(§0.2) | (a) 仅档案记录 + UI 数据年龄标注;(b) 额度渲染读取器(最后手段) |
| C3 | current.json 退化面 | monitored_at 8 天、comparisons 无 astra、completion_observation null | (a) 维持 LKG 现状;(b) UI 显式标注数据年龄 |
| C4 | Kimi 转正 | 数据帽值噪声(§4),上游仍 coming | 维持占位(无反证) |
| C5 | 鹈鹕杯 | /api/cup 404,无公开读端点 | 维持非目标(无反证) |
| C6 | EN 语言切换 | 站点头部新增 | (a) 非目标;(b) App 英文本地化立项 |
| C7 | deng 众测 IQ 读取器 | 壳标记无反证;ADR-0004 | 迭代验证期做一次渲染复探 |
| C8 | v0.4.0 收尾残留 | issue #3 仍 open(已发版);README/README_zh 徽章仍指 v0.2.0;打包可视化证据待刷新;签名/公证外部阻塞 | 机械收尾项 |
| C9 | 版本与跟踪 | 上一发版 v0.4.0(09-20) | 依范围定 v0.4.1 / v0.5.0;issue 拆分 + triage label |

## 6. 结论

本轮无契约破坏、无新增禁域诱惑(cup 404、subscribe 写操作均排除)。拍板焦点集中在 **C1(Fast 雷达恢复时机)** 与 **C2(额度雷达处置)**,辅以 C3/C6 取舍与 C8 机械收尾。领域产物(ADR/术语/issue)待拍板后按 domain-modeling 落盘。

## 证据文件(.lazyzcode/evidence/,planning 期捕获)

| 文件 | 内容 | 大小 |
|---|---|---|
| cr2-current.json | current.json 存档 | 94,716B |
| cr2-insights.json | /api/radar-insights 存档 | 29,272B |
| cr2-fast.json | /data/fast-radar-history.json 存档 | 136,975B |
| cr2-iem.json | /data/intelligence-efficiency.json 存档 | 7,376,902B |
| cr2-vsr.json | /api/visual-spatial-reasoning 存档 | 1,635,695B |
| cr2-ratings.json | /api/model-ratings 存档 | 50,360B |
| cr2-home.html | 首页存档 | 766,595B |
| cr2-deng.html | deng 未渲染壳存档 | 937,533B |
| cr2-cup-api.json | /api/cup 404 响应 | 27B |
| cr2-subcount.json | /api/subscriber-count 响应 | 38B |
