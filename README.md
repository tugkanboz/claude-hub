<p align="center">
  <img src="assets/AppIcon.png" width="128" alt="ClaudeHub app icon">
</p>

<h1 align="center">ClaudeHub</h1>

<p align="center">
  <strong>Track all of your Claude Code accounts from the macOS menu bar.</strong>
</p>

<p align="center">
  <a href="https://github.com/tugkanboz/claude-hub/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/tugkanboz/claude-hub?style=flat-square&color=7c3aed"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-000000?style=flat-square&logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-native-000000?style=flat-square&logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10%2B-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="Apple notarized" src="https://img.shields.io/badge/Apple-notarized-22c55e?style=flat-square&logo=apple&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://github.com/tugkanboz/claude-hub/releases/latest"><strong>Download for macOS</strong></a>
  &nbsp;|&nbsp;
  <a href="#installation">Installation</a>
  &nbsp;|&nbsp;
  <a href="#build-from-source">Build from source</a>
</p>

ClaudeHub is a small native macOS menu bar app for people who use more than
one Claude Code subscription. It keeps each Claude Code profile separate and
shows their usage in a single menu, so you do not need to switch accounts just
to check the remaining limits.

![ClaudeHub showing multiple Claude Code accounts](assets/claudehub.png?v=2)

## What it shows

- **Multiple accounts:** Add as many isolated Claude Code profiles as you need.
- **Current usage:** Check five-hour, seven-day and model-specific utilization.
- **Reset times:** See how long remains until each usage window resets.
- **Extra usage:** View extra usage details when they are enabled for an account.
- **Automatic refresh:** Usage is refreshed every five minutes.
- **Automatic token renewal:** Normal OAuth sessions are renewed through the installed Claude Code CLI.
- **Native macOS interface:** ClaudeHub is written in Swift and AppKit for Apple Silicon.
- **No tracking:** There is no telemetry, advertising or third-party analytics SDK.

The menu bar itself only shows the ClaudeHub icon. Open it to see the accounts
you have added and the latest usage information for each one.

## Download

[**Download the latest ClaudeHub release**](https://github.com/tugkanboz/claude-hub/releases/latest)

Open the release and download the `.dmg` file under **Assets**. Published builds
are signed with a Developer ID certificate, notarized by Apple and checked with
Gatekeeper before release.

ClaudeHub currently supports Apple Silicon Macs running macOS 13 or newer.

## Installation

1. Download the latest `.dmg` from the [Releases page](https://github.com/tugkanboz/claude-hub/releases/latest).
2. Open the disk image.
3. Drag **ClaudeHub** into the **Applications** folder.
4. Start ClaudeHub from **Applications**.
5. Open **Accounts > Add Existing Claude Profile...** and select each profile directory you prepared.

## Requirements

- An Apple Silicon Mac
- macOS 13 or newer
- Claude Code installed and available through the `claude` command
- A separate `CLAUDE_CONFIG_DIR` for every Claude account you want to monitor

## Prepare Claude Code profiles

ClaudeHub does not create Claude Code accounts or perform the first browser
login. Create each isolated profile from Terminal with Claude Code:

```bash
CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/account1" claude auth login
CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/account2" claude auth login
CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/account3" claude auth login
```

Each command creates its profile directory if it does not already exist and
opens the Claude login flow. These isolated profiles do not change your normal
`~/.claude` configuration.

After every account is signed in:

1. Open ClaudeHub.
2. Choose **Accounts > Add Existing Claude Profile...**.
3. Select a directory such as `~/.claude-accounts/account1`.
4. Enter the label that should appear in the menu.
5. Repeat for the remaining profiles.

ClaudeHub stores only the account label and profile directory path in:

```text
~/Library/Application Support/ClaudeHub/accounts.json
```

## Keychain access

Claude Code stores the credentials for every isolated profile in macOS
Keychain. ClaudeHub reads each credential when the app starts and keeps it only
in memory while the app is running.

macOS may ask for permission once for every profile. Enter your Mac password
and choose **Always Allow** so the published Developer ID-signed app can read
that profile again after a restart. Choosing **Allow** grants access only for
the current run and can cause the password prompt to return the next time you
open ClaudeHub.

The regular five-minute usage refresh uses the credential already held in
memory. It does not read Keychain again on every refresh.

## Automatic token renewal

Five minutes before a normal access token expires, ClaudeHub passes the
existing refresh token and scopes to the installed `claude` CLI. Claude Code
renews the session and writes its updated credential back to its own Keychain
item. ClaudeHub then reloads that profile.

This process does not open a browser, invoke a model or consume Claude plan
usage.

## Reconnect an expired or revoked profile

A manual login is only required when the refresh token has been revoked, the
account was logged out of Claude Code, or the account displays another
authentication error.

Run `claude auth login` again with the same profile directory that was
originally added to ClaudeHub. For example:

```bash
CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/account2" claude auth login
```

Complete the browser login, quit ClaudeHub and open it again so the in-memory
credential is replaced. Then choose **Refresh Now**. You do not need to remove
the profile from ClaudeHub or add it again.

## After restarting the Mac

Restarting or shutting down the Mac does not require another Claude browser
login. ClaudeHub keeps the configured profile names and paths in its
`accounts.json` file, and Claude Code keeps the authentication credentials in
macOS Keychain.

Open ClaudeHub again after signing in to macOS. If you want it to start
automatically, add ClaudeHub under **System Settings > General > Login Items**.
Profiles granted **Always Allow** Keychain access should load without another
permission prompt.

## Languages

ClaudeHub follows the macOS system language. It currently includes Turkish,
English, French and Spanish. Unsupported system languages fall back to English.
The product name remains **ClaudeHub** in every language.

## Build from source

```bash
swift test
bash scripts/build-app.sh
bash scripts/package-dmg.sh
```

The application bundle is written to `dist/ClaudeHub.app`. Local builds receive
an ad-hoc signature. GitHub release builds use the configured Developer ID
certificate, are notarized by Apple and are verified with Gatekeeper before
publishing.

## Privacy

- ClaudeHub never modifies your normal `~/.claude` configuration.
- Tokens are not written to ClaudeHub configuration files or logs.
- Credentials remain in macOS Keychain and in memory while ClaudeHub is open.
- Usage and profile requests go directly to Anthropic's OAuth endpoints.
- ClaudeHub has no telemetry, advertising or third-party analytics SDK.

## License

Copyright © 2026 Tuğkan Boz. Released under the [MIT License](LICENSE).

ClaudeHub is an independent project and is not affiliated with Anthropic.
Claude and Claude Code are trademarks of Anthropic.
