# Codex Usage Display

[English](README.md)

非官方 macOS 菜单栏应用，显示 Codex 的 5 小时和每周限额剩余百分比。

## 使用要求

- Apple 芯片 Mac，运行 macOS 13 或更新版本。
- 安装 [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)，并使用自己的 ChatGPT 账号登录。

## 安装

1. 从 [v0.1.0 预览版](https://github.com/FlashDose/codex-usage-display/releases/tag/v0.1.0) 下载 `CodexUsageBar-v0.1.0-arm64.zip`。
2. 解压，将 `Codex Usage Bar.app` 移至“应用程序”文件夹。
3. 打开应用。

此预览版采用临时签名，未经 Apple 公证。如果 macOS 阻止打开，请先核对下载来源，再按[苹果官方说明](https://support.apple.com/zh-cn/102445)在“系统设置 → 隐私与安全性”中选择“仍要打开”。请下载 ZIP 附件；GitHub 自动生成的“Source code”压缩包不包含应用。

## 使用

左侧白色百分比表示 5 小时剩余额度，右侧青绿色百分比表示每周剩余额度；上方的 `↻` 表示距离下次 5 小时重置的时间。点击菜单栏项目可查看准确重置时间并手动刷新。用量每三分钟更新一次，倒计时每分钟更新一次。

如果 Codex CLI 未提供每周限额，该位置显示 `—`。菜单文案和错误信息目前仅有中文。

## 从源码构建

安装 Xcode Command Line Tools 后运行：

```bash
./build_app.sh
```

应用生成于 `dist/Codex Usage Bar.app`。在 Apple 芯片 Mac 上运行 `./scripts/package_release.sh`，可在 `dist/releases/` 生成临时签名的 ZIP 和 SHA-256 文件。

## 数据与隐私

应用在本机启动已安装的 Codex CLI，并请求 `account/rateLimits/read`。它不需要 OpenAI API Key，不直接读取 CLI 凭据，不保存用量历史，也不发送遥测数据。身份验证和网络通信由 CLI 处理。

本项目与 OpenAI 无关联。源码采用 [MIT License](LICENSE)。
