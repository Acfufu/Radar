# Human Review Checklist

Maintained by the executing agent per `docs/ai-radar-refactor-plan.md` rule 8.
Every HUMAN-PENDING acceptance item gets exactly one entry; the release gate
requires this list to have zero PENDING items.

- [HR-1][R0/C0a] Icon visual variant / 图标视觉变体 — 产物: `Assets/AIRadar.icns/png`（当前为旧图标逐字节沿用；现 icon 为纯雷达图形无文字，spec §8 豁免品牌字样改写）/ 建议方法: 人工出图 AI Radar 变体后 `iconutil -c icns Assets/AIRadar.iconset -o Assets/AIRadar.icns` 重生成并复核观感 / 状态: **DONE（2026-09-08 人工拍板：沿用现图标）** — 三版代码渲染候选（A multistation / B flat / C emerald，对比材料 icon-comparison.png 与 icon-review.html——评审后未入库，本地留存于 `.lazyzcode/evidence/imagegen/`）与现行并排目视后，确认现行最成熟且纯图形无 Claude 残留，spec §8 豁免成立；资产零改动，`Assets/AIRadar.iconset` 无需生成
- [HR-2][R0/C0b] Login item visual check / 登录项目视确认 — 产物: 迁移核验记录（commit 2824c31 message）/ 建议方法: 系统设置 > 通用 > 登录项，确认 AI Radar 的登录项状态与迁移前一致（bundle ID 未变，预期无感知）/ 状态: **DONE（2026-09-09 人工确认：从未开启登录项）** — 证据：用户截图「登录项与扩展→登录时打开」（无 Radar 条目）+ System Events 登录项清单与截图逐项一致（Amphetamine/BetterDisplay/CC Switch/LocalSend/NeatDownloadManager/Snapzy/Thaw/TokenTracker/Vorssaint，共 9 项无 Radar）+ App 偏好 `launchAtLogin = 0`（`defaults read com.acfufu.ClaudeRadar`）+ 用户回忆「印象中没有出现过」——未注册过，迁移前后状态一致（均缺席），bundle ID 不变无注册漂移

## P0 reskin comparison (72 pairs)

| File | baseline bytes | p0-after bytes | Verdict |
|---|---|---|---|
| claude-code-radar__daochu__亮色__fresh.png | 317971 | 317958 | 待人工（并排目视） |
| claude-code-radar__daochu__亮色__stale.png | 317971 | 317958 | 待人工（并排目视） |
| claude-code-radar__daochu__暗色__fresh.png | 236058 | 248741 | 待人工（并排目视） |
| claude-code-radar__daochu__暗色__stale.png | 248741 | 248741 | 待人工（并排目视） |
| claude-code-radar__gailan__亮色__fresh.png | 763596 | 668171 | 待人工（并排目视） |
| claude-code-radar__gailan__亮色__stale.png | 724495 | 649903 | 待人工（并排目视） |
| claude-code-radar__gailan__暗色__fresh.png | 872482 | 739983 | 待人工（并排目视） |
| claude-code-radar__gailan__暗色__stale.png | 826235 | 719295 | 待人工（并排目视） |
| claude-code-radar__juece__亮色__fresh.png | 486809 | 487171 | 待人工（并排目视） |
| claude-code-radar__juece__亮色__stale.png | 524627 | 487171 | 待人工（并排目视） |
| claude-code-radar__juece__暗色__fresh.png | 492200 | 459925 | 待人工（并排目视） |
| claude-code-radar__juece__暗色__stale.png | 479102 | 459925 | 待人工（并排目视） |
| claude-code-radar__laiyuan__亮色__fresh.png | 390474 | 390165 | 待人工（并排目视） |
| claude-code-radar__laiyuan__亮色__stale.png | 392480 | 392214 | 待人工（并排目视） |
| claude-code-radar__laiyuan__暗色__fresh.png | 399113 | 398770 | 待人工（并排目视） |
| claude-code-radar__laiyuan__暗色__stale.png | 400920 | 400606 | 待人工（并排目视） |
| claude-code-radar__moxing__亮色__fresh.png | 432722 | 430885 | 待人工（并排目视） |
| claude-code-radar__moxing__亮色__stale.png | 430885 | 430885 | 待人工（并排目视） |
| claude-code-radar__moxing__暗色__fresh.png | 435331 | 391456 | 待人工（并排目视） |
| claude-code-radar__moxing__暗色__stale.png | 396370 | 391456 | 待人工（并排目视） |
| claude-code-radar__overview__亮色__fresh.png | 809868 | 668766 | 待人工（并排目视） |
| claude-code-radar__overview__亮色__stale.png | 722622 | 649667 | 待人工（并排目视） |
| claude-code-radar__overview__暗色__fresh.png | 887052 | 739764 | 待人工（并排目视） |
| claude-code-radar__overview__暗色__stale.png | 840840 | 719195 | 待人工（并排目视） |
| claude-code-radar__qushi__亮色__fresh.png | 499591 | 504370 | 待人工（并排目视） |
| claude-code-radar__qushi__亮色__stale.png | 500501 | 499056 | 待人工（并排目视） |
| claude-code-radar__qushi__暗色__fresh.png | 582584 | 592297 | 待人工（并排目视） |
| claude-code-radar__qushi__暗色__stale.png | 585559 | 584505 | 待人工（并排目视） |
| codex-radar__daochu__亮色__fresh.png | 368268 | 368253 | 待人工（并排目视） |
| codex-radar__daochu__亮色__stale.png | 368268 | 368253 | 待人工（并排目视） |
| codex-radar__daochu__暗色__fresh.png | 285941 | 285941 | 待人工（并排目视） |
| codex-radar__daochu__暗色__stale.png | 285941 | 285941 | 待人工（并排目视） |
| codex-radar__gailan__亮色__fresh.png | 548480 | 547845 | 待人工（并排目视） |
| codex-radar__gailan__亮色__stale.png | 533424 | 532203 | 待人工（并排目视） |
| codex-radar__gailan__暗色__fresh.png | 613427 | 606854 | 待人工（并排目视） |
| codex-radar__gailan__暗色__stale.png | 566693 | 566079 | 待人工（并排目视） |
| codex-radar__juece__亮色__fresh.png | 468390 | 468379 | 待人工（并排目视） |
| codex-radar__juece__亮色__stale.png | 468390 | 468379 | 待人工（并排目视） |
| codex-radar__juece__暗色__fresh.png | 437202 | 437202 | 待人工（并排目视） |
| codex-radar__juece__暗色__stale.png | 437202 | 437202 | 待人工（并排目视） |
| codex-radar__laiyuan__亮色__fresh.png | 393607 | 393132 | 待人工（并排目视） |
| codex-radar__laiyuan__亮色__stale.png | 394504 | 395036 | 待人工（并排目视） |
| codex-radar__laiyuan__暗色__fresh.png | 400234 | 399757 | 待人工（并排目视） |
| codex-radar__laiyuan__暗色__stale.png | 400679 | 401401 | 待人工（并排目视） |
| codex-radar__moxing__亮色__fresh.png | 443156 | 443156 | 待人工（并排目视） |
| codex-radar__moxing__亮色__stale.png | 443156 | 443156 | 待人工（并排目视） |
| codex-radar__moxing__暗色__fresh.png | 402256 | 402256 | 待人工（并排目视） |
| codex-radar__moxing__暗色__stale.png | 484173 | 402256 | 待人工（并排目视） |
| codex-radar__qushi__亮色__fresh.png | 516903 | 521733 | 待人工（并排目视） |
| codex-radar__qushi__亮色__stale.png | 516837 | 515819 | 待人工（并排目视） |
| codex-radar__qushi__暗色__fresh.png | 604524 | 611421 | 待人工（并排目视） |
| codex-radar__qushi__暗色__stale.png | 604594 | 603939 | 待人工（并排目视） |
| codex-radar__zhili__亮色__fresh.png | 687134 | 687134 | 待人工（并排目视） |
| codex-radar__zhili__亮色__stale.png | 628464 | 628450 | 待人工（并排目视） |
| codex-radar__zhili__暗色__fresh.png | 854017 | 854017 | 待人工（并排目视） |
| codex-radar__zhili__暗色__stale.png | 808362 | 808362 | 待人工（并排目视） |
| swe-bench-verified__bangdan__亮色__fresh.png | 484071 | 483124 | 待人工（并排目视） |
| swe-bench-verified__bangdan__亮色__stale.png | 484241 | 483876 | 待人工（并排目视） |
| swe-bench-verified__bangdan__暗色__fresh.png | 503968 | 503040 | 待人工（并排目视） |
| swe-bench-verified__bangdan__暗色__stale.png | 503931 | 503753 | 待人工（并排目视） |
| swe-bench-verified__daochu__亮色__fresh.png | 280034 | 280021 | 待人工（并排目视） |
| swe-bench-verified__daochu__亮色__stale.png | 280034 | 280021 | 待人工（并排目视） |
| swe-bench-verified__daochu__暗色__fresh.png | 224276 | 224276 | 待人工（并排目视） |
| swe-bench-verified__daochu__暗色__stale.png | 224276 | 224276 | 待人工（并排目视） |
| swe-bench-verified__laiyuan__亮色__fresh.png | 465197 | 464589 | 待人工（并排目视） |
| swe-bench-verified__laiyuan__亮色__stale.png | 465582 | 465253 | 待人工（并排目视） |
| swe-bench-verified__laiyuan__暗色__fresh.png | 487035 | 486123 | 待人工（并排目视） |
| swe-bench-verified__laiyuan__暗色__stale.png | 487506 | 487463 | 待人工（并排目视） |
| swe-bench-verified__qushi__亮色__fresh.png | 484109 | 483015 | 待人工（并排目视） |
| swe-bench-verified__qushi__亮色__stale.png | 484107 | 483729 | 待人工（并排目视） |
| swe-bench-verified__qushi__暗色__fresh.png | 503918 | 502654 | 待人工（并排目视） |
| swe-bench-verified__qushi__暗色__stale.png | 503848 | 503392 | 待人工（并排目视） |

## P2② efficiency ranking card (added 2026-09-05)

- [HR-3][P2②][备注 v0.4.0：自动滚动已可用——CGEvent 前台滚轮投递对 SwiftUI ScrollView 有效，见 baseline/manifest v0.4.0 段；本条可据此重执行] Efficiency-PK upstream ranking card visual review / 效能 PK 页「上游效能排行」卡目视核验 — 产物: 种子截图（本地留档，不入库）`/tmp/airadar-shots/codex-radar__xiaoneng__暗色__fresh.png`、`/tmp/airadar-shots/codex-radar__xiaoneng__亮色__fresh.png`、`/tmp/airadar-shots/codex-radar__xiaoneng-ranking__暗色__fresh.png`；渲染数据另有 AX 树结构化证据（摘要 17 模型 / 24h 267 / 48h 375 / 累计 42,903；明细行 gpt-5.6-sol·xhigh 88.4、gpt-5.6-terra·max 84.2、deepseek-v4-flash·off 71.6 含 Run 级列），记录于 issue #2 / 建议方法: 执行
  `defaults write com.acfufu.ClaudeRadar appearance '暗色'; rm -rf /tmp/AIRadar-Demo; RADAR_FIXTURE_MODE=ui RADAR_DATA_ROOT=/tmp/AIRadar-Demo RADAR_UI_STATE=fresh RADAR_UI_SOURCE=codexRadar RADAR_UI_DESTINATION="效能 PK" .build/app/AIRadar.app/Contents/MacOS/AIRadar`
  启动后手动滚动到页面底部，核对「上游效能排行」卡：摘要四项、表格 Run 级列（通过/有效、均价、均时长、均 Tokens、缓存命中、24h、总运行）、method 口径脚注（fixture 文案以「fixture：」开头为预期）、来源行署名「数据来自 Codex 雷达 codexradar.com」；说明：执行环境无法自动滚动（后台滚轮事件不达 SwiftUI ScrollView、AXScrollDownByPage 无实现、抢前台会干扰在用会话），故卡片像素留档待人工 / 状态: **DONE（2026-09-23 依 v0.5.0 滚动工具链重执行，CGEvent 前台滚轮投递实测有效）** — 像素证据 `.lazyzcode/evidence/v050-hr/codex-radar__xiaoneng-ranking__暗色__fresh.png`（暗色，深滚至卡底）与 `codex-radar__xiaoneng__亮色__fresh.png`（亮色）：摘要四项（模型 17 / 24h 267 / 48h 375 / 累计 42,903）、Run 级七列（通过/有效 291/336、均价 4.51 $、均时长 12.4 分、均 Tokens 2,210,400.5、缓存命中 95.1%、24h 9、总运行 2,104 等）、method 口径脚注以「fixture：」开头、来源行署名「数据来自 Codex 雷达 codexradar.com」全部在屏；明细行数值与 v0.4.0 AX 树记录（sol·xhigh 88.4 / terra·max 84.2 / deepseek-v4-flash·off 71.6）逐项吻合
- [HR-4][P3] Degradation-warning v2 offline re-check / 降智预警 v2 断网复核 — 产物: 降智预警读取器 v2（commit 待填，reader fallback 删除 + revision -v2）/ 建议方法: 关闭 Wi-Fi 后以 `RADAR_FIXTURE_MODE=online RADAR_DATA_ROOT=$TMPDIR/AIRadar-OfflineCheck .build/app/AIRadar.app/Contents/MacOS/AIRadar` 启动，确认预警面板保留旧数据、状态指示转 amber/red，退出后删除 QA 目录 / 状态: **DONE（2026-09-23，per-process 断网法——`sandbox-exec (deny network*)` 免关 Wi-Fi，配置存 `.lazyzcode/evidence/v050-hr/hr4-deny-net.sb`）** — 步骤：`RADAR_FIXTURE_MODE=ui RADAR_UI_STATE=warning-lkg-error` 种子写入预警 LKG（30 分钟前捕获）→ 同根 `RADAR_FIXTURE_MODE=online` 沙箱断网复启 → 像素证据 `.lazyzcode/evidence/v050-hr/hr4__offline-lkg__alerts.png`：断网下渲染预警卡完整保留 4 行 LKG（IQ 128.5/126/119/110 含 24h 降幅）、侧栏状态点转红、结构化卡 LKG 照常——fail-safe 语义实证。空态对照（无 LKG 断网启动）见同目录 `hr4__offline__alerts.png`：如实「暂无官网预警数据」。**⚠ 附带上游发现（2026-09-25）：codexradar.com 主页自身水合把 `degradation-grid` 清成空 div（服务端 HTML 标记 2/4/2 仍在，渲染后 grid=1 空/cards=0/deltas=0，与等待和滚动无关）——渲染预警读取面已无数据可读，读取器按 fail-safe 正确失败（终态网络错误、保 LKG）；`degradation_alerts` JSON 路径不受影响。下一轮 recon 需处置渲染预警读取器（退役或重冻结，ADR-0002 先例）**
- [HR-5][v0.4.0] hero.gif / hero-zh.gif refresh / 首页动图重录 — 产物: `Assets/readme/hero.gif`、`Assets/readme/hero-zh.gif`(当前仍为改名前录制的旧页序动图;录制工具链不在仓库内,`hero-motion.json` 为设计稿)/ 建议方法: 按新页序(聚合站对比视图 + Codex 九页 + 白名单站单页)重录或重生成动图;截图素材已就绪于 `docs/design-qa/baseline/v040/` / 状态: **PENDING(人工)** — 随发版人工核验清单一并闭环
