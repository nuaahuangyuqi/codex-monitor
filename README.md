# Codex Monitor for macOS

原生 SwiftUI 菜单栏应用，通过 Codex 官方 app-server 集中查看多个 ChatGPT 账号的 Token 活动、订阅方案和模型额度，并可用指定账号打开 Codex。

## 当前能力

- 使用 Codex 官方 app-server OAuth 流程，不输入 API Key
- 登录时自动打开默认浏览器，支持重新打开浏览器、取消并重新登录
- Codex 桌面端永远使用原生 `~/.codex`，不再创建、合并或链接独立对话目录
- 仅为每个账号保存权限为 `0600` 的登录凭据，用量查询的临时运行目录用后即删
- 旧版本 CLIProxyAPIPlus 账号会在首次刷新时迁移到标准 Codex 认证格式
- 自动读取 ChatGPT 方案类型、Codex 额度百分比和恢复时间
- 多账号汇总或单账号查看
- 7/30 天 Token 趋势图，支持指针交互查看每日数据
- 按日期列出每个账号的每日 Token 使用量
- 在账号卡片中一键切换原生凭据并打开 Codex，失败时自动回滚
- 支持对已有账号重新进行官方授权
- 菜单栏快速查看 Token 与各账号剩余额度
- 仪表盘每 15 分钟自动刷新，打开菜单栏时也会检查数据新鲜度

> ChatGPT 网页登录不会返回 OpenAI Platform 组织的 API 调用次数或美元费用。这两项仅能通过组织 Admin Key 的 Usage/Costs API 获取，因此“只允许网页登录”模式下应用不会伪造或估算它们。续费日期也不在当前官方账号协议返回范围内。

## 构建与运行

要求 Apple Silicon Mac、macOS 14 或更高版本，以及已安装的 Codex macOS 应用。看板使用 Codex 应用内附带且与当前版本匹配的 app-server。

```sh
swift run CodexMeter
```

生成可双击运行的 `.app`：

```sh
./scripts/build-app.sh
open "dist/Codex Monitor.app"
```

如果需要在其他 Mac 上分发，请使用自己的 Apple Developer 证书替换脚本中的临时签名，并完成公证。

## 多账号工作方式

账号凭据保存在 `~/Library/Application Support/CodexMonitor/Credentials`，该目录不包含任何对话、SQLite 数据库、缓存或 Codex 配置。刷新非当前账号时，应用会创建一个短生命周临时目录，为该账号启动 app-server，并分别调用：

- `account/read`
- `account/rateLimits/read`
- `account/usage/read`

"用此账号打开 Codex"会先请求正在运行的 Codex 正常退出，保存其最新凭据，验证目标账号后原子替换 `~/.codex/auth.json`，再通过 Launch Services 正常打开 Codex。启动时不传入 `CODEX_HOME` 或 `CODEX_SQLITE_HOME`，因此所有账号始终看到同一份原生对话。如果 Codex 无法完全退出、目标凭据无效、配置重定向了 SQLite，或启动后校验失败，应用会拒绝切换并恢复原账号。

首次启动 1.3.0 时，旧版 `Accounts/<账号ID>/CodexHome` 中的凭据会被提取，随后整个隔离数据目录被删除。其中独有对话不会合并到 `~/.codex`。
