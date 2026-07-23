# CLAUDE.md — Tydly repo guide

Guidance for future Claude Code sessions working in this repo. The design handoff (the
authoritative spec) lives in [`DesignHandoff/`](DesignHandoff/): `CLAUDE.md` (briefing),
`README.md` (screens/interactions/state), `DESIGN.md` (tokens/components/voice), and the two
`.dc.html` files — open `DesignHandoff/Archivaris Journey.dc.html` in a browser for visual
truth (phases 01–07).

## What this is

A native macOS menu-bar app (Swift/SwiftUI, `MenuBarExtra`). Tydly is the brand; **Otto** is
the default, user-chosen persona name (fallback "Archivist"). See `README.md` for status and
how to run it.

## The 10 non-negotiable product rules (verbatim)

1. **Nothing moves without consent** until a rule is explicitly promoted by the user.
2. **Sensitive files** (IDs, financial/medical docs) can never become auto-filed — permanently ask-first.
3. **Every action undoable**, individually and per batch; undo history survives restarts.
4. **Autonomy is offered, never taken**; rules self-demote after 2 mistakes/week.
5. **Red = broken only.** Amber = waiting on user. Never use red for busy states.
6. **The whisper bar never asks questions** — decisions live only in the popover.
7. **No notifications** (NSUserNotification/UNUserNotificationCenter) — the icon badge, popover, and whisper bar are the only surfaces.
8. Menubar icon **never animates when idle**.
9. Decline/paywall states delete nothing ("Otto is resting" = watch-only).
10. Skipped decisions self-mute (park, re-ask once Friday, then silence).

These are enforced in `Sources/TydlyCore/Rules.swift` and pinned by `Tests/TydlyCoreTests`.
**Do not weaken them in code. Ask the user before deviating from any of them.**

## Architecture decisions (made in the scaffold)

- **Swift Package, no Xcode IDE.** Command-line workflow via the `Makefile`
  (`make run/test/app`). Chosen with the user; keeps the door open to other platforms.
- **macOS 26 on Apple silicon.** The owner approved raising the minimum so semantic
  classification can use Apple's on-device Foundation Models framework. Swift 6.2 and the
  macOS 26 SDK are required; no cloud fallback is allowed.
- **Five targets.** `TydlyCore` (pure policy), `TydlyAI` (tool-free local model),
  `TydlyPersistence` (encrypted ledger), `TydlyMacEngine` (scoped macOS capabilities), and
  `Tydly` (SwiftUI/AppKit UI). Keep UI-agnostic logic in Core and English in Localization.
- **`MenuBarExtra` (`.window` style)** for icon + popover; a thin AppKit `AppDelegate` owns
  windows/panels that sit outside the scene (onboarding now; whisper `NSPanel` next).
- **Menu-bar glyph** is a programmatically rendered *template* `NSImage` (`MenuGlyph`) so
  macOS tints it; badges are separate colored overlays.
- **No file mover yet.** `AppModel` still uses `SampleData`. `TydlyPersistence` now supplies
  the SQLCipher prepare-before-mutation ledger, recovery matrix, inverse undo records,
  encrypted backups, and quarantine. Security-scoped root generations and the race-safe
  mover must use this substrate; FSEvents remains only a rescan hint.
- **Capabilities before files.** `TydlyMacEngine` captures Desktop/Downloads through
  atomic Powerbox selection, encrypted immutable bookmark generations, ledger-wide CAS,
  complete policy/identity revalidation, and closure-scoped balanced access. No watcher or
  mover may bypass this store or persist a resolved absolute path.
- **AI is advisory.** `TydlyAI` receives bounded path-free evidence and candidate IDs, has no
  tools, and returns allowlisted IDs only. Deterministic `TydlyCore` policy owns sensitivity,
  consent, autonomy, resting mode, confidence, execution, and undo. See
  `Documentation/AI_ENGINE.md`.

## Conventions

- **Tokens only.** Colors/type/radii/spacing come from `DesignSystem/Theme.swift`; components
  from `DesignSystem/Components.swift`. Don't hand-roll values that exist as tokens.
- **Color semantics are exclusive:** green = tidy, blue = working, amber = waiting-on-user,
  grey = paused, red = broken. (Rule 5.)
- **Voice:** numbers over sentences; reasons on demand ("why?"); one reassurance sentence per
  surface; receipts read verb + count + folder chip ("Filed 12 → Atlas"), never "12 → Atlas".
- **Localization:** all user-facing copy goes through `L` (`Localization.swift`) →
  `Resources/en.lproj/Localizable.strings`. Dutch (`nl.lproj`) is planned next: swap values,
  don't touch call sites.
- **Accessibility & motion:** VoiceOver labels on controls; respect `accessibilityReduceMotion`
  (no pulse/ghost travel; state swaps instant).
- Model identifiers, session URLs, and internal tooling names never appear in commits, PRs, or
  code.

## Known, flagged deviation from the mock

- The naming-step preview reads **"Signs their work as [Name]"** (neutral) rather than the
  mock's "Signs his work as". The persona is user-named (Otto / Ada / Juno / custom), so a
  gendered pronoun would be wrong for most choices. Flagged for the user; revert if they want
  the literal mock copy. (`L.onboarding_signs`.)

## Definition of done per screen

Matches the Journey mock at 1× on a 2560×1440 display, light mode; dark mode via system
materials; Reduce Motion respected; VoiceOver labels on every control; ⌘Z undoes the last
batch while the popover is open.

## Next phases (suggested order)

Finder demonstration (Phase 02) → whisper bar `NSPanel` (Phase 04) → error/repair states
(Phase 05) → rules pane + weekly note + trial/rest (Phase 06) → settings window (Phase 07) →
real file engine + undo journal.
