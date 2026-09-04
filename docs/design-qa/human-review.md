# Human Review Checklist

Maintained by the executing agent per `docs/ai-radar-refactor-plan.md` rule 8.
Every HUMAN-PENDING acceptance item gets exactly one entry; the release gate
requires this list to have zero PENDING items.

- [HR-1][R0/C0a] Icon visual variant / 图标视觉变体 — 产物: `Assets/AIRadar.icns/png`（当前为旧图标逐字节沿用；现 icon 为纯雷达图形无文字，spec §8 豁免品牌字样改写）/ 建议方法: 人工出图 AI Radar 变体后 `iconutil -c icns Assets/AIRadar.iconset -o Assets/AIRadar.icns` 重生成并复核观感 / 状态: PENDING
- [HR-2][R0/C0b] Login item visual check / 登录项目视确认 — 产物: 迁移核验记录（commit 2824c31 message）/ 建议方法: 系统设置 > 通用 > 登录项，确认 AI Radar 的登录项状态与迁移前一致（bundle ID 未变，预期无感知）/ 状态: PENDING

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

- [HR-3][P2②] Efficiency-PK upstream ranking card visual review / 效能 PK 页「上游效能排行」卡目视核验 — 产物: 种子截图（本地留档，不入库）`/tmp/airadar-shots/codex-radar__xiaoneng__暗色__fresh.png`、`/tmp/airadar-shots/codex-radar__xiaoneng__亮色__fresh.png`、`/tmp/airadar-shots/codex-radar__xiaoneng-ranking__暗色__fresh.png`；渲染数据另有 AX 树结构化证据（摘要 17 模型 / 24h 267 / 48h 375 / 累计 42,903；明细行 gpt-5.6-sol·xhigh 88.4、gpt-5.6-terra·max 84.2、deepseek-v4-flash·off 71.6 含 Run 级列），记录于 issue #2 / 建议方法: 执行
  `defaults write com.acfufu.ClaudeRadar appearance '暗色'; rm -rf /tmp/AIRadar-Demo; RADAR_FIXTURE_MODE=ui RADAR_DATA_ROOT=/tmp/AIRadar-Demo RADAR_UI_STATE=fresh RADAR_UI_SOURCE=codexRadar RADAR_UI_DESTINATION="效能 PK" .build/app/AIRadar.app/Contents/MacOS/AIRadar`
  启动后手动滚动到页面底部，核对「上游效能排行」卡：摘要四项、表格 Run 级列（通过/有效、均价、均时长、均 Tokens、缓存命中、24h、总运行）、method 口径脚注（fixture 文案以「fixture：」开头为预期）、来源行署名「数据来自 Codex 雷达 codexradar.com」；说明：执行环境无法自动滚动（后台滚轮事件不达 SwiftUI ScrollView、AXScrollDownByPage 无实现、抢前台会干扰在用会话），故卡片像素留档待人工 / 状态: PENDING
- [HR-4][P3] Degradation-warning v2 offline re-check / 降智预警 v2 断网复核 — 产物: 降智预警读取器 v2（commit 待填，reader fallback 删除 + revision -v2）/ 建议方法: 关闭 Wi-Fi 后以 `RADAR_FIXTURE_MODE=online RADAR_DATA_ROOT=$TMPDIR/AIRadar-OfflineCheck .build/app/AIRadar.app/Contents/MacOS/AIRadar` 启动，确认预警面板保留旧数据、状态指示转 amber/red，退出后删除 QA 目录 / 状态: PENDING
