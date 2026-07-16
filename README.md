# Codex Monitor for macOS

原生 SwiftUI 菜单栏应用，通过 OpenAI 官方网页登录集中查看一个或多个 ChatGPT 账号的 Codex 订阅方案与模型额度。

## 当前能力

- 使用与 Quotio 相同的 CLIProxyAPIPlus OAuth 流程跳转 OpenAI 网站，不输入 API Key
- 登录时自动打开默认浏览器，支持重新打开浏览器、取消并重新登录
- 登录窗口打开时预启动认证服务；使用本地成功回调，不唤起官方 Codex 应用
- 登录专用进程关闭插件与 Apps 预热，减少浏览器打开前的等待
- 使用 macOS Launch Services 命令启动默认浏览器，并在失败时显示明确错误
- 参考 Quotio：通过 NSWorkspace 解析默认浏览器，再按 Bundle ID 显式投递 OAuth URL
- 自动读取 ChatGPT 方案类型、Codex 额度百分比和恢复时间
- 每个账号使用独立的 CLIProxyAPI 认证空间，支持多账号
- 多账号汇总或单账号查看
- 7/30 天 Token 趋势图，支持指针交互查看每日数据
- 菜单栏快速查看 Token 与各账号剩余额度
- 仪表盘每 15 分钟自动刷新，打开菜单栏时也会检查数据新鲜度

> ChatGPT 网页登录不会返回 OpenAI Platform 组织的 API 调用次数或美元费用。这两项仅能通过组织 Admin Key 的 Usage/Costs API 获取，因此“只允许网页登录”模式下应用不会伪造或估算它们。续费日期也不在当前官方账号协议返回范围内。

## 构建与运行

要求 Apple Silicon Mac 与 macOS 14 或更高版本。CLIProxyAPIPlus 已随应用打包。

```sh
swift run CodexMeter
```

生成可双击运行的 `.app`：

```sh
./scripts/build-app.sh
open "dist/Codex Monitor.app"
```

如果需要在其他 Mac 上分发，请使用自己的 Apple Developer 证书替换脚本中的临时签名，并完成公证。
