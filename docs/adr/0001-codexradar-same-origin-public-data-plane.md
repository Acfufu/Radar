# codexradar.com 同域公开数据面机制性放行

上游在一周内把主要数据面从 `/data/*` 静态文件迁到同域 `/api/*` 公开 GET(radar-insights、intelligence-efficiency-metrics、visual-spatial-reasoning 等,2026-09-08 实测均无需凭据),而既有配置本就有一条 `/api/*` 先例(`communityURL = /api/model-ratings?history=14`)。2026-09-08 拍板:§5.0 白名单改为按「同域 + 公开 GET + 无凭据」三条件机制性放行 codexradar.com 同域 `/api/*`,不再逐端点列举——避免上游每次新增端点都要先改 spec。`api.codexradar.com` 主机禁令与 deng `/api/*` 提交流程(credential-protected)禁令维持不变,transport 层 host+path 断言同步更新。

## Considered Options

- 显式列举端点扩面(更窄,但每个新端点都要再拍板一次)
- 维持 `/data/*` 字面 + 逐端点例外(与已拍板的数据面接入节奏冲突)
