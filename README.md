# Codex Usage Display

[简体中文](README.zh-CN.md)

An unofficial macOS menu bar app that displays your remaining Codex 5-hour and weekly usage limits.

## Requirements

- Apple silicon Mac running macOS 13 or later.
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) installed and signed in with your ChatGPT account.

## Install

1. Download `CodexUsageBar-v0.1.0-arm64.zip` from the [v0.1.0 preview release](https://github.com/FlashDose/codex-usage-display/releases/tag/v0.1.0).
2. Unzip it and move `Codex Usage Bar.app` to your Applications folder.
3. Open the app.

This preview is ad hoc signed and not notarized. If macOS blocks it, verify the download source, then follow [Apple's instructions](https://support.apple.com/en-us/102445) to select **Open Anyway** in **System Settings → Privacy & Security**. Download the ZIP asset; GitHub's “Source code” archives do not contain the app.

## Use

The white percentage on the left shows the 5-hour limit; the teal percentage on the right shows the weekly limit. The `↻` line above them counts down to the next 5-hour reset. Click the menu bar item for exact reset times and manual refresh. Usage refreshes every three minutes; the countdown updates every minute.

If the CLI does not provide a weekly limit, the app shows `—`. Menu labels and error messages are currently in Chinese.

## Build from source

Install the Xcode Command Line Tools, then run:

```bash
./build_app.sh
```

The app is created at `dist/Codex Usage Bar.app`. On an Apple silicon Mac, `./scripts/package_release.sh` creates an ad-hoc signed ZIP and a SHA-256 file in `dist/releases/`.

## Data and privacy

The app starts the installed Codex CLI locally and requests `account/rateLimits/read`. It does not require an OpenAI API key, read CLI credentials directly, store usage history, or send telemetry. The CLI handles authentication and network communication.

This project is not affiliated with OpenAI. Licensed under the [MIT License](LICENSE).
