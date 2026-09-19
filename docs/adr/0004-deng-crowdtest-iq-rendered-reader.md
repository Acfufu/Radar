# deng 众测 IQ 以新渲染契约复活,新增五站对齐的渲染读取器(修订 ADR-0002 的「不再是 deng」条款)

deng(众测雷达)的 IQ 区在 2026-09-20 复核中以**全新 DOM 形态复活**:匿名渲染探针(whoami=404)实测 `#iq-body` 由 JS 挂载后出全量数据——70 个数据格(每格 `data-model`×`data-effort` 按钮带 `data-iq-score`/`data-iq-p`/`data-iq-n`/`data-count-p`/`data-count-n`/`data-covered-tasks`/`data-total-tasks`/`data-coverage-insufficient` 与方法论 `title`)、20 张 harness 卡(`.iqcard`,覆盖 codex/zcode/deepseek/dsh/claude-code/grok/kimi/codebuddy/antigravity 九个 harness 家族)、252 个内嵌小时趋势点(`<circle data-trend-label="MM/DD HH:00 · IQ">`,约 24h 窗口)。数据来路为 deng 前端从 `/api/v1/*`(Bearer 凭据域,禁域维持)拉取后渲染进 DOM。ADR-0002 退役的是**旧 iq-history 契约**(`data-iq-hours`/`.total-iq`,今日实测仍为 0),该判断与「IQ 历史走 iem `history[]` 数据面」的方案均不变;被修订的仅是其 Consequences 中「未来新开读取器但**不再是 deng**」一句——众测 IQ 是 deng 上新出现的、只有渲染态可得的真实数据面,构成「数据面缺失时最后手段」的正当适用。

2026-09-20 拍板(grill 逐题确认):**新增 deng 众测 IQ 渲染读取器**。非持久 WebKit、exact-origin `deng.codexradar.com`、匿名无凭据,数据集 revision 建议 `deng-rendered-crowdtest-iq-v1`(沿用渲染读取器接线模式,实现期先复跑一次探针复核标记稳定性,再冻结解析契约)。范围**五站对齐**:codex/claude-code/dsh/zcode/grok 五张 harness 卡,分别挂入 App 对应站的「众测 IQ」独立数据面卡(带 deng 署名);kimi 卡对应占位站不挂,deepseek/codebuddy/antigravity 无对应站不采。**排除项**:Bearer `/api/v1/*` 端点、kimi 之外的映射外卡、任何写操作(打分/提交)。**口径边界**:众测 IQ(最近 3 次有效运行、全任务等权)与 Codex 站综合智能 IQ、本地 IQ 拟合分属不同口径,分卡展示、署名随行、**永不混算**(D10 同级边界)。

## Consequences

- 渲染读取器是全部数据路径中维护风险最高的一类:deng 前端改版即断,断时按既有 fail-safe 语义终态失败、保 LKG;不因此放宽禁域或改拉凭据 API。
- 五站各增一张「众测 IQ」卡,UI/无障碍/测试面 ×5;卡为独立数据面,不与站内其他 IQ 口径合并、不参与跨站对比视图(聚合站不消费众测 IQ)。
- ADR-0002 其余结论维持:v1 iq-history 读取器照退役清单移除;官网 IQ 历史卡继续由 iem `history[]` 支撑,与本读取器并存、互不替代。
- 实现前置条件:实现期首日复跑匿名探针,`[data-iq-score]`=0 或需登录即本 ADR 落空,回退为「维持退役」并记录。
