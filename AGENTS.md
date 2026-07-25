# AGENTS.md — handover for the next agent (Codex)

You're picking up **Tydly**, a native macOS menu-bar app. This file is the handover; Codex
loads `AGENTS.md` automatically, so start here. `CLAUDE.md` and `README.md` cover the same
ground for humans — this doc adds *current state, what's unverified, and what to do next.*

## TL;DR

- Swift Package (no Xcode IDE). Build/run from the CLI: `make run`, `make test`, `make app`.
- Requires an Apple-silicon Mac on macOS 26+, Swift 6.2, and the macOS 26 SDK. The owner
  explicitly approved the higher floor for Apple's fully local Foundation Models framework.
  Don't move to an Xcode project; the workflow remains SwiftPM and CLI-only.
- Six targets: **`TydlyCore`** (pure policy/contracts), **`TydlyAI`** (tool-free local
  model), **`TydlyAgent`** (Otto's orchestration loop), **`TydlyPersistence`** (encrypted
  ledger), **`TydlyMacEngine`** (scoped macOS capabilities), and **`Tydly`** (UI).
- The package builds and its Core/AI tests, signed bundle audit, and detached launch pass on
  an Apple-silicon macOS 26 runner. Interactive checks still need a logged-in Mac.

## What Tydly is

A local, trust-earning file archivist in the menu bar. Its persona (user-named, default
"Otto") watches only Desktop + Downloads, groups clutter by *project*, proposes moves,
demonstrates them in Finder before acting, and earns per-category autonomy over time. Every
move is undoable. **Nothing leaves the Mac** — no account, no cloud, no network entitlement.

Authoritative spec is the design handoff in `DesignHandoff/`:
- `Archivaris Journey.dc.html` — **visual source of truth**, phases 01–07 (open in a browser).
- `README.md` — screens, interactions, state machine. `DESIGN.md` — tokens, components, voice.
- `CLAUDE.md` — the original implementation briefing.

Product/backend/security sources of truth:
- `Documentation/PRODUCT_VISION.md` — **"Otto is the product"**, the agent loop, watch-only
  behaviour, the working-alpha scenario, and product-quality metrics.
- `Documentation/SECURITY.md` — threat model, capabilities, journal/move protocol, release gates.
- `Documentation/AI_ENGINE.md` — evidence-first classifier, sensitivity lattice, prompt boundary.
- Linear project: `https://linear.app/agentinc/project/tydly-d103ba5afcdb` (AgentHuddle team;
  do not use Gymly).

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
| AI contracts + automatic-execution policy | `Sources/TydlyCore/` | implemented + tested |
| Local Foundation Models reranker | `Sources/TydlyAI/` | implemented + validated boundary |
| Agent orchestration contract (posture, sweep, plan, memory) | `Sources/TydlyAgent/` | implemented + tested; not yet wired to the UI |
| SQLCipher operation ledger + crash recovery | `Sources/TydlyPersistence/` | implemented + disk-tested |
| Security-scoped root generations | `Sources/TydlyMacEngine/` | implemented + policy-tested |
| Signed sandbox + privacy audit | `Scripts/`, `.github/workflows/macos.yml` | verified on macOS 26 |
| Core, AI, persistence, capability, and crash tests | `Tests/`, `Scripts/` | 70 passing |

**Not built yet** (see "Next phases"): Finder demonstration (Phase 02), whisper bar (04),
error/repair states (05), rule offer + rules pane + weekly note + trial/rest (06), settings
window (07), and the **real file mover** (FSEvents and safe moves).
The encrypted ledger now records operation intent, authorization, inverse undo, and recovery,
onboarding captures encrypted Desktop/Downloads capabilities, and `TydlyAgent` defines the
orchestration contract — but no production code watches, extracts, or mutates files, and the
agent is not yet wired to the UI. `AppModel` still uses `SampleData`.

## Verify first

`swift build`, `swift test`, `make app`, `make audit`, and a detached app-bundle launch pass
on an Apple-silicon macOS 26 runner. Development app bundles are ad-hoc signed with the
production sandbox entitlements; they deliberately have no network capability. Before
starting the next phase, run `make run` on a logged-in Mac and complete these checks:

1. **`MenuBarExtra` label updates.** The icon re-renders because `TydlyApp` observes
   `AppModel` (a `@StateObject`). If the menu-bar icon doesn't update on state change on your
   target OS, fall back to an AppKit `NSStatusItem` managed in `AppDelegate` (keep `MenuGlyph`
   + the badge overlays). Owner asked for `MenuBarExtra`, so try to keep it.
2. **Embedded Info.plist for `swift run`.** `Package.swift` embeds `Sources/Tydly/Info.plist`
   via `-sectcreate` linker flags so `swift run` launches as a menu-bar agent (`LSUIElement`,
   no Dock icon). Confirm the item appears and there's no Dock icon. If flaky, use `make app`
   (bundles a real `.app`).
3. **Localization resource bundle.** `L` resolves `Tydly_Tydly.bundle` from the assembled
   app's `Contents/Resources`, with `Bundle.module` only as the SwiftPM fallback. Confirm the
   actual table loads; English fallback can otherwise hide a packaging error.
4. **Template glyph tint + colored badges.** `MenuGlyph` is an `isTemplate` NSImage (macOS
   tints it); badges are separate colored overlays. Verify the glyph tints for light/dark
   menu bars while the blue/amber/red badges keep their color.
5. **Onboarding window key focus.** The naming step has a `TextField`. The window is `.titled`
   with transparent chrome (`AppDelegate.showOnboarding`) specifically so it can become key
   and accept typing. Verify custom-name entry works.
6. **⌘Z undo.** `PopoverRootView` owns a hidden keyboard-shortcut button. Verify ⌘Z undoes the
   last batch while the popover is open.
7. **Powerbox capability flow.** Verify onboarding opens Desktop then Downloads panels,
   rejects any other/cloud/remote folder, commits neither selection after cancellation, and
   restores both grants after relaunch.

The automated build and rule checks run on every branch update. Eyeball `make run` against
the Journey mock at 1× before marking the current screens visually verified.

## Build / run / iterate

```sh
make run     # debug build → launches in the menu bar (Ctrl-C quits)
make test    # unit suite + abrupt-process ledger recovery probes
make app     # dist/Tydly.app (proper menu-bar agent bundle)
make audit   # signing, sandbox, minimum OS, and no-network checks
make open    # build + launch the .app
```

No SwiftUI canvas previews (that's Xcode-only). Instead, **debug builds show an in-app state
switcher** at the foot of the popover (`#if DEBUG DebugStateBar`): jump between
All tidy / Decision / Working / Observing and replay onboarding. Use that to see every screen.

## Architecture & where things live

```
Sources/
  TydlyCore/            Domain · Rules · AIContracts · ExecutionPolicy · OperationLedger
  TydlyAI/              FoundationModelClassifier (local, no tools/filesystem/network)
  TydlyAgent/           AgentPosture · AgentEvidence · AgentMemory · AgentPlan · TydlyAgent
  TydlyPersistence/     SQLCipher ledger · Keychain key store · quarantine
  TydlyMacEngine/       bookmark generations · policy · closure-scoped access
  Tydly/
    TydlyApp.swift              @main; MenuBarExtra scene
    AppDelegate.swift           onboarding NSWindow (whisper NSPanel goes here next)
    AppModel.swift              ObservableObject; in-memory intents + DEBUG switcher
    Localization.swift          L → Resources/en.lproj/Localizable.strings
    DesignSystem/               Theme (tokens) · Components · MenuGlyph
    MenuBar/MenuBarLabel.swift  icon glyph + badge states
    Popover/                    PopoverRootView router + the four state bodies (+ DebugStateBar)
    Onboarding/                 OnboardingView · Privacy/FolderScope/Naming steps · PageControl
Tests/
  TydlyCoreTests/               Rules · state · execution policy
  TydlyAITests/                 allowlist · sensitivity · prompt-boundary validation
  TydlyAgentTests/              posture · sweep admission/cancellation · plan digest
  TydlyPersistenceTests/        encryption · recovery · inverse undo · backup · quarantine
  TydlyMacEngineTests/          scope policy · stale refresh · migration · cancellation
```

Layering rule: **UI-agnostic logic and all rule enforcement live in `TydlyCore`; user-facing
English lives only in the UI layer** (`Localization.swift`), so `TydlyCore` stays portable and
localization stays in one place. Compose display strings in views from Core data (counts,
kinds, project names) — don't put English in Core.

`TydlyAI` is advisory only. It receives path-free bounded evidence and existing candidate
IDs, creates a fresh tool-free `SystemLanguageModel` session, and returns only validated
allowlisted IDs. It cannot clear sensitivity, report execution confidence, mutate rules, or
authorize a move. Never add cloud fallback, Private Cloud Compute, model downloads, or a
local model server.

`TydlyAgent` is Otto's orchestration loop and depends on `TydlyCore` only — the concrete
classifier and memory store are injected by the app layer, so the whole loop is testable
without Apple Intelligence or a disk. Three boundaries are structural: it never touches the
filesystem, never issues an `ExecutionAuthorization`, and never sees a path (evidence and
plans carry opaque IDs and root *generation* IDs). `AgentPolicy.posture` resolves the single
reason Otto is restrained — paused, resting, capability, repair, model — because a silent
agent reads as a broken one. Thermal and Low Power Mode arrive as an injected
`SystemConditions` reading rather than a direct `ProcessInfo` call, which keeps the target
pure Foundation.

`TydlyPersistence` owns no move API. It uses SQLCipher 4.17.0 through Zetetic's managed
GRDB 7.11.1 fork, pinned in `Package.resolved`. Existing stores never generate replacement
keys. Authorization is SHA-256-bound to the exact ordered batch and authenticated with an
HKDF-separated HMAC from the ledger key; any unresolved repair globally blocks new mutation
intent. Production defaults to a nonsynchronizing Data Protection Keychain key; this path
requires a provisioned signing identity, while ad-hoc CI can only verify legacy local
Keychain plumbing. Run the signed app with
`--verify-data-protection-keychain` as a provisioned release gate.

`TydlyMacEngine` derives Desktop/Downloads requirements internally, stores only encrypted
bookmarks plus opaque identity, and exposes access only inside balanced async closures.
Capabilities are atomically versioned with a ledger-wide CAS and crash-releasing file lock;
stale exact generations invalidate new plans. Historical recovery requires a referencing
nonterminal operation and reserves it against concurrent transition for the lease duration.

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
  (the ledger foundation exists; do not add moves until bookmark and mover integration uses it).

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
5. **Real file engine.** Follow `Documentation/SECURITY.md`. The ledger, root capability, and
   agent-orchestration substrates are present. FSEvents is only a rescan hint. Initial moves
   remain race-safe, no-overwrite, same-volume ordinary files with durable inverse undo.
   **Keep the sandbox network-free** — do not add
   `com.apple.security.network.client` (`Tydly.entitlements`).

   **Owner decision (25 July 2026) — metadata-only fast path first.** `CODEX_HANDOFF.md`
   sequences the isolated XPC content extractor (AH-76) ahead of real decisions. The owner
   chose to reach a real, human-visible proposal sooner instead:

   1. Scoped inventory + FSEvents reconciliation.
   2. **Metadata-only** evidence — filesystem facts, `UTType`, bounded filename tokens, dates.
      No file *contents* are parsed, so the malformed-input attack surface that motivates the
      XPC isolation does not exist yet, and no security property is weakened.
   3. Replace `SampleData` with real read-only decisions built from that evidence.
   4. **Then** AH-76: the signed, sandboxed read-only XPC extractor adds PDFKit/ImageIO/Vision
      content evidence behind the same `EvidenceBundleReference` contract.

   Two hard constraints on the fast path: metadata-only extraction yields at best
   `EvidenceCoverage.partial`, which keeps sensitivity `unknown` and therefore keeps every
   proposal permanently ask-first — correct for an ask-first alpha, and it must not be
   relaxed to `.complete` to unlock automation. And step 3 must land **read-only**: no mover
   until AH-77 and AH-74 are done.

## Guardrails

- Don't convert to an Xcode project or add an Xcode-only workflow.
- Don't add a network entitlement or any outbound networking. Classification runs on-device.
- Don't weaken the ten rules; ask first.
- Keep English copy out of `TydlyCore`; keep rule logic out of the views.
