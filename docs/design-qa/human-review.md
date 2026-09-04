# Human Review Checklist

Maintained by the executing agent per `docs/ai-radar-refactor-plan.md` rule 8.
Every HUMAN-PENDING acceptance item gets exactly one entry; the release gate
requires this list to have zero PENDING items.

- [HR-1][R0/C0a] Icon visual variant / 图标视觉变体 — 产物: `Assets/AIRadar.icns/png`（当前为旧图标逐字节沿用；现 icon 为纯雷达图形无文字，spec §8 豁免品牌字样改写）/ 建议方法: 人工出图 AI Radar 变体后 `iconutil -c icns Assets/AIRadar.iconset -o Assets/AIRadar.icns` 重生成并复核观感 / 状态: PENDING
- [HR-2][R0/C0b] Login item visual check / 登录项目视确认 — 产物: 迁移核验记录（commit 2824c31 message）/ 建议方法: 系统设置 > 通用 > 登录项，确认 AI Radar 的登录项状态与迁移前一致（bundle ID 未变，预期无感知）/ 状态: PENDING
