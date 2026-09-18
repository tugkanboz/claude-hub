# ClaudeHub

ClaudeHub is a native macOS menu-bar app that displays usage for multiple
Claude Code subscription profiles in one place.

The menu bar displays only the ClaudeHub icon. Each configured profile shows
its five-hour and weekly utilization, model-specific limits, reset countdowns
and extra usage.

ClaudeHub follows the macOS system language in Turkish, English, French and
Spanish. Other system languages fall back to English. The product name remains
**ClaudeHub** in every language.

![ClaudeHub multi-account menu bar preview](assets/claudehub.png?v=2)

## Download

[**Download the latest ClaudeHub release for macOS**](https://github.com/tugkanboz/claude-hub/releases/latest)

Open the latest release and download the `.dmg` file listed under **Assets**.
Release builds are signed with a Developer ID certificate and notarized by Apple.
ClaudeHub currently supports Apple Silicon Macs running macOS 13 or newer.

## Installation

1. Download the latest `.dmg` from the [Releases page](https://github.com/tugkanboz/claude-hub/releases/latest).
2. Open the disk image and drag **ClaudeHub** into the **Applications** folder.
3. Launch ClaudeHub from **Applications**.
4. Choose **Accounts → Add Claude Profile…** and select each isolated Claude Code profile directory.

## Requirements

- Apple Silicon Mac with macOS 13 or newer
- Claude Code installed
- One isolated `CLAUDE_CONFIG_DIR` per Claude account

## Prepare profiles

Log in once for every account. These commands do not change your normal
`~/.claude` profile:

```bash
CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/account1" claude auth login
CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/account2" claude auth login
CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/account3" claude auth login
```

Open ClaudeHub, then choose **Accounts → Add Claude Profile…** and select each
directory. ClaudeHub stores only the label and directory path in
`~/Library/Application Support/ClaudeHub/accounts.json`.

## Keychain access and token renewal

Claude Code stores credentials for isolated profiles in macOS Keychain.
ClaudeHub reads each profile once when the app starts and keeps the credential
only in memory. The five-minute usage refresh uses that in-memory value, so it
does not trigger another Keychain password prompt.

On the first launch, macOS can ask once for every Claude profile. Choose
**Always Allow** to remember the permission for published Developer ID-signed
builds.

Five minutes before an access token expires, ClaudeHub gives the existing
refresh token and scopes back to the installed `claude` CLI. Claude Code
performs the exchange and saves its own credential. ClaudeHub then reloads that
profile once. This does not invoke a model or consume plan usage.

If Anthropic revokes a refresh token, run `claude auth login` once for that
profile and click **Refresh Now**.

## Build

```bash
swift test
bash scripts/build-app.sh
bash scripts/package-dmg.sh
```

The application is produced at `dist/ClaudeHub.app`. Local builds receive an
ad-hoc signature. GitHub release builds are signed with a Developer ID
certificate, notarized by Apple and verified with Gatekeeper before publishing.

## Privacy

- ClaudeHub never modifies `~/.claude`.
- Tokens are never written to ClaudeHub configuration or logs; they live only in memory while the app is open.
- Requests go directly to Anthropic's OAuth usage and profile endpoints.
- There is no telemetry, advertising or third-party analytics SDK.

## License

Copyright © 2026 Tuğkan Boz. Released under the [MIT License](LICENSE).

ClaudeHub is an independent project and is not affiliated with Anthropic.
Claude and Claude Code are trademarks of Anthropic.
