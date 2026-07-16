# Codex Monitor for macOS

原生 SwiftUI 菜单栏应用，通过 Codex 官方 app-server 集中查看多个 ChatGPT 账号的 Token 活动、订阅方案和模型额度，并可用指定账号打开 Codex。

## 当前能力

- 使用 Codex 官方 app-server OAuth 流程，不输入 API Key
- 登录时自动打开默认浏览器，支持重新打开浏览器、取消并重新登录
- 每个账号使用独立的 `CODEX_HOME`，认证、刷新和本地状态互不干扰
- 所有账号共享默认 Codex 对话数据库，切换账号不会隐藏原有对话
- 旧版本 CLIProxyAPIPlus 账号会在首次刷新时迁移到标准 Codex 认证格式
- 自动读取 ChatGPT 方案类型、Codex 额度百分比和恢复时间
- 多账号汇总或单账号查看
- 7/30 天 Token 趋势图，支持指针交互查看每日数据
- 按日期列出每个账号的每日 Token 使用量
- 在账号卡片中一键用该账号打开独立 Codex 实例
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

每个账号都保存在 `~/Library/Application Support/CodexMonitor/Accounts/<账号ID>/CodexHome`。刷新时应用为每个账号启动短生命周期 app-server，并分别调用：

- `account/read`
- `account/rateLimits/read`
- `account/usage/read`

“用此账号打开 Codex”会创建新的 Codex 应用实例，并只为该实例设置对应的 `CODEX_HOME`。账号目录仅隔离认证和账号配置；`state_5.sqlite`、`sessions`、`archived_sessions`、会话索引、附件和生成图片都会迁移后链接到默认 `~/.codex` 目录。`CODEX_SQLITE_HOME` 也明确指向 `~/.codex`，所以无论 Codex 桌面端是否传递该环境变量，所有账号都会使用默认历史记录目录。迁移前会保留本地备份，用户默认登录不会被覆盖。
