# AI Radar 全量同步重构 · 执行计划（Executor Plan）

- **执行者**：GLM-5.3-Flash-Max（下称「执行者」）
- **规格（唯一事实源）**：`docs/ai-radar-sync-spec.md`（v1.0，已经 5 轮双审定稿，并经计划五轮双审反向同步修订）。本计划只定义**执行顺序、操作步骤与验收门**；一切「做什么/为什么」以 spec 为准。本计划与 spec 冲突时，**以 spec 为准并停止执行、报告冲突**。
- **计划文件位置（终版）**：`docs/ai-radar-refactor-plan.md`（本文件，已随交付落盘）
- **环境注记**：执行宿主为 darwin arm64 / zsh；双屏 `backingScaleFactor=2.0`（1080x720 为 points，截图像素 2160x1440）；`$TMPDIR` 带尾斜杠（双斜杠无害）；本机无 GetWindowID；**执行前宿主可能无「屏幕录制」TCC 授权（`screencapture` 将硬失败 exit 1，不产出文件）——C0c pre-flight 会判定并给出合法停止点**。

---

## 0. 全局守则（每个 commit 都适用）

1. **工作流**：每个阶段开工前 `gh issue create` 建跟踪 issue 并按 `docs/agents/triage-labels.md` 打规范标签。**一次性前置（C0-pre）**：canonical 五标签中 4 个不存在——先按 triage-labels.md 名录 `gh label create` 补齐（流程就绪，非「新增标签」）；C0-pre 自身的记录并入 R0 issue。
2. **测试命令**（唯一全量门）：
   ```bash
   DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcrun swift test
   ```
   基线：R0 前为 367 tests / 46 suites 全绿（实测已验证；不符则停止并报告）。
3. **构建命令**：`./Scripts/build-app.sh debug`；产物 `.build/app/<Name>.app`。
4. **fixture UI 启动（程序化截图验证，无需人工）**。标准循环（每次采集原样使用，单次 shell 调用内完成）：
   ```bash
   defaults write com.acfufu.ClaudeRadar appearance '暗色'   # 或 '亮色'
   # 清除 SwiftUI 持久窗口 frame，否则历史 frame（如 1239x879pt）覆盖 defaultSize
   defaults delete com.acfufu.ClaudeRadar "NSWindow Frame workspace" 2>/dev/null || true
   defaults delete com.acfufu.ClaudeRadar "NSWindow Frame workspace-AppWindow-1" 2>/dev/null || true
   RADAR_FIXTURE_MODE="ui" RADAR_DATA_ROOT="/tmp/AIRadar-Demo" \
     RADAR_UI_STATE=fresh RADAR_UI_SOURCE=<source> RADAR_UI_DESTINATION=<dest> \
     .build/app/AIRadar.app/Contents/MacOS/AIRadar &          # R0 前为 ClaudeRadar
   APP_PID=$!
   WIN_ID=""
   for i in $(seq 1 30); do
     WIN_ID=$(/tmp/airadar-tools/winlist AIRadar 2>/dev/null | awk '{print $2}' | tr -d '#' | head -1)
     [ -n "$WIN_ID" ] && break
     sleep 1
   done
   [ -n "$WIN_ID" ] || { echo "window not found in 30s"; kill "$APP_PID" 2>/dev/null; exit 1; }
   screencapture -l"$WIN_ID" -o <path>.png && kill "$APP_PID"   # -o 去窗口阴影，保证像素尺寸断言成立
   # 断言：sips -g pixelWidth -g pixelHeight == 2160x1440（Retina 2x；1x 显示器按该机 scale 折算，manifest 注明）
   # 断言：文件字节数 ≥ 20000（真实基线 188KB–555KB；纯色图仅数 KB）
   ```
   `RADAR_UI_STATE` 取 `fresh|stale`；`RADAR_UI_DESTINATION` 现值域为**中文 rawValue**（概览/决策透镜/模型/趋势/智力中心/来源状态/导出），P1a 扩展后另有新值。
   **窗口枚举工具（C0c 第一个动作：编译一次，全程复用）**——`/tmp/airadar-tools/winlist.swift`，`mkdir -p /tmp/airadar-tools && swiftc -O /tmp/airadar-tools/winlist.swift -o /tmp/airadar-tools/winlist`（已实测编译运行通过；列出 owner 的 layer-0 窗口 `<Owner> #<id> <宽>x<高>`，找不到 exit 1；layer 过滤排除 MenuBarExtra 状态项）：
   ```swift
   import CoreGraphics
   import Foundation
   let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "-"
   let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
   var found = false
   for w in list {
       guard let ownerName = w[kCGWindowOwnerName as String] as? String else { continue }
       if owner != "-" && ownerName != owner { continue }
       guard let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
       guard let num = (w[kCGWindowNumber as String] as? NSNumber)?.intValue else { continue }
       guard let b = w[kCGWindowBounds as String] as? [String: Any],
             let wd = (b["Width"] as? NSNumber)?.doubleValue,
             let ht = (b["Height"] as? NSNumber)?.doubleValue else { continue }
       print("\(ownerName) #\(num) \(Int(wd))x\(Int(ht))")
       found = true
   }
   if !found { FileHandle.standardError.write("no window for '\(owner)'\n".data(using: .utf8)!); exit(1) }
   ```
   （Settings 窗口同开时取输出中面积最大的行。）
5. **裁量禁令**：spec「写死」条款不得偏离；spec 未覆盖的实现决策 → 停止并在 issue 报告。排版微调白名单（spec §12）：卡片列宽、color-mix 近似两法取一、无 runtime 站在 Settings/MenuBarExtra 的显示回落占位（如「—」）。
6. **验收门三分类（写死，防误停）**：
   - **AUTO**：执行者可用命令/断言判定的门。「连续 2 次尝试不通过 → 停止」**仅适用此类**。
   - **HUMAN-PENDING**：需人工判断的门（视觉比对、观感、系统 GUI 确认）。执行者**禁止自行判定**，产出工件与建议核验方法记入人工核验清单（守则 8），**不阻塞 commit**，不参与尝试计数；发版前必须全部闭环。
   - **EXTERNAL-RETRY**：依赖外部环境的门（网络、TCC、上游可达性）。**瞬时失败**（超时/DNS/5xx/429/Cloudflare challenge）→ 指数退避重试 ≤3 次，仍失败 → 记 `DEFERRED`（含已试命令与原始错误）入人工核验清单，继续后续 commit，发版前闭环；**结构失败**（数据可取得但 schema/DOM 与 spec 写死条款冲突）→ 立即停止。凡外部失败不得解释为裁量缺失，凡裁量缺失不得以重试消化。
   - **环境缺失（TCC 未授权/无 GUI 会话）→ EXTERNAL-ENV 合法停止点**：不适用重试计数，issue 输出人工步骤后停止（下文同此称）。
7. **commit 纪律**：一 commit 一交付物；message 首行 `phase(scope): summary`，正文列「依 spec 变更的既有断言」清单；每项 P2 附加种子截图文件名与 online 验收记录（固定字段：`日期/模式/datasetType/lastSuccessfulAt/实体计数/截图文件名/结论(OK|DEFERRED+原因)`）。
8. **人工核验清单**：执行者全程维护 `docs/design-qa/human-review.md`（随所属阶段 commit 入库），条目格式：`- [HR-nn][阶段] 事项 / 产物路径 / 建议人工核验方法（含具体命令或系统设置路径）/ 状态(PENDING|CLOSED)`。每个 HUMAN-PENDING 动作产生恰一个条目；**收尾发版门追加「清单无 PENDING 项」**。
9. **失败恢复与回滚**：任意 commit 中途失败 → 仅用 `git reset --hard HEAD`（可加**限定路径**的 `git clean`），**禁止无路径参数的 `git clean -fd`**；恢复后重跑该阶段验收门。回滚单位 = **按逆序整段回退至阶段边界**（C0-pre / R0（含 C0a–C0c）/ P0 / P1 / P2 / P3 / 收尾），不做中途单 commit 独立 revert（多文件跨 commit 纠缠）；每阶段末在 issue 记录 commit hash。回滚 C0b 后可选 `rm -rf ~/Library/Application Support/AIRadar`（仅当确认回滚后 app 不再用它），`ClaudeRadar-backup-*` 保留。
10. **禁止事项**：不请求 `api.codexradar.com` 与 deng `/api/*`；不搬运上游文案/图片/二维码/logo；不实现打分提交；不删既有测试断言除非该行为被 spec 明确变更；不改环境变量名；**online 模式一律不得在未设 `RADAR_DATA_ROOT` 时运行**（防污染真实数据目录）。

---

## 0.5 C0-pre · 文档与流程保护（docs-only commit，R0 最前）

1. `gh label create` 补齐缺失的 canonical 标签（守则 1）。
2. 将当前未跟踪文件纳入一个 docs-only commit：`docs/ai-radar-sync-spec.md`、`docs/ai-radar-refactor-plan.md`（本计划，已随交付落盘）、`AGENTS.md`、`docs/agents/`（防后续恢复操作误删唯一事实源；若个别文件不存在则以实际 `git status` 为准）。
3. 基线确认：全局测试命令跑一遍，记录 `367/46` 绿。

**验收门（AUTO）**：commit 完成；基线记录在案。

---

## 1. R0 · 重命名（2 code commits + 1 docs commit）

### C0a — 纯机械重命名 + 测试替换

**顺序（严格按此执行）**：
1. `git mv Sources/ClaudeRadar Sources/AIRadar`；`git mv Tests/ClaudeRadarTests Tests/AIRadarTests`。
2. `Package.swift`：`name: "ClaudeRadar"`→`"AIRadar"`、target 名同步、`ClaudeRadarTests`→`AIRadarTests`（exclude 值 `Fixtures/CodexRenderedWarning`、`Fixtures/CodexRenderedIQHistory` 不变）。
3. 全仓 `import ClaudeRadar`→`import AIRadar`：`grep -rlE '(@testable )?import ClaudeRadar$' Tests/` 实测恰 42 个文件。
4. `git mv Config/ClaudeRadar-Info.plist Config/AIRadar-Info.plist`；编辑：**CFBundleIdentifier 保持 `com.acfufu.ClaudeRadar` 不变**；改 CFBundleName/DisplayName/ExecutableName；`CFBundleIconFile`→`AIRadar.icns`。
5. `Scripts/build-app.sh` 与 `script/build_and_run.sh`：`ClaudeRadar` 字面量全量替换（APP_NAME、ICON_FILE、Info.plist 路径、`RESOURCE_BUNDLE` 的 `AIRadar_AIRadar.bundle`；**`script/build_and_run.sh` 的 APP_NAME 同步替换，BUNDLE_ID 保持不变**——spec §8 已列）。
6. UA：`ClaudeCodeRadarHTTP.swift:8` 改为字面量 `AIRadar/0.3.0 (macOS; +https://github.com/Acfufu/Radar)`。
7. 导出文件名前缀：`RadarExportService.swift:124` `.ClaudeRadarExport-`→`.AIRadarExport-`；`ExportView.swift:142` `ClaudeRadarExport-`→`AIRadarExport-`。
8. Assets：`git mv Assets/ClaudeRadar.icns Assets/AIRadar.icns`、同 png；**图像内容逐字节沿用**（现 icon 为纯雷达图形无文字元素，spec §8 据实豁免「品牌字样」改写；commit message 注明豁免；视觉变体入 HR 清单，由人工出图后 `iconutil -c icns` 重生成）。**禁止执行者自行绘制/生成图标**。
9. 测试机械替换（spec §8 全仓口径）：`grep -rn "ClaudeRadar" Tests/ --include='*.swift'`（第 3 步后实测 19 个非 import 文件）——**只替换**：路径串（`Sources/ClaudeRadar/`、`Tests/ClaudeRadarTests/`、`Config/ClaudeRadar-Info.plist`）、品牌子串（`Claude Radar`——实际断言形态如 `Window("Claude Radar", id: "workspace")`、`Label("Claude Radar", systemImage: "scope")`，按品牌子串替换，源码与测试两侧同串）、`.ClaudeRadarExport-`；**不替换**：生产类型名引用、**bundle ID 断言（`Phase0SmokeTests:40` `plist.contains("com.acfufu.ClaudeRadar")` 豁免）**。
10. 用户可见串：窗口标题、菜单栏、Settings 关于页（spec D2 措辞，英+中）、README/README_zh/PRODUCT.md 品牌；两份历史文档顶部加「历史存档」注记，不改内容。
11. `Phase4SourceContractTests` 新增 UA 字面量断言；**Settings 关于页 D2 声明英文与中文各加一条字面量断言**（仿 UA 先例）。

**验收门（AUTO，全过才 commit）**：
- [ ] `xcrun swift test`：全绿且总数 ≥367（基线 367/46；UA/D2 新断言使计数递增）。
- [ ] `./Scripts/build-app.sh debug` 产出 `.build/app/AIRadar.app`。
- [ ] `git log --follow` 抽查 3 个迁移文件历史保留。
- [ ] `grep -rn "ClaudeRadar" Sources/ Tests/ Scripts/ script/ Config/ Package.swift` 仅剩生产类型名与 CFBundleIdentifier 值（`environment.toml` 的 `name` 键为 autogenerated、`.codex/` 不在此 grep 路径内）；文档侧另跑 `grep -rn "Claude Radar" README.md README_zh.md PRODUCT.md` 应零命中（历史存档文档除外）。
- [ ] spec §8 硬约束自查（内务项）：`git diff --stat` 文件集清单附入 commit message，逐文件对照 spec §8 列明项。
- [ ] 中途任一步失败 → `git reset --hard HEAD` 回基线整段重做（守则 9）。
- [ ] HUMAN-PENDING 入清单：HR-图标视觉变体（闭环=收尾 iconutil 重生成接线）。

### C0b — 数据目录迁移 + 迁移测试

1. 迁移实现（spec §8 时序）：**核心抽为可注入 `(old: URL, new: URL)` 的纯函数**；`AppEnvironment.current()` 仅做路径解析并调用。守卫 =「旧目录存在且新目录不存在」；**复制失败/未完成时先删除本次创建的半成品 `AIRadar/` 再回退空目录（保证下次启动可重试；可复制到临时名再 rename 压小窗口）；`.migrated` 标记仅 advisory**；DEBUG 下 `RADAR_DATA_ROOT` 覆盖时跳过。**不重排 `AppEnvironment.swift` 的 `#else`/`onlineSourceEnabled` 区域**（ReleaseReadinessTests 源码锚定精确串）。**迁移单测内禁止出现 `~/Library` 或 `Application Support` 字面路径**（全部经注入根目录）。
2. 新增迁移单测（注入根目录）：旧目录存在→复制成功且旧目录原样；旧目录缺失→全新目录；**复制中断→半成品目录已被清理**；**标记写入失败→不阻塞、不触发重复制**；`RADAR_DATA_ROOT` 覆盖→跳过。
3. 手工核验（程序化 + 记录进 commit message；**本机若无 `~/Library/Application Support/ClaudeRadar` 则记录跳过**）：
   ```bash
   TS=$(date +%Y%m%d-%H%M%S); AS="$HOME/Library/Application Support"
   [ -d "$AS/ClaudeRadar" ] || { echo "SKIP: no legacy dir"; exit 0; }
   ditto "$AS/ClaudeRadar" "$AS/ClaudeRadar-backup-$TS"      # 兄弟目录快照
   defaults read com.acfufu.ClaudeRadar > /tmp/defaults-before
   (cd "$AS" && find ClaudeRadar -type f -exec shasum {} \; | sort) > /tmp/radar-before.sha
   # 启动 app（正常模式）→ 轮询 "$AS/AIRadar/.migrated" 出现（**≤60s；超时输出 ls "$AS" 诊断并按 AUTO 失败处理**）→ 退出 app
   (cd "$AS" && find ClaudeRadar -type f -exec shasum {} \; | sort) > /tmp/radar-after.sha
   diff /tmp/radar-before.sha /tmp/radar-after.sha           # 旧目录原样（app 退出后再跑，避免运行中写文件假差异）
   diff -rq "$AS/ClaudeRadar" "$AS/ClaudeRadar-backup-$TS"   # 与快照一致
   ls "$AS/AIRadar"                                          # 含 Radar.store/SyncMetadata.json/RawSamples
   # defaults 逐键比对：双侧先滤掉 SwiftUI 场景键（NSWindow Frame 会被启动/退出改写，产生假差异）
   defaults read com.acfufu.ClaudeRadar > /tmp/defaults-after
   diff <(grep -v "NSWindow Frame" /tmp/defaults-before) <(grep -v "NSWindow Frame" /tmp/defaults-after)
   ```
   还原（仅旧目录意外变动时）：`rm -rf "$AS/ClaudeRadar" && ditto "$AS/ClaudeRadar-backup-$TS" "$AS/ClaudeRadar" && rm -rf "$AS/AIRadar"`。备份保留至 P0 结束（P0 末可删，不删亦可，注明即可）。
4. **登录项核验两层**：程序化主层（commit 门槛）——①bundle ID 不变断言绿（登录项注册键=bundle ID，D5 充分条件）；②`out=$(sudo -n sfltool dumpbtm 2>/dev/null | grep -i clauderadar); [ -z "$out" ] && echo "SKIP: no passwordless sudo or no entry（记录时注明无法区分两者）"`；③迁移前后 `defaults read com.acfufu.ClaudeRadar launchAtLogin` 一致。人工确认层（HUMAN-PENDING 入 HR）：「系统设置 > 通用 > 登录项」目视确认。

**验收门（AUTO）**：测试全绿（≥367+迁移测试）；程序化核验全过（含超时上界）；`git log --follow` 抽查通过。HUMAN-PENDING：HR-登录项目视确认。

### C0c — 视觉基线捕获（独立 docs-only commit）

0. **准备与截图管线 pre-flight（一次性，先于矩阵）**：①`mkdir -p /tmp/airadar-tools` 并按守则 4 编译 winlist；②启动 fixture（`RADAR_UI_DESTINATION=概览`）→ winlist 枚举窗口 id → `screencapture -l<id> -o /tmp/probe-a.png`；③换 `RADAR_UI_DESTINATION=导出` 重启再截 `/tmp/probe-b.png`；④断言：两 id 均存在、两 PNG **宽 2160**（Retina 2x）、`shasum` 互异、字节数 ≥ 20000。任一失败 → 判定 TCC 未授权或无 GUI 会话（**EXTERNAL-ENV 合法停止点**，守则 6），issue 输出人工步骤：「系统设置 > 隐私与安全性 > 屏幕录制 → 为终端宿主开启授权后重跑」。MenuBarExtra 展开态若走 osascript 路线，此处一并探测辅助功能授权（**本机实测 AppleEvent -1712 超时，预期失败 → 该处直接转 HUMAN**）。
1. `mkdir -p docs/design-qa/baseline`；**外观原值保护**：`defaults read com.acfufu.ClaudeRadar appearance 2>/dev/null || echo __ABSENT__ > /tmp/appearance.orig`。
2. 矩阵 = **当时可达目的地 × 明/暗 × `fresh|stale`**：信息总览 1 + Claude 6 + Codex 7（含智力中心）+ SWE 有历史形态 4（`hasComparableHistory` 现 fixture 恒真——无历史形态 3 目的地无杠杆，**不采集，manifest 注明豁免**），共 18 目的地实例 × 2 × 2 ≈ **72 张，以 manifest 实枚为准**。文件名确定性命名 `<source>__<dest>__<theme>__<state>.png`；manifest 驱动循环、`[ -f <png> ] && continue`（**断点续拍幂等**）；每次（重）开矩阵前 `rm -rf /tmp/AIRadar-Demo`。
3. 每组合走守则 4 标准循环采集 → `docs/design-qa/baseline/<name>.png`。
4. manifest 表：目的地 × 主题 × seed × 文件名 + 豁免注记。commit 前 `find docs -name .DS_Store -delete`。**结束恢复外观原值**：`defaults write com.acfufu.ClaudeRadar appearance "$(cat /tmp/appearance.orig)"`；原值为 `__ABSENT__` 则 `defaults delete com.acfufu.ClaudeRadar appearance 2>/dev/null || true`。

**验收门（AUTO）**：manifest 覆盖全矩阵（含豁免注记）；截图全部在位且过 2160x1440/字节数断言；外观原值已恢复；`git status` 干净。

> 流程：R0 阶段 issue 开工时创建（C0-pre 后，C0-pre 记录并入该 issue）；C0a/C0b/C0c 各 commit 后在 issue 勾选并记录 commit hash（守则 9）。

---

## 2. P0 · 视觉重制（1–2 commits）

1. 按 spec §7 + §1.1 token 表重写 `RadarStyle.swift` 的 `RadarPalette`（四语义色 + soft + 双级边框 + 对比度轴）与几何常量（15/11/7、Capsule、shadow 两档、`radarAccentCard`）；`RadarAnalyticsColors` 5 色 family→四语义色+中性灰映射。**只换映射不改 API 名**（面板契约测试锚定 `analyticsLayout`/`analyticsColors(for:)` 等）。
2. 新共享组件落 `Features/Shared/`：公告横幅（两态 + v1-payload 不渲染）、状态点（四态）、星评分矩阵、月份计数表（升序补零）——**API 只接受本地 view-model**；badge 白名单注释入组件文档。
3. 重写 `RadarStyleTests`（新 token 断言 + increased-contrast 断言按对比度轴条款）。
4. 新增测试：4 组件 view-model 映射单测 + nil-data 空态单测（每组件 ≥1）+ 横幅 v1-payload 不渲染 + 月份分桶（升序补零）+ badge 白名单契约测试。
5. 更新 `docs/design-qa.md`：冻结参考改钉 codexradar.com 2026-09-04、token 全表、color-mix 近似法、family 映射、状态点四态、对比度轴、路由矩阵初版（P1b 再更新终版）。**P0 末可删除 C0b 备份目录（不删亦可，注明）。**

**验收门**：
- **AUTO（阻塞 commit）**：全量测试绿；p0-after/ 与 manifest 全矩阵无缺项（脚本比对文件名集合）；每张 PNG 过守则 4 尺寸/字节数断言；外观原值保护同 C0c。
- **HUMAN-PENDING（不阻塞，入 HR 清单，发版前闭环）**：`docs/design-qa/baseline/p0-after/` 全矩阵 + design-qa 比对表（行 = 文件对/基线字节数/p0-after 字节数/结论=待人工），建议核验方法：**与 manifest 基线并排目视**。

---

## 3. P1 · 架构站点化（3 commits）

### C-P1a — station 枚举 + 路由泛化 + 旁路 + 值域

1. Station 枚举与 rawValue/storageKey（spec §4.1 命名约定；malformed 回落语义保留）。
2. `WorkspaceRouting`/`WorkspaceRoute` 泛化 + 新目的地（§4.2 行 1–9 + 工具组；智力中心**本 commit 不下线**，仅类型层支持）。
3. 旁路改造 (a)–(g)（spec §4.1）：`RadarWorkspaceModel` 可空 runtime + 旁路、`defaultDestination`、`normalizedRoute`、`SettingsView`/`MenuBarView`/`AppCommands`；`RadarWorkspaceView.swift` **全文件处理**（含 `:162` `refreshEnabled`）；**编译联动文件按 spec §9 P1① 清单：ClaudeRadarApp.swift、AppEnvironment.debugInitialSourceID、MenuBarView、InformationOverviewView、AppCommands**。`ClaudeRadarApp.swift` runtime 构造**不增删参数**（`ReleaseReadinessTests:37` 计数锚定；确需改动则同步更新断言）。
4. 刷新语义三态（实站/聚合站依次三实站/占位站禁用+tooltip）——工具栏与 CommandMenu 同步。
5. `RADAR_UI_SOURCE` 新增值 `aggregate`/`upcoming-dsh|zcode|grok|kimi`、`RADAR_UI_DESTINATION` 随新目的地扩展。
6. 测试更新（本 commit 名点）：Station/路由/CommandMenu/旁路不崩溃（aggregate 与占位站 × Workspace/Settings/MenuBar/Command）、**`WorkspaceRoutingContractTests`（storageKey 回落语义）**、**`Phase4RuntimeSettingsTests`（`RADAR_UI_SOURCE`/`RADAR_UI_DESTINATION` 值域解析断言）**、**`WorkspaceProjectionTests:10` allCases 精确表**、**`MultiSourceWorkspaceTests:27` `destinations.last == .export`（C-P1b 还需二次改写）**、**两个 DebugFixture 测试文件（`debugInitialSourceID` 类型变 Station 即编译红）**。

**验收门（AUTO）**：全量测试绿；`RADAR_UI_SOURCE=aggregate` fixture 可启动（守则 4 循环 + `sleep 10; kill -0 "$APP_PID"` 存活判定）。

### C-P1b — Codex 站页矩阵重组 + 智力中心下线

1. 按 §4.2 矩阵重组：行 1 融合概览官方区+模型列表+官方 24h 趋势卡；行 2 降智预警升级+推荐链接卡+预测卡（nil 空态）；行 3 效能 PK（收编 3 面板，面板文件本体不重写）；行 6 历史对比（收编 2 面板）；行 4 额度雷达（窄 view-model）；**行 9 社区入口 + 社区知识文章列表卡（§12 已决：标题 + 上游自带摘要 + 外链，无摘要仅标题+外链；issue 注明该卡为 §12 决策在矩阵的落点）**；行 5/7 骨架（nil 空态）；行 8 工具组四页保留。
2. 下线智力中心目的地（`WorkspaceRouting` + 契约测试 + design-qa 路由矩阵终版）；**旧 storageKey 回落以契约测试判定**：断言 `WorkspaceRoute(storageKey: "source:codex-radar:intelligence-center")` 经 `restoreRoute`/`normalizedRoute` 回落至该站有效路由（`MultiSourceWorkspaceTests` 现有同型断言可锚）；`MultiSourceWorkspaceTests:27` 二次改写（`last` 恢复 `.export`）。（注：路由持久化在 `@SceneStorage`，无法经环境变量注入真实旧 key 启动路径——不使用「以旧 key 启动 fixture」的判定。）
3. `CodexRenderedIQHistoryOverviewContractTests` 迁挂新页锚定（全文件重锚 + `:59` 路径前缀）。
4. 测试：路由契约、`WorkspaceProjectionTests`/`WorkspacePresentationContractTests`/面板契约系列（`CodexAnalyticsPanelsContractTests.integrationContract`、`CodexIQHistoryPanelContractTests.integrationAndProvenanceContract` 重锚智力中心组合序）；社区知识卡两态单测。

**验收门（AUTO）**：全量测试绿；①主轴 1–9 顺序 = 路由契约测试断言；②旧 storageKey 回落 = 上条契约测试断言绿；③逐目的地截图按守则 4 管线自动采集入库留档（视觉正确性归 HR 抽查，**HR 条目随本 commit 建立，状态 PENDING，建议核验方法：与 manifest 基线并排目视**）。

### C-P1c — 聚合站 + 占位站 + 侧栏 + MenuBarExtra + README

1. 聚合站页（状态卡/新鲜度点、无横幅无导出，D10）+ 占位站「即将开放」卡（**主文案 + 副文案列站名 DSH/ZCode/Grok/Kimi**）。
2. 侧栏三 Section 顺序（§4.1 写死）；MenuBarExtra 状态点四态。
3. README/README_zh fixture 命令全量更新（新值域）。
4. 测试：侧栏顺序单测（§4.1 写死序列逐项断言）、占位站主/副文案断言、状态点四态映射、聚合站不可导出负向断言（**落点 `WorkspaceSupportSurfaceTests`**）。

**验收门（AUTO）**：全量测试绿；聚合站/占位站选中态全表面不崩溃（复跑 C-P1a 旁路测试组）；侧栏顺序以单测为判定；**一律**留档 `RADAR_UI_SOURCE=aggregate` 启动截图并入 HR 清单（人工复核，状态 PENDING）。

---

## 4. P2 · 数据面（5 commits，严格顺序）

> **每项 C-P2 的通用验收门**：
> - ①全量测试绿（AUTO）。
> - ②**online 验收（程序化代理，EXTERNAL-RETRY）**：**一律以 `RADAR_DATA_ROOT="$TMPDIR/AIRadar-OnlineQA-<phase>"` 启动（禁止未设 RADAR_DATA_ROOT 跑 online；TMPDIR 尾斜杠致双斜杠无害）**；`RADAR_FIXTURE_MODE=online` 启动 → 轮询 ≤120s 等同步 → 退出 → **主判据**：`SyncMetadata.json` 对应 datasetType 的 `lastSuccessfulAt` 非 nil；**辅判据**：store 内对应归一化实体计数 >0（`sqlite3 "$DATA_ROOT/Radar.store" 'SELECT COUNT(*) FROM Z<实体名>;`——SwiftData/Core Data `Z` 前缀命名约定；「面板非空」以此等效判定）；按守则 7 固定字段记录。网络类失败按守则 6 分级（瞬时→DEFERRED 不计停止；结构性→停止）；QA 数据目录用后即删。
> - ③fixture 隔离自动测试绿（`ui/disabled` 零网络）。
> - ④种子截图文件名与 seed 名入 commit message。
> - **⑤专属**：无新 datasetType/面板，online 门=复验**①–③**的三新数据集在 online 同步后出现在导出 manifest/page 并记录（或注明豁免理由；④ ModelRatings 无新实体，不适用）。

### C-P2① — CodexCurrentV2 升级

1. DTO 扩展（全 Optional）：Run 级 5 字段 + `recent_days`/`data_source`/`quota_calibration`/`quota_check`/`quota_radar.trend`；顶层 window/status/recommended_action/window_open/timezone/prediction/tibo_presence（键名精确按 spec §1.1，含 safety_note_en/zh）。
2. 新实体 `CodexRadarStatusSnapshotEntity`（window+prediction+tibo_presence 同表）——**不新增 `RadarDatasetType`**，随 sourceStatus 主链同步落库。
3. 连锁：`SourceStatusDataset` 扩展 + `ContentFingerprint.sourceStatus`（trend 不排序）+ `verifiedSourceStatus`；`BenchmarkDataset` 扩展 + `ContentFingerprint.benchmark`；**`CodexRadarParser.project`**；`DebugUISeed` 构造点。
4. 重开迁移测试初版（仿 `upgradePreservesHistory`）。
5. 投影与展示（全部新面板来源行**含署名原串「数据来自 Codex 雷达 codexradar.com」**+字面量断言）：横幅/状态徽章/预测卡；tibo 卡（**行为断言三件套：`should_display=false` 整卡隐藏含 safety_note；`safety_note_zh` 优先 `_en` 兜底；摘要 `evidence_summary_zh/en` 原文直出不拼接**）；额度 trend+check+calibration（窄 view-model）；**历史对比/对比表新列（human 可读值直显 + `cost_usd_basis` 脚注；不走 `CodexHistoryMetric`，`count == 6` 存活）**。
6. 测试：parser v1 兼容回归 + v2 fixture；指纹连锁；实体测试（**含 `CodexRadarStatusSnapshotEntity` 清除/去重路径各 ≥1**——不在 datasetType 内，`deleteNormalizedHistory` 循环不覆盖）；D13 断言 + tibo 三件套。
7. Settings 关于页：quota 口径核验（source-account estimate, never personal user usage）+ **写入署名原串「数据来自 Codex 雷达 codexradar.com」（与面板同串）并加字面量断言**。

### C-P2② — IntelligenceEfficiencyDataset 适配器

1. sidecar 全套：专属 transport（**8MiB** 两处）+ Coordinator + triggerObserver + `RadarDatasetType` 新 case + performStart 接线 + `synchronizationEnabled` 总闸 + raw-sample（既有 prune）+ SyncMetadata。
2. `IntelligenceEfficiencySnapshotEntity` + 重开迁移测试增量；`RadarRepositoryTests` allCases 计数与位置数组扩展。
3. `Dataset/Adapter` 后缀命名；`Phase4SourceContractTests`：`intelligence-efficiency` 否定断言改写 + **`api.codexradar.com` 与 deng `/api/*` 契约否定断言（落点=本 commit）** + transport host 白名单断言（`request.host == "codexradar.com"`）。
4. 效能 PK 页接数据（含 Run 级新列展示）+ 来源行署名原串 + 种子截图。
5. fixture（含 SHA-256）+ 8MiB 上限/超限 LKG 测试 + 零网络隔离测试。
6. **Settings 关于页边界段落追加本端点披露**（公开 GET、署名、禁域）。

### C-P2③ — FastRadarHistory 适配器

1. sidecar 模式 + **专属 transport 8MiB 两处（spec §5.0/§10 统一口径）** + `FastRadarRunEntity`（**每 sync 整体替换不累积** + 正负向测试）+ 派生指标（独立 evaluate 函数）+ 重开迁移测试增量 + `RadarRepositoryTests` 扩展。
2. Fast 雷达页接数据（当前对比 + 历史 + 月份计数表）+ 来源行署名原串 + 种子截图。
3. transport host 白名单断言 + fixture + 上限/隔离/替换测试。
4. **Settings 关于页边界段落追加本端点披露**。

### C-P2④ — ModelRatings 升级

1. group/effort 开放集合解析（`group: String?` 未知值原样保留）；7 天/24h 矩阵（`history[]` 尾部/当日桶）；`my_scores` 只读（D12 负向测试）。
2. 星评分矩阵接数据（effort 后缀标签 = badge 白名单位）+ 「去上游打分」链接 + 来源行署名原串 + 种子截图。
3. fixture + 测试。

### C-P2⑤ — 导出扩围

1. 3 新实体入 ExportManifest/ExportPage（per-dataset envelope；schemaVersion 维持 1）。
2. `RadarExportServiceTests`：ExportDataset.allCases 精确表 + 新 dataset manifest/page 测试 + 聚合站不可导出断言。
3. 测试 + 种子截图（导出面）；online 门按 ⑤ 专属口径。

**P2 阶段末**：online manual 步骤汇总写入 release-checklist（记录手段，不替代各项已执行验收）。

---

## 5. P3 · 渲染读取器（1–2 commits）

1. **deng v2**：**程序化勘察**（非人工）：`curl -sSL -o /tmp/deng-snapshot.html https://deng.codexradar.com/` + grep 结构标记计数成表（`iq-body|iq-range|iqcard|data-iq-|station-dashboard|site-overview|ticker` 等）；若 JS 渲染致与 spec §1.1 不符，改一次性 WKWebView 渲染脚本 dump outerHTML；标记表与快照 shasum 入 issue/commit 作审计锚（结构性冲突 → 停止）。→ 重写 extraction script（revision `-v2`；触点以全仓 grep `codex-radar-rendered-iq-history-v1` 为准——实测 `.swift` 9 处 + fixture JSON 10 处；**逐断言区分「解析输出比较」vs「测试数据构造」，仅前者随 revision 改写**）；fixture：仅重录 DOM 派生 fixture（live 读取→净化脱敏→SHA256SUMS 重算），合成错误 fixture 保留并按 v2 形态适配；**重录后人工过目全部新 fixture 全文（HUMAN-PENDING 入 HR）**；**nonPersistent 与既有净化禁词清单沿用不动，禁词仅增补不删减**（增补 `beacon`、`cf_chl`、`data:`、`mailto:`、`tel:`）；**清点三联一致：`ls <fixtureDir>/*.json | wc -l` == fixtureNames 数 == SHA256SUMS 行数**；官网 24h 趋势卡（P1b 行 1）接 v2 数据；**source-contract.md 内两处 revision 字面量随码同步**。
2. **降智预警 v2**：删 `data-radar-metric` 回退分支（`:193-196`）；revision `-v2`（grep 同法，区分输出比较与数据构造）；**契约断言锚定存活的 4 个 data-radar-degradation\* 标记**；**Cloudflare challenge 检测保留（配断言）**；删 `missing-metric.json`/`duplicate-metric.json` 与 fixtureNames 两项（`CodexRenderedWarningDOMParserTests.swift:271-275`）；其余 fixture 适配；source-contract.md 对应 revision 字面量随码同步。
3. 测试：两读取器 DOMParser/PageReader/契约/Projection/DebugFixture 全链；`Phase4SourceContractTests` revision/解析形态断言改写。

**验收门**：
- **AUTO**：全量测试绿；**LKG 判据以自动化测试为准**（超限→LKG、坏 DOM/challenge→LKG、transport 失败保留旧数据的单测全绿）。
- **HUMAN-PENDING（HR）**：app 级断网复核（建议方法：关 Wi-Fi → online 启动 → 确认面板保留旧数据且状态点转 amber/red）；新 fixture 全文过目。

---

## 6. 收尾（1–2 commits + 发版）

1. 文档：source-contract（两新端点 boundary 条目、fixture SHA-256、大小政策、D12/D13 条款、additive 不 bump、署名原串核对、**intelligence-efficiency.json 增长观测记录**）；third-party-notices（应用名、两新端点披露、tibo 披露、quota 口径）；release-checklist（路径/UA 手动步/online QA 步/路由矩阵/升级步）；implementation-status（364→实测）；design-qa 终版；README/README_zh D2 终检。
2. `CONTEXT.md`（/domain-modeling 固化 station 词汇）+ ADR（三房间→站点工作台）。
3. plist 版本步进：`CFBundleShortVersionString`→`0.3.0`、`CFBundleVersion`+1。
4. 图标复核（HR 条目闭环：人工视觉变体出图后 `iconutil -c icns` 重生成接线）+ hero.gif/README 截图重录（聚合站 + Codex 九页 + MenuBarExtra，明暗双版；**MenuBarExtra 展开态**：C0c pre-flight 已实测本机 osascript AppleEvent -1712 超时 → **直接转 HUMAN**（人工点开后台截，方法入 HR 条目）；gif 用 `ffmpeg`（palettegen/paletteuse 两遍法）程序化合成；观感终检入 HR）。
5. 发版 v0.3.0（release-checklist 全项）。

**验收门**：
- **AUTO**：全量测试绿；release-checklist 逐项勾选；issue 全部关闭。
- **发版硬门**：`docs/design-qa/human-review.md` **无 PENDING 项**。

---

## 7. 执行顺序与停止条件总表

```
C0-pre(docs) → C0a → C0b → C0c(docs) → P0 → C-P1a → C-P1b → C-P1c → C-P2① → ② → ③ → ④ → ⑤ → P3 → 收尾
```

**停止条件**（按守则 6 分类适用）：
- 基线测试与 367/46 不符（AUTO 停止）；
- spec「写死」条款与现实冲突（上游端点结构变化、DOM 结构性漂移、勘察与 spec §1.1 冲突）→ 立即停止；
- 需要本计划/spec 未授权的裁量 → 立即停止（不得以重试消化）；
- AUTO 验收门连续 2 次尝试不通过 → 停止（EXTERNAL-RETRY 类门按守则 6 分级，不适用此条）；
- TCC/无 GUI 会话等环境缺失（C0c pre-flight 判定）→ EXTERNAL-ENV 合法停止点，issue 输出人工步骤后停止。
