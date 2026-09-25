# codex 渲染预警读取器 v2 软退役:停调度收 UI 卡,冻结契约与代码保留待解冻

2026-09-25 HR-4 断网复核的在线灌注阶段发现(`docs/design-qa/human-review.md` HR-4 附带发现段):codexradar.com 主页自身水合把降智预警渲染面清空——服务端 HTML 标记完整(`data-radar-degradation-grid`×2、`degradation-card-score`×4、`degradation-deltas`×2,与冻结契约 `codex-radar-rendered-dom-v2` 一致,09-22/09-25 两次抓取均如此),但渲染后实测 grid=1(空)/cards=0/deltas=0,与等待时长(0.5–9s)和滚动无关;预警面板区域被「蹬友经验」知识卡与推广内容填充。读取器 v2 按 fail-safe 语义正确终态失败保 LKG(SyncMetadata `codex-radar|rendered-warnings` consecutiveFailures=2、kind=network),无数据损坏。

**与 ADR-0002 硬退役的前提差异**:deng v1 退役是服务端数据岛本身消失(`iq-body` 空壳、`data-iq-hours` 归零),读取对象不存在;本次服务端数据面完好,死的仅是客户端水合层,冻结契约可能原样复活——上游若修复水合,渲染面按 v1.2 契约原样可读。因此不构成硬退役前提,也不适用「渲染面被推广内容有意替代」的单点推断(服务端标记仍在,意图证据矛盾)。

2026-09-25 拍板(grill 逐题确认):**软退役**。停渲染预警读取器 v2 的同步调度、隐藏渲染预警 UI 卡;读取器(`CodexRenderedWarningPageReader`/`CodexRenderedWarningDOMParser`/`CodexRenderedWarningCoordinator`)、冻结契约 v1.2、测试、fixture 全部保留。`degradation_alerts` JSON 结构化路径(v1.1 双路径决策)不受影响,预警卡照常由 radar-insights 支撑——双路径并存的前提(渲染面可用)虽消失,但 JSON 路径单路径已完整承载预警数据面,用户可见能力不回退。

## 复活条件(手动解冻,不自动)

- 后续 recon 实测渲染面标记重现(grid/cards/deltas 恢复非零)且契约仍为 v1.2 → 解冻:重开调度 + 恢复 UI 卡,零代码改动。
- 若上游把预警数值移到新 DOM 锚点 → 按新实测契约重冻结(extraction 更新)再解冻;现探针未见替代标记,重冻结无对象。
- 若确认上游永久下线渲染预警面 → 升级硬退役,按 ADR-0002 退役清单先例移除代码与测试。

## Consequences

- 执行面入下一轮实现循环,连同额度雷达 trend/check/calibration 渲染、HR 口径修正(「发版硬门=清零」改「agent 可清零项清零 + 人工项列明 owner」)、hero.gif 帧序列重生成(ffmpeg 从 `docs/design-qa/baseline/v040/` 双主题截图,非实录)。
- 用户侧:渲染预警卡隐藏,现存用户的 LKG 数据不再以 stale 卡露出;预警信息由 JSON 路径卡继续承载;新装用户无空态卡。
- SyncMetadata 不再累积 `rendered-warnings` 终态失败噪声。
- 软退役不删代码不进退役清单,渲染读取器「数据面缺失时最后手段」的定位不变(ADR-0002 Consequences);本 ADR 只处置这一只读取器,不影响 deng 众测 IQ 渲染读取器(ADR-0004,同日在线同步健康)。
