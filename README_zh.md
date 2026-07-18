<!-- markdownlint-disable -->

<div align="center">

<img alt="Claude Radar 应用图标" src="Assets/ClaudeRadar.png" width="128" height="128">

# Claude Radar

<div>
  <img alt="平台：macOS 26 或更高版本" src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white">
  <img alt="版本 0.2.0" src="https://img.shields.io/badge/version-0.2.0-4C8BF5">
  <img alt="状态：本地 QA 预览" src="https://img.shields.io/badge/status-local_QA_preview-D97706">
</div>

<br>

简体中文 | [English](README.md)

将公开模型 Benchmark 快照转化为可执行对比、推荐、监控与可复现导出的原生 macOS 工作台。

Claude Radar 将兼容 Claude Code Radar 与 Codex Radar 的快照数据整理为菜单栏摘要和两个相互独立的 SwiftUI 工作区。主概览在同一界面呈现当前信号、模型家族健康、推理层级热力图、推荐透镜、近期表现与同步状态。当前仓库是一个**接入公开来源的本地 QA 预览版**：Release 构建会自动同步两个公开 Adapter，并保留按来源隔离的历史供后续展示。

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

- 以当前峰值 IQ 为主信号，同时呈现按来源隔离的 24 小时趋势、模型家族健康、推理层级热力图与公开订阅上下文。
- 可按最高质量、性价比、最低额度成本或最快完成生成推荐，并通过 IQ/耗时对比图及实测指标解释结果。
- 对比当前最强的五个模型与上一个兼容快照，同时展示每题成本和平均耗时。
- 实时显示数据源健康、最近同步时间、刷新间隔、历史快照数量与下一次自动检查。
- 支持模型指标搜索、排序、动态列展示和单模型详情查看。
- 展示质量、成本、Token 与耗时的历史趋势，并避免连接来源 revision 不一致的数据。
- 独立维护 Benchmark、社区评分和来源状态；单个分段失败不会抹除其他可用数据。
- Claude Code Radar 与 Codex Radar 使用独立的工作区、历史和导出范围，不合并模型或分数。
- 在本地保留规范化历史与受限的原始诊断样本，并提供明确的数据清理入口。
- 将选定数据集导出为带 manifest 的分页 JSON ZIP，支持日期范围和可选原始样本。
- 主工作区关闭后仍可驻留菜单栏，可由用户设置为登录时启动，并支持跟随系统、亮色或暗色外观。

## 使用说明

Release 构建会自动启动两个公开来源的运行时。切换来源只改变当前展示的工作区，不会停止后台同步。若要改用脱敏开发 fixture 体验界面：

```bash
./Scripts/build-app.sh debug
RADAR_FIXTURE_MODE="ui" \
RADAR_DATA_ROOT="/tmp/ClaudeRadar-Demo" \
.build/app/ClaudeRadar.app/Contents/MacOS/ClaudeRadar
```

“概览”会针对当前来源集中展示主信号、热力图、决策透镜、近期表现和实时同步监控。通过目标控件可在质量、性价比、额度成本与速度之间切换推荐。侧边栏还提供“模型”“趋势”“来源状态”和“导出”。菜单栏中的瞄准镜图标会显示精简质量摘要，也可用于重新打开工作区。

在“设置 → 通用 → 外观”中可选择“跟随系统”“亮色”或“暗色”；该偏好会统一应用于主工作区、菜单栏面板和设置窗口。

如需运行时 QA 使用的确定性同步序列，请将 `RADAR_FIXTURE_MODE="ui"` 改为 `RADAR_FIXTURE_MODE="sequence"`，并指定一个全新的 `RADAR_DATA_ROOT`。

若要使用脱敏 fixture 验证 Codex Radar Adapter 和来源切换器：

```bash
RADAR_FIXTURE_MODE="codex" \
RADAR_DATA_ROOT="/tmp/CodexRadar-Demo" \
.build/app/ClaudeRadar.app/Contents/MacOS/ClaudeRadar
```

## 数据与导出

Claude Radar 默认将本地数据保存在：

```text
~/Library/Application Support/ClaudeRadar/
├── Radar.store
├── SyncMetadata.json
└── RawSamples/
```

导出内容可包含模型、Benchmark 运行、社区评分、来源状态，以及用户主动选择的当前保留原始样本。每个 ZIP 都包含分页 JSON 文件和 `manifest.json`；分页大小与日期范围可在“导出”页配置。

设置中提供“清除规范化历史”和“清除原始诊断样本”两个独立操作。仅删除应用不会自动删除这两类数据。

## 隐私与权限

- Release 构建会在启动时及设定的刷新周期内同步两个来源的已记录公开接口。
- Debug fixture 模式只使用人工脱敏的本地数据；显式 `online` QA 模式会在隔离数据目录中运行两个生产公开 Adapter。
- 规范化历史、原始样本、偏好设置和导出文件会留在本机，除非用户自行移动或分享。
- 原始样本和导出包可能包含来源返回的内容。分享前请检查；不需要时应保持原始样本导出关闭。
- 只有用户开启“登录时启动”后，应用才会使用 macOS Service Management 注册登录项。

## 兼容性与限制

- 仅支持 macOS 26 或更高版本；没有 Windows、Linux、iOS 或 Web 版本。
- `0.2.0` 是本地 QA 预览版，并非已公证的公开发行版本。
- 公开响应可能变化或临时不可用；刷新失败时，应用会保留并明确标记最近一次有效的按来源缓存数据。
- Release 构建会排除 fixture JSON 和 Debug QA 资源。Codex 集成只使用公开摘要与社区评分接口，不访问受保护的完整 API。
- 社区评分与配额估算只是来源上下文，不会参与 Benchmark 质量、派生指标或 Pareto 计算。

## 目录结构

```text
Assets/                 App 图标源文件与打包图标
Config/                 macOS Bundle 元数据
Scripts/                Debug 与 Release App 组装脚本
Sources/ClaudeRadar/    App、来源 Adapter、持久化、同步与 UI
Tests/ClaudeRadarTests/ Swift Testing 测试
docs/                   来源契约与发布证据
script/                 本地运行、调试、日志与验证入口
```

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

Swift package 不含第三方包依赖。架构与发布证据见 [`docs/implementation-status.md`](docs/implementation-status.md)、[`docs/source-contract.md`](docs/source-contract.md)、[`docs/release-checklist.md`](docs/release-checklist.md) 和当前的 [`概览设计 QA`](docs/design-qa.md)。

## 安全

Claude Radar 会在持久化前验证来源数据，将诊断样本限制在应用专属数据目录，并先在临时目录组装导出内容，再安装最终 ZIP。请将本地数据目录与导出包视为可能包含敏感信息的内容。执行破坏性数据清理 QA 时不要使用真实的 Application Support 目录，应在 Debug 构建中指定隔离的 `RADAR_DATA_ROOT`。

## 第三方数据

Claude Radar 与 Claude Code Radar、Codex Radar 均不存在隶属或背书关系。归属信息与当前数据复用边界见 [`docs/third-party-notices.md`](docs/third-party-notices.md)。

## 许可证状态

当前尚未指定任何许可证。除非仓库所有者明确授权，否则不得对本仓库代码进行任何复用或再分发。
