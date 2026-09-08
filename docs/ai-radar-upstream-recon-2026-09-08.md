# AI Radar 上游调研档案 — codexradar.com 2026-09-08 快照

- 调研时间:2026-09-08(北京时间上午)
- 方法:iab 浏览器渲染读取(codexradar.com 各 `?station=` 页 + deng.codexradar.com)+ `curl` 实测各数据端点字节与 schema + 仓库 grep 对照
- 目的:为「AI Radar App 下一步迭代」拍板提供上游事实基线;本档案为 `docs/ai-radar-sync-spec.md`(快照 2026-09-04)的**上游重勘察增量**,不替代 spec
- 关联:spec §1.1(上游快照)、§4.1(占位站契约)、§5.0(域名白名单)、D9(deng v2);loop:`.lazyzcode/plans/codexradar-recon-grill-next-iter.md`

## 1. 线上布局与板块清单

### 1.1 全局

- 页头:「AI 雷达」+ tagline「什么值得蹬」+ **站点切换下拉**(`details.station-switcher`)+ "Powered by 众测雷达"(链 deng)+ 浅色模式切换 + EN 链接(`?station=codex` 参数式路由)。
- **站点菜单(5 项)**:`./?station=aggregate`(聚合站预览)、`./?station=codex`(当前)、`./?station=dsh`、`./?station=zcode`、`./?station=grok`;页尾另有「Kimi Code 站近期开放」预告(Kimi 未进菜单)。
- 页脚:四二维码入口(蹬友群/自助站群/公众号/小助手)+ 隐私政策 + English。

### 1.2 Codex 站(`?station=codex`)自上而下

1. 公告条(当前:「GPT6-Astra 分数上线」)+ 快速入口三链接。
2. **Codex 站速览图**(info-graphic PNG,`radar-high-readout-comic-20260907-1220-readout-codex-station.png`,图注注明更新时间 9月7日 12:20)。
3. 雷达社区知识分享(5 篇文章卡:长上下文不加价 872K、任务 deep-link 协作、Max 推理强度、250 credits≈$10、推理强度中英对照)。
4. **站长推荐**(radar-insights `recommendations[]`):4 场景卡(日常开发/难题攻坚/后台自动化/跑龙虾类任务),每卡 top-2 模型档位 + IQ/耗时/费用,带说明按钮与刷新。
5. **综合智能排行**:三能力 tab 🧠综合智能 / 💻软件工程能力 / 🧩视觉空间推理;每档位卡:大号 IQ + 24h 有效作答数 + 费用 + 耗时;数据每分钟自检。
6. **综合成本 × IQ 散点图**(指标可切换:综合/时间/费用成本,全屏按钮)。
7. **IQ 历史数据**(折叠区):按模型族(Astra/Sol/Terra/Luna/5.5)分曲线,每 4 小时观察点,覆盖 8/18–9/8(约 3 周),左右滑动回看。
8. **历史数据比较**:多选模型档位 × 指标(IQ/费用/耗时/Agent steps/cache 命中率/总 tokens)。
9. **社区体感分**:`/api/model-ratings` 星矩阵(行=模型族+入/缓/出价格,列=ultra…off;7 天/24h 窗口切换;人数评分;打分 radio)。
10. **额度雷达**(8/25 更新):20x Pro 只跑 Luna $1,145.10 / 只跑 Sol $1,919.83,附 API 价折算方法。
11. **Fast 雷达**(9/6 更新):体感加速 1.367×/TTFT −0.40s/TPS 1.503× 三大卡 + Sol/Terra/Luna 明细表 + 87 次历史曲线(分页+模型/指标选择)。
12. **Tibo 雷达**:头像变更追踪(旧/新对比)、重置次数表(直接重置 vs 重置卡,按月)、Tibo 时区钟(PT)、近 48h 动态、重置时段分布图(静态 PNG)、Tibo 动态 feed(信号标签:无重置信号/间接相关,分页)。

### 1.3 预览站(`?station=dsh|zcode|grok|aggregate`)

四站均渲染「PREVIEW STATION」横幅 + 站点描述 + stats 四卡 + **同基准效能排行 + 模型档位详情**,数据真实且当日更新(9/8 07:49):

| 站 | 描述 | 最高 IQ | 已测档位 | 近 24h 运行 |
|---|---|---|---|---|
| DSH | DeepSeek Harness,DSH V4 Flash/Pro,与其他站按模型白名单隔离 | 96.1(Pro max) | 4 | 0 |
| ZCode | ZCode(GLM),GLM-5.3 各档位 | 97(max) | 3 | 1 |
| Grok | Grok 4.6 各推理档位众测表现 | 100(xhigh) | 4 | 2 |
| 聚合 | Codex+DSH+ZCode+Grok 同基准雷达图景 | 108.8(Codex·Astra ultra) | 40 可比档位 | 127 |

三站页脚注:「预览数据统一采用 DeepSWE 基准与现有缓存接口。IQ、耗时可直接横向比较;费用为参考或等效成本。」

### 1.4 分站实现机制(浏览器内实勘结论)

- 分站**没有独立数据端点**:`/api/radar-insights` 实测 `?station=dsh` 响应与无参**字节级一致**;DSH 页的网络请求与 Codex 页同一批。
- 分站 = 前端 `station-preview-dashboard-v1` 脚本内 **station→模型白名单**(`dsh-deepseek-v4-flash/pro`、`glm-5.3`、`grok-4.6`)+ 同一批端点响应按白名单**客户端裁剪**;聚合站把四站模型并表再标注来源站(`Codex ·`/`DSH ·`/`ZCode ·`/`Grok ·` 前缀)。
- `?station=` 仅是前端裁剪参数;页面为 SSR HTML + 内联脚本运行时渲染(非 SPA 框架),无 SW/CacheStorage/IndexedDB。

## 2. 数据端点清单(2026-09-08 实测)

| 端点 | 公开性 | schema | 内容 | App 现状 |
|---|---|---|---|---|
| `codexradar.com/current.json` | 公开 GET | (schema_version 键) | Codex 站主 envelope:status/window/prediction/model_iq/tibo_presence/api_access 等 | ✅ 主链 benchmark+sourceStatus |
| `codexradar.com/api/model-ratings?view=public&window=7d\|24h&history=14` | 公开 GET | ok/day/models[]{id,label,group,average,count} | 社区体感分矩阵 + 14 天历史;`view=mine` 需 credentials(排除域) | ✅ communityURL 已接(`?history=14`) |
| `codexradar.com/api/radar-insights` | 公开 GET(29KB) | schema 1 | comprehensive_points[]{model,effort,iq,software_iq,visual_iq,samples}(仅 Codex 模型)+ recommendations[](4 场景)+ **degradation_alerts**(对象) | ❌ 未接 |
| `codexradar.com/api/intelligence-efficiency-metrics` | 公开 GET | schema 2/3,benchmark=deep-swe | points[]{model,effort,iq,cost,时长,runs_24h,runs_total} **含 dsh-deepseek-v4-flash/pro、glm-5.3、glm-5.3-flash、grok-4.6 全部档位** | ❌ 未接(接的是静态变体,见下行) |
| `codexradar.com/data/intelligence-efficiency.json` | 公开 GET(静态) | **schema 2** | 同上数据面的静态版;points 含 harness 字段(`codex`×58、`dsh`×6;**glm/grok 标 `codex`**,另有 claude-opus-5/claude-sonnet-5/gemini-3.7-flash/hy4-preview/k3 等跨站模型) | ✅ P2-2 sidecar 已在同步;parser 开放集(points 开放数组、schema 不校验固定值) |
| `codexradar.com/data/fast-radar-history.json` | 公开 GET(静态) | 1 | Fast 雷达 87 run 历史;页面内另有 66KB 同内容 `<script type="application/json" data-fast-radar-history-fallback>` 兜底岛 | ✅ P2-3 sidecar |
| `codexradar.com/api/visual-spatial-reasoning`(+`-history`) | 公开 GET(777KB/4KB) | schema 1 | 视觉空间推理:benchmark=pompeii-adjacency,scoring=continuous-macro,Adjacency F1,runs_24h 62/runs_total 4742,points[] 历史 | ❌ 未接 |
| `deng.codexradar.com/`(渲染页) | 公开渲染 | — | 众测雷达提交/登录流;**`id="iq-body"` 空壳 ×1,`data-iq-hours` ×0,`.total-iq` ×0** | ⚠ v1 渲染读取器仍接线、终态失败、保 LKG |

注意:`codexradar.com/data/stations.json`、`/data/station-dsh.json` 等**不存在**(回落 SPA HTML);无任何 `api.codexradar.com` 主机请求;deng `/api/*` 为 Bearer 提交流程(维持禁域)。

## 3. 官网新功能 vs App 现状差距表

| # | 官网功能 | App 现状 | 差距 |
|---|---|---|---|
| G1 | 四预览站真实数据(聚合/DSH/ZCode/Grok) | 占位卡(spec §4.1「上游无数据」前提已失效);但 P2-2 sidecar 数据集**已含全部新站模型点**(开放集解析,UI 按 `RadarModelIdentity.family` 归组、无白名单过滤) | 导航/归组/展示层:占位→实站;数据几乎现成 |
| G2 | IQ 历史数据板块(3 周×4h 点) | deng v1 读取器(24h IQ)终态失败保 LKG;IQ 历史=官网 24h vs 本地拟合 toggle | 上游已有 IQ 历史数据面;具体端点未在本次资源列表中捕获(折叠区懒加载),deng v2 重写必要性存疑 |
| G3 | 综合智能三能力 tab(软件工程/视觉空间分量) | radar-insights 未接;visual-spatial-reasoning 未接;P2-2 效率数据有 IQ/成本/时长但无 software_iq/visual_iq 分量 | 新数据面接入(2 端点) |
| G4 | 站长推荐 4 场景卡 | 「预警与推荐」页有降智预警 v2 渲染卡;recommendations 未结构化接入(radar-insights 提供) | radar-insights 接入即得 |
| G5 | degradation_alerts JSON 化 | 降智预警走**主页渲染读取 v2**(2026-09-05 上线) | 渲染读取仍必要?radar-insights 已含 alerts 对象——两条路径取舍待拍板 |
| G6 | 评分 7d/24h 双窗口 + 14 天历史 | communityURL 已带 `history=14`;星矩阵 7 天/24h 已实现(P2-4) | 基本对齐;历史曲线展示差距小 |
| G7 | 额度雷达/Fast 雷达/Tibo 雷达 | P2-1/P2-3 均已落地(额度雷达页、Fast 雷达页 82 run、Tibo 雷达页) | 基本对齐;Tibo 头像变更/时区钟为官网新细节 |
| G8 | Kimi Code 站预告 | Kimi 占位卡已存在(§4.1 契约) | 无差距(等上游) |

## 4. deng 现状与 D9 前提变化

- spec §1.1(2026-09-04 实测)deng 已重建为「众测雷达」,数据岛消失——本次复核**维持**:`iq-body` 仅剩空壳,`data-iq-hours`/`.total-iq` 为 0。
- App v1 读取器(`CodexRenderedIQHistoryPageReader.swift:159` fixedURL=deng,extraction revision `codex-radar-rendered-iq-history-v1`)在新 DOM 上必然 `missingRoot`/标记缺失终态失败 → coordinator 记错误、UI 保 LKG。
- **前提变化**:官网 Codex 站主页已自挂「IQ 历史数据」(3 周×4h 观察点,见 §1.2-7)——上游已把 IQ 历史纳入自己的数据面。「重写 deng 渲染读取器 v2」(spec D9)可能被「读官网 IQ 历史数据面」替代或「直接下线 24h 趋势卡」替代;「改拉禁域 API」仍被 §5.0 明令禁止,不在选项内。
- 官网 IQ 历史的具体端点本次未捕获(疑似折叠区展开时懒加载),若拍板走该路线需在实现期补一次端点勘察。

## 5. spec 变更前提(访谈拍板项的事实基础)

1. **§4.1 占位站契约的前提失效**:spec §1.1 line 21「上游 JSON 端点忽略 station 参数,非 Codex 站无独立内容与数据端点」在数据层仍成立(响应确实不分站),但**非 Codex 站已有真实数据**(经统一端点 + 前端白名单)——「占位站永不同步」的定位需重议。
2. **§5.0 域名白名单需扩面**:现状「仅 codexradar.com `/data/*` 路径与既有端点」,而「既有端点」实际已含一条同域 `/api/*` 公开 GET(`CodexRadarConfiguration.swift:19` communityURL=`/api/model-ratings?history=14`)。新数据面(radar-insights / intelligence-efficiency-metrics / visual-spatial-reasoning)均在同域 `/api/*`;`api.codexradar.com` 主机禁令与 deng `/api/*` 禁令**不受影响、建议维持**。
3. **D9 分支重议**:官网 IQ 历史数据面上线后,「重写渲染读取器 v2」与「读官网数据面/下线趋势卡」三选一。

## 6. App 触点索引(file:line)

- `Sources/AIRadar/Sources/CodexRadar/CodexRadarConfiguration.swift:17` summaryURL=`current.json`;`:19` communityURL=`/api/model-ratings?history=14`(同域 `/api/*` 既有先例)。
- `Sources/AIRadar/Sources/CodexRadar/IntelligenceEfficiencyAdapter.swift:17`、`FastRadarHistoryAdapter.swift:12`:`/data/*` sidecar 端点。
- `Sources/AIRadar/Sources/CodexRadar/IntelligenceEfficiencyParser.swift:7-33`:容错 payload(schema 可选、points 开放数组)——新站模型点已在数据集内。
- `Sources/AIRadar/Domain/CodexEfficiencyAnalytics.swift:33-48`:按 `RadarModelIdentity.family/effort` 开放归组,无模型白名单。
- `Sources/AIRadar/Sources/CodexRadar/CodexRenderedIQHistoryPageReader.swift:159`:deng fixedURL(v1,终态失败)。
- `Sources/AIRadar/Sources/CodexRadar/CodexRenderedWarningPageReader.swift:159`:降智 v2 渲染读取(codexradar.com 主页)。
- `Sources/AIRadar/Features/Workspace/WorkspaceRouting.swift:117-167`:占位站路由/命名(§4.1 契约实现)。

## 7. 截图证据(planning 期捕获,存 `.lazyzcode/evidence/`)

- `codexradar-fullpage.png`(整页,含粘性 hero 的 fullPage 重复伪影,布局以分段截图为准)
- `codexradar-station-rec-insights.png`(站长推荐 4 场景卡 + 综合智能档位卡网格 + 三能力 tab)
- `codexradar-community-ratings.png`(社区体感分星矩阵,7 天/24h 切换)
- `codexradar-fast-radar.png`(Fast 雷达三大卡 + 明细表 + 87 次历史曲线)

## 8. 结论

上游在一周内完成了从「单 Codex 站 + 静态数据文件」到「多站真实数据 + 能力分量 + IQ 历史 + 评分历史」的扩张;App 的站点化架构(P1)与 sidecar 数据面(P2)恰好接住了大部分数据,真正的拍板量集中在:**占位站转正的范围与顺序、deng v2 的三选一、同域 `/api/*` 白名单扩面、新能力维度是否本轮接入、收尾发版 v0.3.0 的时机**。以上均为访谈决策题,本档案只提供事实。
