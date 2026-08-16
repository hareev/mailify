# CLAUDE.md

Guidance for working on Mailify as its developer and tester. Read this before
making changes.

## What this is

A solo-user macOS SwiftUI app (Swift Package, no Xcode project) that syncs
Gmail, uses Claude to categorize mail and draft reply suggestions, and never
sends anything without the user explicitly accepting a suggestion first. No
backend server — the app talks directly to the Gmail REST API and the
Anthropic Messages API over `URLSession`.

Full architecture/feature description lives in `README.md` — read that first
for the big picture. This file is about *how to work on the code*.

## Goal

Mailify's core job is **organizing the user's mailbox**, not just reading it.
Three pillars, in priority order:

1. **Surface what actually needs action, up front.** The inbox should lead
   with important/needs-reply mail (categorization + `needsReply` + draft
   suggestions already do this), not bury it under newsletters and noise.
2. **Archive** — clear handled/low-value mail out of the way without losing
   it (reversible, not deletion).
3. **Purge** — actually delete mail the user doesn't want kept (irreversible,
   used deliberately — receipts long past relevance, spam that slipped
   through, etc.).

**Current gap:** archive and purge are *not implemented yet*. Today's Gmail
OAuth scope is deliberately limited to `gmail.readonly` + `gmail.compose`
(see `SETUP-GMAIL.md`), which cannot label, archive, or delete anything
server-side — by design, to keep the app's blast radius to "read + draft"
only. Getting to real archive/purge means:

- Requesting `gmail.modify` (archive/label) and, for purge, a scope that
  permits `messages.trash`/`messages.delete` — a real trust-boundary
  expansion, on par with the existing "no send" boundary. Surface this to the
  user explicitly before implementing, don't fold it into an unrelated change.
- New `MailProvider` methods (archive/purge are Gmail-specific actions today,
  but should be added to the protocol, not bolted onto `GmailProvider` alone,
  so the provider-agnostic seam holds).
- UI for triggering archive/purge (bulk and per-message) and for surfacing
  "needs action" mail ahead of everything else — today's `SidebarSelection`/
  `MessageListView` don't yet have an action-first/priority view distinct
  from "All Mail" and per-category lists.

Keep this section in mind when prioritizing what to build next or when the
user asks "what should Mailify do" — read/categorize/draft-suggest is the
foundation that's built; organize (archive/purge/action-first) is the
still-open part of the actual goal.

## Build, run, test

```sh
swift build              # debug build — do this after every change, it's fast
swift run                 # build + launch unbundled (fine for most iteration)
./build-app.sh             # release build + real .app bundle, ad-hoc signed
```

There is no SwiftPM `Tests/` target — run `./run-eval.sh` instead for pure
logic (persistence/backward-compat, sync query building, OAuth URL + PKCE,
OAuth redirect parsing; see README's Testing section for the full breakdown).
**Do not reach for `swift test` / XCTest / swift-testing on this machine** —
all three were tried and failed for three different reasons (Command Line
Tools only, no full Xcode.app installed): XCTest.framework doesn't exist
outside Xcode.app at all; swift-testing's framework loads but silently
discovers and runs zero tests while still exiting 0 (looks like a pass,
isn't); and a second SwiftPM executable target can't link against another
target's symbols even with `@testable import`. `run-eval.sh` compiles
`Eval/main.swift` straight alongside `Sources/Mailify/*.swift` with plain
`swiftc`, sidestepping all of it. Full story in `Eval/main.swift`'s header
comment. If a future environment has full Xcode, a real `Tests/MailifyTests`
target may well work fine — this isn't a SwiftPM limitation, just this
machine's toolchain.

Treat yourself as both developer and QA:

- Always run `swift build` before considering a change done — catch
  compile errors yourself, don't hand that back to the user.
- Run `./run-eval.sh` after touching persistence, sync-query building, or the
  OAuth flow, and add a check there for any new pure logic in those areas
  (or elsewhere, following the same pattern) rather than leaving it untested.
- For anything touching sync, categorization, drafting, OAuth, or
  persistence, actually run the app (`swift run` or the packaged `.app`) and
  exercise the change — the eval suite doesn't touch the network or the UI,
  so it's a complement to a real run-through, not a replacement for one.

### Manual test checklist (run through relevant parts after non-trivial changes)

- **Build**: `swift build` clean, no warnings introduced.
- **Launch**: app opens, menu bar extra appears, no crash on cold start with
  an empty/fresh `store.json`.
- **Gmail connect**: Settings → Accounts → Connect completes the OAuth sheet
  and shows the connected email (requires a real client ID/secret filled into
  `GmailOAuthManager.swift` — see README setup).
- **Sync Now**: pulls new mail, no duplicate messages on a second run,
  `lastSyncedAt` advances.
- **Categorization**: only runs when an Anthropic key is set in Settings →
  AI; uncategorized mail should show as such when no key is present, not
  error out.
- **Draft suggestions**: appear in the Suggestion queue for mail flagged
  `needsReply`; **Accept** creates a real Gmail draft (verify in Gmail itself)
  and moves the suggestion to `.accepted`; **Dismiss** just marks it
  dismissed, no Gmail side effect.
- **Spotlight**: synced messages are searchable from macOS Spotlight and
  tapping one opens/selects it in the app.
- **Persistence**: quit and relaunch — state (accounts, categories, messages,
  suggestions) survives.

## Architecture map

```
AppState (root ObservableObject)
 ├─ store: AppStore              — single source of truth (Codable), all mutations via appState.mutateStore { }
 ├─ oauth: GmailOAuthManager     — PKCE OAuth flow, token refresh
 ├─ claude: ClaudeAgentService   — categorize() / suggestDraft(), both forced tool-use
 └─ syncCoordinator: SyncCoordinator
     syncNow() pipeline: fetch (GmailProvider) → cache → categorize (needs API key)
     → draft-suggest (needsReply messages w/o a live suggestion) → persist → Spotlight reindex
```

Key conventions already established in the code — follow them rather than
introducing new patterns:

- **All store mutations go through `AppState.mutateStore { }`.** It's what
  keeps `AppStorePersistence.save` and derived UI state (pending count, dock
  badge) in sync. Never mutate `AppState.store` directly from a view or
  service.
- **Secrets only ever live in Keychain** (`KeychainStore`), never in
  `AppStore`/`store.json`. If you add a new secret (another provider's OAuth
  tokens, another API key), follow the existing `KeychainKeys` pattern.
- **Claude calls use forced tool-use**, not free-text parsing — see
  `ClaudeAgentService.categorize`/`suggestDraft` and `ClaudeAPIClient.callTool`.
  If you add a new Claude-backed feature, do the same (define a `ClaudeTool`
  with a JSON schema, force `tool_choice`) rather than parsing prose.
- **`MailProvider` is the seam for a second mail backend.** Gmail is the only
  implementation today. If asked to add another provider (e.g. IMAP/iCloud),
  implement the protocol and keep `SyncCoordinator`/UI provider-agnostic —
  don't leak Gmail-specific types above that boundary.
- **Persistence is a hand-rolled JSON file on purpose** (see comment in
  `AppStorePersistence.swift`) — not Core Data/SwiftData. Don't "upgrade" this
  unprompted; the ability to inspect/hand-edit `store.json` during
  prompt/schema iteration is a deliberate tradeoff for this solo project.
- **No send code path exists, and it should stay that way** unless the user
  explicitly asks for it. `GmailProvider.createDraft` only ever creates
  Gmail drafts. Adding a "send" capability is a meaningful trust boundary
  change for this app — treat it as something to flag/confirm, not do
  silently as part of an unrelated task.

## Naming: fully "Mailify" now

The project was originally called "WhatIf" and later renamed. As of
2026-08-15 the rename is complete everywhere — bundle id `com.hari.mailify`,
OAuth redirect scheme `com.hari.mailify`, Keychain service names
`com.hari.mailify.*`, Spotlight domain identifier `com.hari.mailify.email`,
App Support data dir `~/Library/Application Support/Mailify/`,
`build-app.sh` output `Mailify.app`/binary `Mailify`, and all doc references
point at `Sources/Mailify/...`. There should be no lingering "whatif"/"WhatIf"
strings — if you find one, it's a regression, not intentional.

If you ever touch the bundle identifier or OAuth redirect scheme again,
remember `GmailOAuthManager.swift`'s `redirectURI`/`redirectScheme` and
`build-app.sh`'s `CFBundleIdentifier`/`CFBundleURLSchemes` **must stay in
sync** — a mismatch breaks the OAuth redirect silently. Likewise, changing
the App Support directory name again will orphan any existing `store.json`
unless you migrate it (not a concern right now — the store was empty and no
Keychain secrets existed at the time of the 2026-08-15 rename).

## Icon

`Resources/AppIcon.icns` is generated, not hand-drawn in an image editor: a
Swift/AppKit script draws a macOS-style squircle (purple→teal gradient
matching the category palette) with a white `envelope.fill` SF Symbol glyph,
exports a 1024×1024 PNG, then `sips` + `iconutil` build the `.icns` from the
standard size set. If you want to change it, regenerate from a new master
PNG rather than hand-editing the `.icns`.

## Repo state

This is a git repository, pushed to `https://github.com/hareev/mailify`
(remote `origin`, branch `main`).

## Secrets handling

`Sources/Mailify/Gmail/GmailOAuthManager.swift` holds a real, filled-in
Google OAuth `clientID`/`clientSecret` locally and is **gitignored** — never
remove it from `.gitignore` or force-add it. The repo instead tracks
`GmailOAuthManager.swift.example`, a template with placeholder
(`YOUR_CLIENT_ID...`/`YOUR_CLIENT_SECRET`) constants; see `SETUP-GMAIL.md`
step 5 for the copy-and-fill-in steps a fresh clone needs. If you ever change
`GmailOAuthManager.swift`'s structure, mirror the same change into the
`.example` file so they stay in sync — the example is what fresh clones and
GitHub visitors actually see.
