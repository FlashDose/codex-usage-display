# Codex Usage Display

**English** | [简体中文](README.zh-CN.md)

An unofficial macOS menu bar app that shows your remaining Codex 5-hour and weekly usage limits.

## Requirements

- Apple silicon Mac running macOS 13 or later. No Intel release is provided.
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) installed and signed in with your ChatGPT account.

## Install

1. Download `CodexUsageBar-v0.1.0-arm64.zip` from the [v0.1.0 preview release](https://github.com/FlashDose/codex-usage-display/releases/tag/v0.1.0).
2. Unzip it and move `Codex Usage Bar.app` to your Applications folder.
3. Open the app. It is ad-hoc signed and has not been notarized by Apple. If macOS blocks the first launch, verify the download source and follow [Apple's instructions](https://support.apple.com/en-us/102445) to choose **Open Anyway** in **System Settings → Privacy & Security**.

GitHub's automatically generated “Source code” archives do not contain the app.

## Use

The menu bar shows the remaining 5-hour and weekly percentages, with a countdown to the next 5-hour reset above them. Click the item for exact reset times and a manual refresh command. Usage refreshes every three minutes; the countdown updates every minute.

If the CLI does not provide a weekly limit, the app shows `—`. Some menu labels and error messages are currently in Chinese. Installation on another Mac has not yet been independently verified.

## Build from source

Install a Swift compiler, then run:

```bash
./build_app.sh
```

The app is created at `dist/Codex Usage Bar.app`. On an Apple silicon Mac, `./scripts/package_release.sh` creates an ad-hoc signed ZIP and a SHA-256 file in `dist/releases/`.

## Data and privacy

The app uses the installed Codex CLI's local app-server to request `account/rateLimits/read`. It does not require an OpenAI API key, directly read CLI authentication files, or store credentials or usage history. No separate telemetry service is included in this project. The CLI protocol may change in future versions.

This project is not affiliated with OpenAI. Licensed under the [MIT License](LICENSE).
