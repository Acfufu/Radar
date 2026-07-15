<!-- markdownlint-disable -->

<div align="center">

# Claude Radar

<div>
  <img alt="平台：macOS 26 或更高版本" src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white">
  <img alt="版本 0.1.0" src="https://img.shields.io/badge/version-0.1.0-4C8BF5">
  <img alt="状态：本地 QA 预览" src="https://img.shields.io/badge/status-local_QA_preview-D97706">
</div>

<br>

简体中文 | [English](README.md)

用于查看模型 Benchmark 快照、趋势、来源健康状态与可复现导出的原生 macOS 工作台。

Claude Radar 将兼容 Claude Code Radar 的快照数据整理为菜单栏摘要和完整 SwiftUI 工作区。Release 构建会自动同步公开的 Claude Code Radar 来源，并按已批准的项目边界在本地保留规范化历史。

</div>

<!-- markdownlint-restore -->

## 下载与安装

Claude Radar 目前从源码构建，需要 macOS 26 或更高版本、Xcode 26 与 Swift 6.2。

```bash
git clone "https://github.com/Acfufu/Radar.git"
cd Radar
./Scripts/build-app.sh release
open .build/app/ClaudeRadar.app
```

生成的应用只进行本地 ad-hoc 签名，尚未完成面向外部分发的公证。

## 亮点功能

- 汇总模型数量、质量、成本效率、来源 revision、配额估算与质量/成本 Pareto 前沿。
- 支持模型指标搜索、排序、动态列展示和单模型详情查看。
- 展示质量、成本、Token 与耗时的历史趋势，并避免连接来源 revision 不一致的数据。
- 独立维护 Benchmark、社区评分和来源状态；单个分段失败不会抹除其他可用数据。
- 在本地保留规范化历史与受限的原始诊断样本，并提供明确的数据清理入口。
- 将选定数据集导出为带 manifest 的分页 JSON ZIP，支持日期范围和可选原始样本。
- 主工作区关闭后仍可驻留菜单栏，并可由用户设置为登录时启动。

## 使用说明

Release 构建会在启动时自动同步，并在菜单栏进程运行期间持续按策略同步。若要改用确定性的脱敏开发 fixture 体验界面：

```bash
./Scripts/build-app.sh debug
RADAR_FIXTURE_MODE="ui" \
RADAR_DATA_ROOT="/tmp/ClaudeRadar-Demo" \
.build/app/ClaudeRadar.app/Contents/MacOS/ClaudeRadar
```

通过侧边栏进入“概览”“模型”“趋势”“来源状态”和“导出”。菜单栏中的瞄准镜图标会显示精简质量摘要，也可用于重新打开工作区。

如需运行时 QA 使用的确定性同步序列，请将 `RADAR_FIXTURE_MODE="ui"` 改为 `RADAR_FIXTURE_MODE="sequence"`，并指定一个全新的 `RADAR_DATA_ROOT`。

## 数据与导出

Claude Radar 默认将本地数据保存在：

```text
~/Library/Application Support/ClaudeRadar/
├── Radar.store
└── RawSamples/
```

导出内容可包含模型、Benchmark 运行、社区评分、来源状态，以及用户主动选择的当前保留原始样本。每个 ZIP 都包含分页 JSON 文件和 `manifest.json`；分页大小与日期范围可在“导出”页配置。

设置中提供“清除规范化历史”和“清除原始诊断样本”两个独立操作。仅删除应用不会自动删除这两类数据。

## 隐私与权限

- Release 构建会在启动、定时、网络恢复、睡眠唤醒和用户手动刷新时访问公开的 Claude Code Radar 接口。
- 项目所有者已于 2026-07-15 批准自动同步、合理缓存、本地历史留存和应用内再展示。该项目边界不构成对关联、背书或第三方许可授予的声明。
- Debug fixture 模式仍用于确定性的本地开发 QA；仓库内 fixture 已经过人工脱敏。
- 规范化历史、原始样本、偏好设置和导出文件会留在本机，除非用户自行移动或分享。
- 原始样本和导出包可能包含来源返回的内容。分享前请检查；不需要时应保持原始样本导出关闭。
- 只有用户开启“登录时启动”后，应用才会使用 macOS Service Management 注册登录项。

## 兼容性与限制

- 仅支持 macOS 26 或更高版本；没有 Windows、Linux、iOS 或 Web 版本。
- `0.1.0` 是本地 QA 预览版，并非已公证的公开发行版本。
- 在线来源仍标记为实验性，因为公开响应结构可能漂移；运行时校验和 Last-Known-Good 会隔离无效更新。
- Release 构建会主动排除 fixture JSON 和 Debug QA 资源，只使用生产 HTTP 来源路径。
- 社区评分与配额估算只是来源上下文，不会参与 Benchmark 质量、派生指标或 Pareto 计算。

## 开发说明

使用仓库脚本与 Swift Package Manager 构建、测试：

```bash
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" swift test
./Scripts/build-app.sh debug
./script/build_and_run.sh --verify
```

常用命令：

```bash
./script/build_and_run.sh run
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
```

Swift package 不含第三方包依赖。架构与发布证据见 [`docs/implementation-status.md`](docs/implementation-status.md)、[`docs/source-contract.md`](docs/source-contract.md) 和 [`docs/release-checklist.md`](docs/release-checklist.md)。

## 安全

Claude Radar 会在持久化前验证来源数据，将诊断样本限制在应用专属数据目录，并先在临时目录组装导出内容，再安装最终 ZIP。请将本地数据目录与导出包视为可能包含敏感信息的内容。执行破坏性数据清理 QA 时不要使用真实的 Application Support 目录，应在 Debug 构建中指定隔离的 `RADAR_DATA_ROOT`。

## 第三方数据

Claude Radar 与 Claude Code Radar 不存在隶属或背书关系。归属信息与当前数据复用边界见 [`docs/third-party-notices.md`](docs/third-party-notices.md)。

## 许可证状态

当前尚未指定任何许可证。除非仓库所有者明确授权，否则不得对本仓库代码进行任何复用或再分发。
