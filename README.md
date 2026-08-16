# Mailify

A native macOS menu-bar app that syncs your Gmail inbox, uses Claude to
categorize mail and draft reply suggestions, and lets you review each
suggestion before anything is sent. **Mailify never sends email on its own** —
the only thing it ever writes to Gmail is a draft, and only after you
explicitly accept a suggestion.

Built as a plain Swift Package (no Xcode project needed) — SwiftUI throughout,
talking directly to the Gmail REST API and the Anthropic Messages API over
`URLSession`. No backend server, no third-party SDKs.

## Goal

Mailify's job is to **organize your mailbox**, not just show it to you. In
priority order:

1. **Surface what needs action, up front.** Important mail that's actually
   addressed to you and expects a reply should lead the inbox, ahead of
   newsletters, receipts, and automated notifications.
2. **Archive** handled/low-value mail out of the way — reversibly, nothing
   lost.
3. **Purge** mail you don't want kept at all — deliberately, not by default.

**Status today:** AI categorization and the action-first "needs reply" signal
are built (see Features below). Archive and purge are **not implemented
yet** — the app currently requests only `gmail.readonly` + `gmail.compose`
Gmail scopes, which can't archive, label, or delete anything server-side.
Getting there requires a deliberate, explicitly-approved scope expansion
(`gmail.modify` and/or trash/delete permissions) — see `CLAUDE.md` for the
implementation plan and the trust-boundary considerations around it.

## Features

- **Gmail sync** — incremental fetch of new/changed mail via the Gmail API,
  manual ("Sync Now") or on a 15-minute timer.
- **AI categorization** — each message is classified into one of your
  categories (School, Investment, Personal, Job, Shop, Purchase, Other by
  default, editable in Settings) and flagged as needing a reply or not.
- **AI draft suggestions** — for mail that needs a reply, Claude proposes a
  subject + body. Suggestions sit in a queue where you **Accept** (creates a
  real Gmail draft for you to review/send) or **Dismiss**.
- **Spotlight integration** — synced mail is indexed so macOS Spotlight can
  find and jump straight to a message in the app.
- **Menu bar extra** — shows pending-suggestion count, quick Sync Now / Open /
  Quit actions.
- **Local-first storage** — all mail metadata/state lives in a JSON file under
  `~/Library/Application Support/Mailify/store.json`; secrets (OAuth tokens,
  Anthropic API key) live in the macOS Keychain, never in that file.

## Requirements

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`) — you do **not** need
  Xcode itself, just the Swift toolchain it provides.
- Your own Google Cloud OAuth client (for Gmail) and your own Anthropic API
  key (for categorization/drafting). Both are free to create; see setup below.

## Setup

1. **Gmail OAuth** — follow [SETUP-GMAIL.md](SETUP-GMAIL.md) to create a
   Google Cloud OAuth client and paste the client ID/secret into
   `Sources/Mailify/Gmail/GmailOAuthManager.swift`. Without this, the app
   builds and runs but Gmail sync won't work.
2. **Anthropic API key** — once the app is running, add your key in
   **Settings → AI**. Without a key, mail still syncs but stays uncategorized
   and no drafts are suggested.

## Build & run

### Option A — run locally, straight from source (fastest for iterating)

```sh
swift build          # debug build — compiles and reports errors
swift run              # build + launch
```

This runs the app unbundled: a generic Dock icon, and Spotlight tap-to-open
won't resolve (there's no registered `.app` yet). Everything else — window,
menu bar extra, Gmail sync, AI categorization/drafts — works normally. This
is the fastest loop while making changes.

### Option B — package a real `.app` (proper icon, Spotlight, installable)

```sh
chmod +x build-app.sh   # first time only
./build-app.sh
open Mailify.app
```

`build-app.sh` does a release build, hand-assembles the bundle structure
(`Contents/MacOS`, `Contents/Resources`, `Info.plist`), sets the app icon from
`Resources/AppIcon.icns`, and ad-hoc code-signs the bundle so Gatekeeper,
notifications, and Spotlight indexing all behave like a normal installed app.

Drag `Mailify.app` into `/Applications` to keep it around and launch it like
any other Mac app.

### VS Code

See [SETUP-VSCODE.md](SETUP-VSCODE.md) for editor setup (Swift + CodeLLDB
extensions), `Cmd+Shift+B` to build, `F5` to debug.

## Project layout

```
Sources/Mailify/
  App/            AppState — root ObservableObject, single source of truth
  Claude/         Anthropic API client + the categorize/draft-suggest "agents"
  Gmail/          Gmail REST client, OAuth (PKCE), and MailProvider conformance
  Models/         Codable value types: Account, Category, EmailMessage, ...
  Notifications/  Local notification for new suggestions
  Persistence/     JSON store load/save, Keychain wrapper
  Spotlight/       CoreSpotlight indexing
  Sync/            SyncCoordinator — the fetch → categorize → draft → persist pipeline
  UI/              SwiftUI views (sidebar, message list/detail, settings, suggestions)
Resources/
  AppIcon.icns    App icon used by build-app.sh when packaging Mailify.app
```

`MailProvider` is a protocol so a second provider (e.g. IMAP-based iCloud
Mail) could be added later without touching `SyncCoordinator`, the UI, or the
data model — Gmail is currently the only implementation.

## Icon

`Resources/AppIcon.icns` is a macOS-style squircle with a purple-to-teal
gradient (matching the app's category color palette) and a white envelope
glyph. Regenerate it with `iconutil` from a 1024×1024 master PNG if you ever
want to redesign it — no external asset pipeline required.

## Testing

```sh
./run-eval.sh
```

Runs the ordered eval suite in [`Eval/main.swift`](Eval/main.swift) — pure
logic checks (no UI, no network, no real Gmail/Google calls) grouped into 4
numbered sections that mirror the sync pipeline:

1. **Persistence** — `AppStore` Codable round-trip, and backward compatibility
   (a `store.json` written before a field existed must still load with that
   field defaulted, not get wiped as "corrupt").
2. **Sync query building** — `GmailProvider.buildQuery`: the History window
   (Settings → Sync) and the Ignore Social/Promotions toggles produce the
   right Gmail search query, including the "window always caps the query,
   even on incremental syncs" regression guard.
3. **OAuth authorize URL + PKCE** — `GmailOAuthManager.makeAuthorizeURL`: the
   redirect is a loopback address (`http://127.0.0.1:...`), never a custom
   URL scheme (Google rejects those for Desktop-app clients), plus every
   required PKCE param is present and correctly derived.
4. **OAuth loopback redirect parsing** — `OAuthLoopbackServer`: the local
   HTTP listener correctly pulls `code`/`error` out of Google's redirect
   request, including edge cases (denied consent, missing params, an
   unrelated request like a stray favicon fetch).

Output is one `PASS`/`FAIL` line per check plus a final count; exit code is
`0` only if every check passed. Run it after any change that touches
persistence, sync-query building, or the OAuth flow — before doing a manual
click-through in the app, not instead of one (it doesn't touch the network
or exercise the UI, so a real "Sync Now" / "Connect" pass is still worth
doing for anything that isn't pure logic).

**Why this isn't a `swift test` / XCTest / SwiftPM test target:** all three
were tried and failed on a Command-Line-Tools-only setup (no full Xcode.app)
for three different reasons — see the header comment in
[`Eval/main.swift`](Eval/main.swift) and [`run-eval.sh`](run-eval.sh) for the
full story. In short: `run-eval.sh` compiles `Eval/main.swift` directly
alongside `Sources/Mailify/*.swift` (skipping `MailifyApp.swift`, which owns
`@main`) with plain `swiftc`, sidestepping all of it. If you're on a machine
with full Xcode installed, a real `Tests/MailifyTests` target with
`swift-testing` may well work fine — this workaround exists because of this
project's specific dev setup, not because SwiftPM testing is broken in
general.

Beyond the eval suite, there's no automated UI/integration test target.
Anything touching Gmail sync, OAuth, or drafting still needs an actual
run-through in the app — see `CLAUDE.md`'s manual test checklist.

## Privacy / safety notes

- Gmail scopes requested are `gmail.readonly` and `gmail.compose` only —
  deliberately **not** `gmail.modify`, so the app has no ability to delete,
  archive, or label your mail server-side.
- There is no send code path anywhere in the app — Claude-drafted replies can
  only ever become a Gmail **draft**, which you review and send yourself from
  Gmail.
