# AGENTS.md — handover for the next agent (Codex)

You're picking up **Tydly**, a native macOS menu-bar app. This file is the handover; Codex
loads `AGENTS.md` automatically, so start here. `CLAUDE.md` and `README.md` cover the same
ground for humans — this doc adds *current state, what's unverified, and what to do next.*

## TL;DR

- Swift Package (no Xcode IDE). Build/run from the CLI: `make run`, `make test`, `make app`.
- Requires macOS 13+ and the macOS SDK (Xcode.app **or** Command Line Tools). Don't move to
  an Xcode project — the owner deliberately wants a Swift-only, CLI-driven workflow, with an
  eye on other platforms later.
- Two targets: **`TydlyCore`** (pure Foundation — model + the product rules, unit-tested) and
  **`Tydly`** (macOS SwiftUI/AppKit UI).
- The package builds and its tests pass on macOS 14 with Apple Swift 5.10. Interactive
  menu-bar and pixel-fidelity checks still need a logged-in Mac. See "Verify first".

## What Tydly is

A local, trust-earning file archivist in the menu bar. Its persona (user-named, default
"Otto") watches only Desktop + Downloads, groups clutter by *project*, proposes moves,
demonstrates them in Finder before acting, and earns per-category autonomy over time. Every
move is undoable. **Nothing leaves the Mac** — no account, no cloud, no network entitlement.

Authoritative spec is the design handoff in `DesignHandoff/`:
- `Archivaris Journey.dc.html` — **visual source of truth**, phases 01–07 (open in a browser).
- `README.md` — screens, interactions, state machine. `DESIGN.md` — tokens, components, voice.
- `CLAUDE.md` — the original implementation briefing.

## Current status

Implemented (phase order requested by the owner: icon → popover → onboarding):

| Area | File(s) | State |
|---|---|---|
| SwiftPM scaffold, Makefile, app-bundle script | `Package.swift`, `Makefile`, `Scripts/` | build + bundle verified |
| Design tokens + components + template glyph | `Sources/Tydly/DesignSystem/` | compiled, visual check pending |
| Menu-bar icon, 5 states | `Sources/Tydly/MenuBar/MenuBarLabel.swift` | compiled, visual check pending |
| Popover: All tidy / Decision / Working / Observing | `Sources/Tydly/Popover/` | compiled, visual check pending |
| Onboarding: Privacy → Folder scope → Naming | `Sources/Tydly/Onboarding/` | compiled, interaction check pending |
| Domain model + 10 rules as logic | `Sources/TydlyCore/` | compiled |
| Rule tests | `Tests/TydlyCoreTests/` | 13 passing |

**Not built yet** (see "Next phases"): Finder demonstration (Phase 02), whisper bar (04),
error/repair states (05), rule offer + rules pane + weekly note + trial/rest (06), settings
window (07), and the **real file engine** (FSEvents, moves, undo journal, security-scoped
bookmarks). There is **no file engine** — `AppModel` seeds `TydlyCore.SampleData` and mutates
in-memory so every screen renders and the approve/skip/undo loop feels live.

## Verify first

`swift build`, `swift test`, `make app`, and a detached app-bundle launch pass on macOS 14
with Apple Swift 5.10. The initial compiler shakeout fixed a `Subscription` name collision
with Combine; packaged localization now resolves from `Contents/Resources` without relying
on SwiftPM's build directory. Before starting the next phase, run `make run` on a logged-in
Mac and complete these interactive checks:

1. **`MenuBarExtra` label updates.** The icon re-renders because `TydlyApp` observes
   `AppModel` (a `@StateObject`). If the menu-bar icon doesn't update on state change on your
   target OS, fall back to an AppKit `NSStatusItem` managed in `AppDelegate` (keep `MenuGlyph`
   + the badge overlays). Owner asked for `MenuBarExtra`, so try to keep it.
2. **Embedded Info.plist for `swift run`.** `Package.swift` embeds `Sources/Tydly/Info.plist`
   via `-sectcreate` linker flags so `swift run` launches as a menu-bar agent (`LSUIElement`,
   no Dock icon). Confirm the item appears and there's no Dock icon. If flaky, use `make app`
   (bundles a real `.app`).
3. **Localization via `Bundle.module`.** `L` (`Localization.swift`) uses
   `NSLocalizedString(..., bundle: .module, ...)` reading `Resources/en.lproj/Localizable.strings`.
   Confirm strings resolve (they fall back to the English key if not, so worst case is silent
   identity — check the table is actually found).
4. **Template glyph tint + colored badges.** `MenuGlyph` is an `isTemplate` NSImage (macOS
   tints it); badges are separate colored overlays. Verify the glyph tints for light/dark
   menu bars while the blue/amber/red badges keep their color.
5. **Onboarding window key focus.** The naming step has a `TextField`. The window is `.titled`
   with transparent chrome (`AppDelegate.showOnboarding`) specifically so it can become key
   and accept typing. Verify custom-name entry works.
6. **⌘Z undo.** `PopoverRootView` owns a hidden keyboard-shortcut button. Verify ⌘Z undoes the
   last batch while the popover is open.

The automated build and rule checks run on every branch update. Eyeball `make run` against
the Journey mock at 1× before marking the current screens visually verified.

## Build / run / iterate

```sh
make run     # debug build → launches in the menu bar (Ctrl-C quits)
make test    # TydlyCore rule tests
make app     # dist/Tydly.app (proper menu-bar agent bundle)
make open    # build + launch the .app
```

No SwiftUI canvas previews (that's Xcode-only). Instead, **debug builds show an in-app state
switcher** at the foot of the popover (`#if DEBUG DebugStateBar`): jump between
All tidy / Decision / Working / Observing and replay onboarding. Use that to see every screen.

## Architecture & where things live

```
Sources/
  TydlyCore/            AgentState · Domain · Rules · SampleData   (pure Foundation, no UI)
  Tydly/
    TydlyApp.swift              @main; MenuBarExtra scene
    AppDelegate.swift           onboarding NSWindow (whisper NSPanel goes here next)
    AppModel.swift              ObservableObject; in-memory intents + DEBUG switcher
    Localization.swift          L → Resources/en.lproj/Localizable.strings
    DesignSystem/               Theme (tokens) · Components · MenuGlyph
    MenuBar/MenuBarLabel.swift  icon glyph + badge states
    Popover/                    PopoverRootView router + the four state bodies (+ DebugStateBar)
    Onboarding/                 OnboardingView · Privacy/FolderScope/Naming steps · PageControl
Tests/TydlyCoreTests/           RulesTests · StateTests
```

Layering rule: **UI-agnostic logic and all rule enforcement live in `TydlyCore`; user-facing
English lives only in the UI layer** (`Localization.swift`), so `TydlyCore` stays portable and
localization stays in one place. Compose display strings in views from Core data (counts,
kinds, project names) — don't put English in Core.

## The ten non-negotiable rules — DO NOT WEAKEN

They are encoded as logic in `Sources/TydlyCore/Rules.swift` and pinned by
`Tests/TydlyCoreTests/`, not left to UI convention. Full text in `CLAUDE.md`. The ones most
easily broken by well-meaning changes:

- **Rule 2** — sensitive files can *never* auto-file. `Rules.autonomyCeiling`/`cappedAutonomy`
  clamp them to `.propose` forever. Don't add a bypass.
- **Rule 4** — autonomy is *offered*, never taken; rules self-demote after 2 mistakes/week
  (`Rules.afterMistake`). Never auto-promote.
- **Rule 5** — red is for *broken* only. Amber = waiting on user. Never red for busy.
- **Rule 7** — **no notifications frameworks** (`UserNotifications`/`NSUserNotification`). The
  icon, popover, and whisper bar are the only surfaces. (Grep stays clean — keep it that way.)
- **Rule 8** — icon never animates when idle (`AgentState.iconAnimates`).
- **Rule 3** — every action undoable, individually and per batch; undo must survive restarts
  (needs the journal — see below).

If a task seems to require weakening any rule, **stop and ask the owner** — they asked to be
consulted before any deviation.

## Conventions

- **Tokens only** — colors/type/radii from `DesignSystem/Theme.swift`, components from
  `Components.swift`. Don't hand-roll values that exist as tokens.
- **Voice** (DESIGN.md §Voice) — numbers over sentences; reasons on demand ("why?"); one
  reassurance sentence per surface; receipts are verb + count + folder chip
  ("Filed 12 → Atlas"), never "12 → Atlas".
- **Accessibility & motion** — VoiceOver labels on controls; honor
  `accessibilityReduceMotion` (no pulse/travel; state swaps instant).
- **No emoji** in UI. SF Symbols per DESIGN.md mapping.
- Never put model identifiers, session URLs, or internal tooling names in commits, PRs, or code.

## Known deviation from the mock (owner is aware)

Naming preview reads **"Signs their work as [Name]"** (neutral) instead of the mock's
"Signs his work as" — the persona is user-named (Otto/Ada/Juno/custom), so "his" is wrong for
most choices. One-line change in `Localization.swift` (`onboarding_signs`) if the owner wants
the literal mock copy.

## Next phases (suggested order + notes)

1. **Finder demonstration (Phase 02).** "Show me" currently stands in by approving directly
   (`DecisionView` → `AppModel.approveTopDecision`). Replace with the real demonstration:
   full-screen transparent overlay drawing ghost files + the "Otto" cursor over a Finder
   snapshot; Esc aborts with zero filesystem changes; "Looks Right" executes. Degrade to a
   plan window + inline diff if overlaying Finder is fragile. Spec: `DesignHandoff/README.md`
   §Phase 02 and the `.wall`/`.gho`/`.cur` classes in the Journey HTML.
2. **Whisper bar (Phase 04).** Borderless non-activating `NSPanel`, floating, bottom-center,
   auto-dismiss 4s, **never asks questions** (Rule 6). Manage it in `AppDelegate`.
3. **Error/repair states (Phase 05)** and **growing-trust (Phase 06)** popover bodies — the
   model already has the types (`ErrorKind`, `FilingRule`, `Subscription`).
4. **Settings window (Phase 07).**
5. **Real file engine.** `FileManager` moves recorded in a journal
   (source/dest/timestamp/batchID) → powers undo that survives restarts (Rule 3). FSEvents for
   watching, sweeping only when idle. Security-scoped bookmarks from `NSOpenPanel` for folder
   access. Persist rules/journal/stats (SQLite or SwiftData) in App Support. **Keep the sandbox
   network-free** — do not add `com.apple.security.network.client` (`Tydly.entitlements`).

## Guardrails

- Don't convert to an Xcode project or add an Xcode-only workflow.
- Don't add a network entitlement or any outbound networking. Classification runs on-device.
- Don't weaken the ten rules; ask first.
- Keep English copy out of `TydlyCore`; keep rule logic out of the views.
