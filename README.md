# Tydly

A local, trust-earning file archivist that lives in the macOS menu bar. Its agent persona
(user-named, default **Otto**) watches only approved folders (Desktop, Downloads), groups
clutter by *project* rather than file type, proposes moves, demonstrates them in Finder
before acting, and earns per-category autonomy over time. Every move is undoable. **Nothing
leaves the Mac** — no account, no cloud, no network entitlement.

This repository is the native implementation of the design handoff in
[`DesignHandoff/`](DesignHandoff/). The HTML files there are the visual source of truth;
`DesignHandoff/DESIGN.md` holds the tokens and `DesignHandoff/README.md` the screen specs.
The reviewed backend threat model and AI design live in
[`Documentation/SECURITY.md`](Documentation/SECURITY.md) and
[`Documentation/AI_ENGINE.md`](Documentation/AI_ENGINE.md).

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
| Security-first execution policy + local Foundation Models boundary | ✅ foundation |
| Finder demonstration, whisper bar, error states, rules pane, settings, weekly note | ⏳ next |
| Real file engine (FSEvents, journal/undo, security-scoped bookmarks) | ⏳ next |

There is **no file engine yet** — state is seeded from `SampleData` so every screen renders
the real design, and intents (approve / skip / undo) mutate in-memory state so the popover
feels live.

## Requirements

- An Apple-silicon Mac running macOS 26 or later.
- Apple Intelligence enabled for semantic reranking. Tydly remains deterministic and
  ask-first when the on-device model is unavailable.
- Swift 6.2 and the macOS 26 SDK from Xcode 26 or matching Command Line Tools. You never
  open the Xcode IDE — everything is command-line.

## Run it

```sh
make run      # debug build, launches Tydly in the menu bar (Ctrl-C to quit)
make test     # runs the Core and local-AI policy tests
make app      # assembles dist/Tydly.app (a proper menu-bar agent bundle)
make audit    # verifies signing, sandbox, and no-network invariants
make open     # build the .app and launch it
```

On first launch the onboarding card appears. After that, click the menu-bar glyph for the
popover.

### Seeing every screen (no Xcode previews)

Xcode's canvas previews aren't part of this workflow, so debug builds include an in-app
switcher at the foot of the popover: **All tidy · Decision · Working · Observing**, plus
**Replay onboarding**. It is compiled out of release builds (`#if DEBUG`).

## Architecture

Three targets keep policy testable and prevent the model from receiving filesystem powers:

- **`TydlyCore`** — pure Foundation. Domain types (`AgentState`, `FilingRule`, `Decision`,
  …), path-free AI contracts, and rule/execution policy. No SwiftUI, AppKit, or Combine.
- **`TydlyAI`** — the constrained, tool-free adapter to Apple's on-device Foundation Models
  framework. It returns allowlisted project and evidence IDs only.
- **`Tydly`** — the macOS executable. SwiftUI `MenuBarExtra` for the icon + popover, a thin
  AppKit `AppDelegate` for the floating onboarding window, `AppModel` (`ObservableObject`)
  wrapping the core.

```
Sources/
  TydlyCore/         AgentState · Domain · Rules · AIContracts · ExecutionPolicy · SampleData
  TydlyAI/           FoundationModelClassifier
  Tydly/
    TydlyApp.swift            @main, MenuBarExtra scene
    AppDelegate.swift         onboarding window (whisper bar later)
    AppModel.swift            observable state + in-memory intents
    DesignSystem/             Theme (tokens) · Components · MenuGlyph
    MenuBar/                  MenuBarLabel (icon states)
    Popover/                  Root router + AllTidy · Decision · Working · Observing (+ DebugStateBar)
    Onboarding/              OnboardingView · Privacy · FolderScope · Naming · PageControl
    Localization.swift + Resources/en.lproj/Localizable.strings
Tests/
  TydlyCoreTests/             Rules · State · ExecutionPolicy
  TydlyAITests/               Allowlist · sensitivity · prompt-boundary validation
```

### Privacy is structural

`Sources/Tydly/Tydly.entitlements` enables the App Sandbox and user-selected file access but
**deliberately omits `com.apple.security.network.client`** — signed with these entitlements,
the app *cannot* open an outbound connection. `LSUIElement` in `Info.plist` keeps it a
menu-bar agent (no Dock icon). Development app bundles are ad-hoc signed with this same
entitlement set, and CI audits both source and signed output. Classification uses only
`SystemLanguageModel`; it has no tools and no cloud fallback.

## The ten non-negotiable rules

They live as code in `TydlyCore` (see `Rules.swift`) and are pinned by tests
(`Tests/TydlyCoreTests`), not left to UI convention. In short: nothing moves without
consent; sensitive files are permanently ask-first; every action is undoable; autonomy is
offered, never taken (and self-demotes after 2 mistakes/week); red means broken only; the
icon never animates when idle; there are no notifications; declining deletes nothing;
skipped decisions self-mute. The full list is in `DesignHandoff/CLAUDE.md` and the root
`CLAUDE.md`.

## Note on the build environment

The package is verified by an Apple-silicon macOS 26 runner: `swift build`, the Core and AI
policy tests, signed release app assembly, privacy audit, and a detached app-bundle launch.
Interactive menu-bar behavior and pixel fidelity still need checking on a logged-in Mac
with `make run`.
