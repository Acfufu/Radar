# deng 众测 IQ 渲染读取器硬退役:deng 整站重建为速蹬天梯,契约对象消失

2026-10-27 上游重勘实测(`docs/ai-radar-upstream-recon-2026-10-27.md` §3.4):deng.codexradar.com 整站重建为「速蹬雷达 · 实时速蹬天梯」——未渲染壳从 937,533B 缩至 **10,110B**(JS 模块应用 `/agent-speed/assets/*/ladder-page.mjs`),`deng-api-origin` 指向新域 **speed-api.codexradar.com**;ego-browser 渲染探针(7s 等待,live pill=live)实测 ADR-0004 冻结契约 `deng-rendered-crowdtest-iq-v1` 的 **8 类锚点全部归零**(`data-iq-score`/`data-iq-p`/`.iqcard`/`#iq-body`/`data-iq-hours`/`.total-iq`/`circle[data-trend-label]`/`data-covered-tasks`),页面现为实时速度天梯(总榜 tok/s、按昵称实时并发行、Codex/CC-Desk/DSH harness 分解、42 人在线/71 路并发)。数据面不是暂缺、不是标记迁移,是整页换功能。

**与 ADR-0005(渲染预警软退役)的前提差异**:渲染预警是服务端数据面仍在、死的仅是客户端水合层,契约可能原样复活;本次是数据岛随整站功能消失,不存在「上游修复即原样复活」路径——与 ADR-0002(deng v1 硬退役)**同前提**。ADR-0004 的众测 IQ 读取器(v1.2 上线)自此失去读取对象。

2026-10-27 拍板(grill G3,逐题):**硬退役**,按 ADR-0002 清单先例:

- 移除读取器三件套(`CodexRenderedCrowdtestIQCoordinator`/`CodexRenderedCrowdtestIQPageReader`/`CodexRenderedCrowdtestIQDOMParser`)与 revision 常量 `deng-rendered-crowdtest-iq-v1` 及全仓触点(以 grep 为准:`RadarAppRuntime` 接线、`RadarRepository`/`SwiftDataModels`/`ContentFingerprint`、`WorkspaceProjection`/`RadarWorkspaceView`/`WhitelistStationPage`/`RadarWorkspaceModel`/`DebugUISeed`/`ClaudeRadarApp` 消费面)
- 移除五站「众测 IQ」独立数据面卡(`CrowdtestIQCard` 与 Codex/CC/DSH/ZCode/Grok 挂载;spec §4.1 v1.2 注记作废)
- fixture(`Tests/AIRadarTests/Fixtures/CodexRenderedCrowdtestIQ/`)与测试(`CodexRenderedCrowdtestIQParserTests`/`CrowdtestIQCardTests` 及 DOMParser/PageReader/Projection/Repository/SourceContract 相关断言)随退役摘除;`Package.swift` exclude 值同步
- 导出数据集随实现轮处置(ADR-0002 同款)
- origin 硬守卫(deng.codexradar.com)随代码摘除;**deng 域禁令与 `speed-api.codexradar.com` 禁域理解维持**(后者推定与 deng 旧 `/api/*` 同类提交流程,不请求、不勘察)

## Consequences

- **运行态渲染读取器归零**:deng v1 已退役(ADR-0002)、降智预警 v2 软退役中(调度停,ADR-0005)、众测 IQ 本篇硬退役——「渲染抓取是数据面缺失时最后手段」的定位不变(CONTEXT.md),未来上游若有只有渲染态的数据,仍可按此模式新开读取器,但不再是众测 IQ。
- 五站「众测 IQ」卡下线后,各站 IQ 口径只剩综合智能(radar-insights `comprehensive_points.iq` 等)与本地拟合,两两独立、永不混算的边界不变(D10 同级红线);radar-insights 结构化路径不受影响(当前因上游 502 故障临时 LKG,恢复后照常)。
- 净化禁词契约测试清单对软退役保留的降智 v2 代码继续有效(spec §6 v1.4);ADR-0004 存档不删,作为「渲染读取器生命周期管理」的先例链一环(0002 退役 → 0004 新开 → 0006 硬退役)。
