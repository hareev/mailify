# Mailify — building with VS Code instead of Xcode

You still need Xcode's **Command Line Tools** — that's what provides
the `swift` compiler and macOS SDK. You never open Xcode itself.

```
xcode-select --install
```

If that command says tools are already installed, you're set.

## 1. VS Code extensions

- **Swift** (official, published by the Swift Server Work Group) —
  gives you syntax highlighting, autocomplete, and inline errors via
  sourcekit-lsp.
- **CodeLLDB** (Vadim Chugunov) — lets VS Code's debugger (breakpoints,
  step-through) work with compiled Swift binaries.

Install both from the Extensions panel (`Cmd+Shift+X`).

## 2. Open the project

`code Mailify` (or File → Open Folder). This is a Swift Package —
`Package.swift` at the root is what makes VS Code and `swift build`
recognize it, no `.xcodeproj` involved.

## 3. Build & run

- `Cmd+Shift+B` → runs the default build task (`swift build`), or from
  the terminal: `swift build`
- To actually launch it while iterating: `swift run`

In this dev-loop mode the app runs unbundled — it'll have a generic
Dock icon and the window works fine, menu bar extra works fine, but
Spotlight tap-to-open won't resolve correctly since there's no
registered `.app` yet. That's expected; it resolves once you package it.

## 4. Debug

Press `F5` (uses the provided `.vscode/launch.json`). Set breakpoints
in any `.swift` file as normal — this builds first, then launches
under CodeLLDB.

## 5. Package as a real .app

```
chmod +x build-app.sh   # first time only
./build-app.sh
open Mailify.app
```

This does a release build, hand-assembles the bundle structure
(`Contents/MacOS`, `Info.plist`), and ad-hoc code-signs it so
Gatekeeper, notifications, and Spotlight indexing all behave like a
normal installed app. Drag `Mailify.app` into `/Applications` to keep it.

## What's different from the Xcode version

The app UI is native SwiftUI throughout — no bundled resource files, so
SwiftPM's `Bundle.module` resource-path resolution (which gets unreliable
once you hand-move a binary into a `.app` structure outside Xcode) never
comes into play. The only WebView left in the app is
[HTMLBodyWebView.swift](Sources/Mailify/UI/MessageDetail/HTMLBodyWebView.swift),
a narrowly-scoped, read-only renderer for email HTML bodies — JavaScript
disabled, no message-handler bridge, no app logic inside it.

## Connecting Gmail

See [SETUP-GMAIL.md](SETUP-GMAIL.md) for the one-time Google Cloud OAuth
setup required before the Gmail connector will work.
