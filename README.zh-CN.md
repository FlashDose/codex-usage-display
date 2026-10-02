# Codex Usage Display

[English](README.md) | **简体中文**

非官方 macOS 菜单栏应用，显示 Codex 的 5 小时和每周限额剩余百分比。

## 使用要求

- Apple 芯片 Mac，运行 macOS 13 或更新版本；暂无 Intel 发行包。
- 安装 [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)，并使用自己的 ChatGPT 账号登录。

## 安装

1. 从 [v0.1.0 预览版](https://github.com/FlashDose/codex-usage-display/releases/tag/v0.1.0)下载 `CodexUsageBar-v0.1.0-arm64.zip`。
2. 解压，将 `Codex Usage Bar.app` 移至“应用程序”文件夹。
3. 打开应用。该版本仅采用临时签名，尚未经过 Apple 公证。如果 macOS 阻止首次打开，请先核对下载来源，再按[苹果官方说明](https://support.apple.com/zh-cn/102445)在“系统设置 → 隐私与安全性”中选择“仍要打开”。

GitHub 自动生成的“Source code”压缩包只有源码，不包含应用。

## 使用

菜单栏显示 5 小时和每周剩余百分比，上方显示下一次 5 小时重置倒计时。点击菜单栏项目可查看准确重置时间并手动刷新。用量每三分钟更新一次，倒计时每分钟更新一次。

如果 Codex CLI 未提供每周限额，该位置显示 `—`。部分菜单文案目前仅有中文。尚未在另一台 Mac 上独立验证安装过程。

## 从源码构建

安装 Swift 编译器后运行：

```bash
./build_app.sh
```

应用生成于 `dist/Codex Usage Bar.app`。在 Apple 芯片 Mac 上运行 `./scripts/package_release.sh`，可在 `dist/releases/` 生成临时签名的 ZIP 和 SHA-256 文件。

## 数据与隐私

应用通过已安装的 Codex CLI 本地 app-server 请求 `account/rateLimits/read`。本项目不需要 OpenAI API Key；应用不会直接读取 CLI 身份验证文件，也不会保存凭据或用量历史。本项目不包含独立的遥测服务。Codex CLI 协议以后可能发生变化。

本项目与 OpenAI 无关联。源码采用 [MIT License](LICENSE)。
