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
| Encrypted operation ledger, inverse undo records, and crash reconciliation | ✅ foundation |
| Encrypted security-scoped Desktop/Downloads capability generations | ✅ foundation |
| Agent orchestration contract — posture, sweeps, plans, memory protocols | ✅ foundation |
| Scoped inventory + metadata-only evidence → the first real decision | ⏳ next |
| Finder demonstration, whisper bar, error states, rules pane, settings, weekly note | ⏳ next |
| Real file engine (FSEvents, XPC extraction, race-safe moves) | ⏳ next |

There is **no watcher or file mover yet** — state remains seeded from `SampleData`. The
encrypted ledger can reconcile intent, onboarding can persist least-privilege folder grants,
and `TydlyAgent` defines the orchestration loop, but nothing inventories or mutates user
files and the agent is not yet wired to the UI.

What Tydly is trying to be, and how Otto behaves when the local model is unavailable, is in
[`Documentation/PRODUCT_VISION.md`](Documentation/PRODUCT_VISION.md).

## Requirements

- An Apple-silicon Mac running macOS 26 or later.
- Apple Intelligence enabled for semantic reranking. Tydly remains deterministic and
  ask-first when the on-device model is unavailable.
- Swift 6.2 and the macOS 26 SDK from Xcode 26 or matching Command Line Tools. You never
  open the Xcode IDE — everything is command-line.

## Run it

```sh
make run      # debug build, launches Tydly in the menu bar (Ctrl-C to quit)
make test     # unit suite + abrupt-process ledger recovery probes
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

Six targets keep policy testable and prevent the model from receiving filesystem powers:

- **`TydlyCore`** — pure Foundation. Domain types (`AgentState`, `FilingRule`, `Decision`,
  …), path-free AI contracts, and rule/execution policy. No SwiftUI, AppKit, or Combine.
- **`TydlyAI`** — the constrained, tool-free adapter to Apple's on-device Foundation Models
  framework. It returns allowlisted project and evidence IDs only.
- **`TydlyAgent`** — Otto's orchestration loop: posture and watch-only reasons, one sweep at a
  time with cancellation and idle deferral, typed path-free evidence, immutable plans, and the
  agent-memory protocols. It never touches the filesystem and never authorizes execution.
- **`TydlyPersistence`** — the single-writer SQLCipher ledger and Keychain key store. It
  records authorization, relative-path intent, transitions, inverse undo, and repair state,
  but owns no move API. Authorization is bound to the exact batch digest and authenticated
  with a ledger-key-derived HMAC; unresolved repair blocks all new mutation intent.
- **`TydlyMacEngine`** — immutable bookmark generations, fail-closed root policy, and
  closure-scoped balanced access. It contains no watcher or mover yet.
- **`Tydly`** — the macOS executable. SwiftUI `MenuBarExtra` for the icon + popover, a thin
  AppKit `AppDelegate` for the floating onboarding window, `AppModel` (`ObservableObject`)
  wrapping the core.

```
Sources/
  TydlyCore/         AgentState · Domain · Rules · AIContracts · ExecutionPolicy · SampleData
  TydlyAI/           FoundationModelClassifier
  TydlyAgent/        AgentPosture · AgentEvidence · AgentMemory · AgentPlan · TydlyAgent
  TydlyPersistence/  DatabaseKeyStore · EncryptedOperationLedger · quarantine
  TydlyMacEngine/    Bookmark adapters · root policy · capability store
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
  TydlyAgentTests/            Posture · sweep admission/cancellation · plan digest
  TydlyPersistenceTests/      Encryption · recovery · inverse undo · backup · quarantine
  TydlyMacEngineTests/        Policy · atomic selection · stale/revoked access · CAS
```

### Privacy is structural

`Sources/Tydly/Tydly.entitlements` enables the App Sandbox and user-selected file access but
**deliberately omits `com.apple.security.network.client`** — signed with these entitlements,
the app *cannot* open an outbound connection. `LSUIElement` in `Info.plist` keeps it a
menu-bar agent (no Dock icon). Development app bundles are ad-hoc signed with this same
entitlement set, and CI audits both source and signed output. Classification uses only
`SystemLanguageModel`; it has no tools and no cloud fallback.

The ledger uses SQLCipher 4.17.0 through Zetetic's managed GRDB 7.11.1 fork, both pinned to
immutable revisions. Its 256-bit key is nonsynchronizing. Production defaults to the Data
Protection Keychain and requires a provisioned signing identity; ad-hoc CI verifies local
Keychain plumbing separately because it cannot impersonate Apple's restricted access group.

Desktop and Downloads are selected through separate `NSOpenPanel` Powerbox grants and
committed atomically. Bookmarks resolve without UI, mounting, or path fallback. Local,
non-provider, non-overlapping policy and immutable identity are rechecked on every use.
A ledger revision CAS plus crash-releasing process lock protects validation across stores;
historical recovery also reserves its referenced nonterminal operation.

## The ten non-negotiable rules

They live as code in `TydlyCore` (see `Rules.swift`) and are pinned by tests
(`Tests/TydlyCoreTests`), not left to UI convention. In short: nothing moves without
consent; sensitive files are permanently ask-first; every action is undoable; autonomy is
offered, never taken (and self-demotes after 2 mistakes/week); red means broken only; the
icon never animates when idle; there are no notifications; declining deletes nothing;
skipped decisions self-mute. The full list is in `DesignHandoff/CLAUDE.md` and the root
`CLAUDE.md`.

## Note on the build environment

The package is verified by an Apple-silicon macOS 26 runner: `swift build`, 70 Core/AI/
persistence/capability tests, abrupt-process recovery probes, signed release app assembly,
privacy audit, and a detached app-bundle launch. Powerbox behavior, menu-bar interaction,
and pixel fidelity still need checking on a logged-in Mac with `make run`.
