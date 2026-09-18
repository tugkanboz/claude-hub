# ClaudeHub

ClaudeHub is a native macOS menu-bar app that displays usage for multiple
Claude Code subscription profiles in one place.

The menu-bar title stays **Claude Usage**. Each configured profile shows its
five-hour and weekly utilization, model-specific limits, reset countdowns and
extra usage.

## Requirements

- Apple Silicon Mac with macOS 13 or newer
- Claude Code installed
- One isolated `CLAUDE_CONFIG_DIR` per Claude account

## Prepare profiles

Log in once for every account. These commands do not change your normal
`~/.claude` profile:

```bash
CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/test-automation" claude auth login
CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/web-otomasyon" claude auth login
CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/ai-test" claude auth login
```

Open ClaudeHub, then choose **Accounts → Add Claude Profile…** and select each
directory. ClaudeHub stores only the label and directory path in
`~/Library/Application Support/ClaudeHub/accounts.json`.

## Token renewal

Claude Code stores credentials for isolated profiles in macOS Keychain.
ClaudeHub reads them only while requesting usage. Five minutes before an
access token expires, ClaudeHub gives the existing refresh token and scopes
back to the installed `claude` CLI. Claude Code performs the exchange and
saves its own credential. This does not invoke a model or consume plan usage.

If Anthropic revokes a refresh token, run `claude auth login` once for that
profile and click **Refresh Now**.

## Build

```bash
swift test
bash scripts/build-app.sh
bash scripts/package-dmg.sh
```

The application is produced at `dist/ClaudeHub.app`. The bundle receives an
ad-hoc signature and is verified before packaging. Public distribution without
Gatekeeper warnings additionally requires an Apple Developer ID certificate
and notarization.

## Privacy

- ClaudeHub never modifies `~/.claude`.
- Tokens are not copied into ClaudeHub configuration or logs.
- Requests go directly to Anthropic's OAuth usage and profile endpoints.
- There is no telemetry, advertising or third-party analytics SDK.

## License

Copyright © 2026 Tuğkan Boz. Released under the [MIT License](LICENSE).

ClaudeHub is an independent project and is not affiliated with Anthropic.
Claude and Claude Code are trademarks of Anthropic.
