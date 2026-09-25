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
- **Expiry warnings:** Profiles show a warning when a known refresh-token expiry is less than five days away.
- **Hourly usage journal:** Read changes, reset times and observation gaps in a local journal for each account.
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

ClaudeHub stores the account UUID, label and profile directory path, but no tokens, in:

```text
~/Library/Application Support/ClaudeHub/accounts.json
```

## Keychain access

Claude Code stores the credentials for every isolated profile in macOS
Keychain. ClaudeHub imports a profile's credential and keeps its own copy under
the Keychain service `com.tugkanboz.claudehub.credentials`, identified by the
account's stable UUID. It uses this copy after a restart and an in-memory cache
while running. Existing profiles are imported on first use after upgrading if
macOS permits access without interaction.

ClaudeHub performs background Keychain reads, writes and cleanup without
requesting a password dialog. If macOS requires authorization, the account
shows **Access permission required** and **Allow access…** in its submenu.
Automatic credential access and renewal for that account pause until you
choose this action. Other accounts continue working. **Refresh Now** does not
request authorization or repeatedly retry a denied Keychain read.

A valid token already in memory can still fetch usage while permission is
pending. During refresh, rate limits, permission errors or other failures,
the last successful measurement remains visible with its original date and
time and is explicitly marked as not current. Reconnecting a profile does not
erase this measurement. ClaudeHub restores the last measurement after restarting
from a local file under Application Support if it is less than seven days old.
This file contains the usage percentages and measurement time,
without an email address, organization or credential. The old measurement is not
written to the usage journal as a fresh one. Cancelling authorization keeps the
account paused. Allowing access reads the latest credential and, if its access
token expires within ten minutes or has already expired, completes a CLI renewal
and imports the resulting credential before saving ClaudeHub's copy and resuming
the schedule. Failed renewal or denied final access does not count as successful
recovery. A revoked login still requires signing in again. This action preserves
any usage request cooldown imposed by Anthropic.

Adding or reconnecting a profile is an explicit action and may display macOS
permission dialogs, including a separate request to update ClaudeHub's own
copy. Choose **Always Allow** only if you trust the installed build. This does
not grant permanent access to replacement Claude Code items. Local ad-hoc
builds and Developer ID-signed releases can have different access rights.

The suppression applies to Security calls made by ClaudeHub. The separately
installed Claude Code CLI and macOS itself control their own dialogs; this
change does not promise that those processes will never ask for permission.

The regular five-minute usage refresh uses the credential already held in
memory. It does not read Keychain again on every refresh.

Removing an account requires confirmation and deletes only ClaudeHub's account
entry and its own credential copy. It does not delete the profile directory or
the Claude Code Keychain item. A failed credential cleanup is reported.

## Automatic token renewal

Each profile has its own renewal schedule, approximately ten minutes before
access-token expiry. This schedule is independent of usage polling and keeps
running for idle profiles while ClaudeHub is open. After sleep, overdue work
is picked up when the app resumes. Nothing can renew while the Mac is shut down
or ClaudeHub is closed.

Before a scheduled renewal, ClaudeHub checks whether Claude Code has already
updated the credential. If renewal is still needed, it passes the refresh token
and scopes to the installed `claude` CLI. Claude Code writes the renewed session
to its own Keychain item. ClaudeHub then imports the result into its private
copy. ClaudeHub does not directly modify Claude Code's Keychain item.

Automatic renewal is restricted to isolated profiles. The normal `~/.claude`
directory is protected, including paths that resolve to it through a symlink.

Only one renewal per account runs at a time. Failed renewals use a bounded
retry delay, and the CLI process has a timeout. A renewal failure does not by
itself hide otherwise accessible usage. An HTTP 401 triggers a credential
reload, then one renewal attempt if necessary; it does not loop indefinitely.

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

Complete the browser login, then choose **Accounts > Reconnect Profile >
your profile** in ClaudeHub. This imports the new credential without restarting
or removing the account. Reopening the app alone may reuse its private cached
credential, so use **Reconnect Profile** after a manual login.

## After restarting the Mac

Restarting or shutting down the Mac does not require another Claude browser
login. ClaudeHub keeps the configured profile names and paths in its
`accounts.json` file, and Claude Code keeps the authentication credentials in
macOS Keychain.

Open ClaudeHub again after signing in to macOS. If you want it to start
automatically, add ClaudeHub under **System Settings > General > Login Items**.
Profiles normally load from ClaudeHub's own Keychain copy. Locked Keychains,
changes to the app's signature and importing a replaced Claude Code item can
still require permission through **Allow access…**. A restart does not extend an expired or revoked
refresh token; use the reconnect instructions if necessary.

## Languages

ClaudeHub follows the macOS system language. It currently includes Turkish,
English, French and Spanish. Unsupported system languages fall back to English.
The product name remains **ClaudeHub** in every language.

## Build from source

Use Swift 5.10 or newer on macOS with the Xcode command-line tools installed.

```bash
swift test
bash scripts/build-app.sh
bash scripts/package-dmg.sh
```

The application bundle is written to `dist/ClaudeHub.app`. Local builds receive
an ad-hoc signature. GitHub release builds use the configured Developer ID
certificate, are notarized by Apple and are verified with Gatekeeper before
publishing.

The build generates `AppIcon.icns` and its iconset from the checked-in 1024px
PNG using macOS `sips` and `iconutil`. To redraw the PNG from the SVG first,
install `rsvg-convert` and run `bash scripts/build-icons.sh --render-svg`.

CI runs the tests twice, builds the app, checks the bundled icon and verifies
the DMG. CI artifacts are ad-hoc-signed test builds, not notarized releases.

### Session-change smoke test

Before releasing changes to credential handling, test the signed app on a Mac:

1. Add two isolated profiles and verify their usage independently.
2. Quit and reopen the app. Confirm it can reuse its private Keychain copies.
3. Sign in again to one profile from Terminal, then reconnect that profile in
   the menu. Confirm the other profile is unaffected.
4. Let a profile reach renewal time while it is not being used in Terminal.
   Verify renewal still happens without a manual usage refresh.
5. Sleep and wake the Mac across a renewal deadline, then check the profile.
6. Deny access, repeatedly refresh, then allow it from the account submenu.
   Confirm background reads stay paused, other profiles continue and stale
   measurements are labelled. Also disconnect the network. Confirm errors are bounded
   and the app remains responsive. Restore access and reconnect.
7. Repeatedly press Refresh Now while removing a profile. Confirm cancelled
   work does not restore a removed account or overwrite newer results.

Automated tests use fake credentials and do not access personal tokens. They
cannot verify macOS permission dialogs or Anthropic's live renewal behavior.

## Request limits and refresh behavior

ClaudeHub normally fetches usage every five minutes. Profile information is
cached in memory for six hours instead of being fetched with every usage poll.
Reconnecting a profile or receiving HTTP 401 invalidates that profile cache.

If either endpoint returns HTTP 429, requests for that account pause until the
server's `Retry-After` time, when provided as seconds or an HTTP date. If the
header is missing or invalid, the delay starts at about one minute and doubles
with a small random offset, up to 30 minutes. A successful query resets this
backoff. Other accounts and the independent token-renewal schedule continue.
The next regular poll at or after the deadline retries; the displayed time is
the earliest allowed attempt, not a promise of an exact retry time.

**Refresh Now** respects the same deadline. Concurrent refreshes share one
request per account, and a successful measurement can be reused for 30 seconds
without changing its original timestamp. Reconnecting does not bypass an
existing rate-limit wait. The profile cache and 30-second reuse are held in memory.
The 429 retry deadline is also stored locally per account and still applies
after restarting the app. A successful request or removing the account clears
it; no credential or personal profile data is stored in this deadline file.

The menu shows a localized rate-limit message and the earliest retry time.
When available, the last successful measurement remains visible, explicitly
marked as not current with its date and time. A failed poll clears the journal's
current sample, so old measurements are not recorded as fresh hourly data.
Diagnostic logs include the account UUID, endpoint and retry time; they do not
include tokens, request headers or raw response bodies.

## Hourly usage journal

While the Mac is awake and ClaudeHub is running, a journal entry is saved at
each local hour boundary, such as 09:00 or 10:00. Starting the app at 10:25
means the first entry is at 11:00. Sleeping, shutting down or quitting the app
leaves a gap. ClaudeHub does not wake the Mac or fill in missed hours when it
resumes. A timer delayed by a minute or more is skipped too.

The journal reuses the most recent successful five-minute usage query. It does
not make extra API requests or read Keychain. Each entry includes both the hour
being recorded and the actual measurement time. A sample older than six minutes
is marked unavailable; an old percentage is never presented as a new measurement.
Usage polling and token renewal keep their existing independent schedules.

Open an account's submenu and choose **Open Usage Journal** to see its files:

```text
~/.claude-usage/ClaudeHub/<account-UUID>/2026-09-22.log
~/.claude-usage/ClaudeHub/<account-UUID>/2026-09-22.json
```

The `.log` file is a plain-text table without commentary. Percentages and costs
are right-aligned; every column has one width throughout the daily file, so
`1.0%`, `25.0%` and `100.0%` do not shift the separators. Open it in a monospaced
font with line wrapping disabled. Missing values appear as `-`, not zero.
Each usage window has its own row; extra usage adds cost columns when available.
Headers and status labels follow the app's Turkish, English, French or Spanish
language. Existing entries in the current daily log are rendered as a table on
the next journal write; older files are left unchanged.

The `.json` file retains measurements and explanations for later analysis.
Files are grouped by UTC date; table timestamps include the local UTC offset.

Example percentage alignment (the full log also includes measurement and reset timestamps):

```text
|-------|---------|--------|
| Time  | Period  | Usage  |
|-------|---------|--------|
| 09:00 | 5 hours |   1.0% |
| 10:00 | 5 hours |  25.0% |
| 11:00 | 5 hours | 100.0% |
|-------|---------|--------|
```

JSON explanations distinguish first observations, unchanged usage, increases, reported
decreases, approaching limits, changed reset times and recovery after missing
data. Deltas are only calculated between consecutive available hourly records
with matching known reset times. A gap or a changed period does not produce a
made-up consumption total. These percentages describe limit utilization, not
token counts, costs or which project consumed the allowance.

Journal files contain account UUIDs, timestamps, usage windows, extra-usage data
when provided, and explanations. Account names, email addresses, organization
IDs, profile paths and credentials are not included. Files are written in the
background. Only the current day's entries are kept in the writer's cache;
history is loaded once per account after launch for comparisons.

The latest 30 UTC calendar days are retained. Cleanup runs at most once per day
when a record is written and only removes dated journal files inside ClaudeHub's
UUID account folders. Removing an account does not immediately erase its history;
you can delete its journal folder yourself. If no more records are written,
automatic cleanup waits until recording resumes. Existing corrupt JSON is not
overwritten; move the damaged file out of the folder before restarting the app
to resume recording. A write failure is shown in the account submenu.

## Account-file recovery and logs

Older `config_dir` account entries are normalized on successful load, preserving
their generated IDs for later launches. If `accounts.json` is invalid, the app
keeps the original, attempts an `accounts.json.bak` backup and disables account
changes. Existing backups are preserved with uniquely named additional backups.
Inspect or restore the file before reopening the app; an empty account list is
never saved over a failed load.

Logs are stored at `~/Library/Logs/ClaudeHub/menubar.log`. At about 1 MB the log
rotates to `menubar.log.1`; only the latest rotated log is retained.

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
