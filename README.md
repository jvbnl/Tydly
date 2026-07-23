# Tydly

A local, trust-earning file archivist that lives in the macOS menu bar. Its agent persona
(user-named, default **Otto**) watches only approved folders (Desktop, Downloads), groups
clutter by *project* rather than file type, proposes moves, demonstrates them in Finder
before acting, and earns per-category autonomy over time. Every move is undoable. **Nothing
leaves the Mac** — no account, no cloud, no network entitlement.

This repository is the native implementation of the design handoff in
[`DesignHandoff/`](DesignHandoff/). The HTML files there are the visual source of truth;
`DesignHandoff/DESIGN.md` holds the tokens and `DesignHandoff/README.md` the screen specs.

## Status

Scaffold + first screens, built in the phase order requested: **menu-bar icon states →
popover (all tidy / decision / working) → onboarding.**

| Area | State |
|---|---|
| Project scaffold (SwiftPM, menu-bar agent, no Xcode) | ✅ |
| Design system — tokens, components, template glyph | ✅ |
| Menu-bar icon: 5 states (quiet / working+pulse / needs-you / paused / broken) | ✅ |
| Popover: All tidy, Decision waiting, Working, Observing | ✅ |
| Onboarding: Privacy → Folder scope → Naming | ✅ |
| The 10 product rules encoded + unit-tested in `TydlyCore` | ✅ |
| Finder demonstration, whisper bar, error states, rules pane, settings, weekly note | ⏳ next |
| Real file engine (FSEvents, journal/undo, security-scoped bookmarks) | ⏳ next |

There is **no file engine yet** — state is seeded from `SampleData` so every screen renders
the real design, and intents (approve / skip / undo) mutate in-memory state so the popover
feels live.

## Requirements

- macOS 13 (Ventura) or later — `MenuBarExtra` requires it.
- The macOS SDK: **Xcode.app or the Command Line Tools** installed once
  (`xcode-select --install`). You never open the Xcode IDE — everything is command-line.

## Run it

```sh
make run      # debug build, launches Tydly in the menu bar (Ctrl-C to quit)
make test     # runs the TydlyCore rule tests
make app      # assembles dist/Tydly.app (a proper menu-bar agent bundle)
make open     # build the .app and launch it
```

On first launch the onboarding card appears. After that, click the menu-bar glyph for the
popover.

### Seeing every screen (no Xcode previews)

Xcode's canvas previews aren't part of this workflow, so debug builds include an in-app
switcher at the foot of the popover: **All tidy · Decision · Working · Observing**, plus
**Replay onboarding**. It is compiled out of release builds (`#if DEBUG`).

## Architecture

Two targets, so a future move to other platforms stays cheap and the rules stay testable:

- **`TydlyCore`** — pure Foundation. Domain types (`AgentState`, `FilingRule`, `Decision`,
  …) and the rule-enforcement logic (`Rules`). No SwiftUI, AppKit, or Combine.
- **`Tydly`** — the macOS executable. SwiftUI `MenuBarExtra` for the icon + popover, a thin
  AppKit `AppDelegate` for the floating onboarding window, `AppModel` (`ObservableObject`)
  wrapping the core.

```
Sources/
  TydlyCore/         AgentState · Domain · Rules · SampleData
  Tydly/
    TydlyApp.swift            @main, MenuBarExtra scene
    AppDelegate.swift         onboarding window (whisper bar later)
    AppModel.swift            observable state + in-memory intents
    DesignSystem/             Theme (tokens) · Components · MenuGlyph
    MenuBar/                  MenuBarLabel (icon states)
    Popover/                  Root router + AllTidy · Decision · Working · Observing (+ DebugStateBar)
    Onboarding/              OnboardingView · Privacy · FolderScope · Naming · PageControl
    Localization.swift + Resources/en.lproj/Localizable.strings
Tests/TydlyCoreTests/         RulesTests · StateTests
```

### Privacy is structural

`Sources/Tydly/Tydly.entitlements` enables the App Sandbox and user-selected file access but
**deliberately omits `com.apple.security.network.client`** — signed with these entitlements,
the app *cannot* open an outbound connection. `LSUIElement` in `Info.plist` keeps it a
menu-bar agent (no Dock icon). Classification will run fully on-device.

## The ten non-negotiable rules

They live as code in `TydlyCore` (see `Rules.swift`) and are pinned by tests
(`Tests/TydlyCoreTests`), not left to UI convention. In short: nothing moves without
consent; sensitive files are permanently ask-first; every action is undoable; autonomy is
offered, never taken (and self-demotes after 2 mistakes/week); red means broken only; the
icon never animates when idle; there are no notifications; declining deletes nothing;
skipped decisions self-mute. The full list is in `DesignHandoff/CLAUDE.md` and the root
`CLAUDE.md`.

## Note on the build environment

The package is verified on macOS 14 with Apple Swift 5.10: `swift build`, all 13
`TydlyCore` tests, release app assembly, and a detached app-bundle launch pass. Interactive
menu-bar behavior and pixel fidelity still need checking on a logged-in Mac with `make run`.
