# CLAUDE.md — Tydly implementation briefing

You are implementing **Tydly**, a native macOS menubar app: a local, trust-earning file archivist. This folder is a design handoff; read `README.md` (screens, interactions, state) and `DESIGN.md` (tokens, components, voice) before writing code. The HTML files are design references to recreate natively, not code to port.

## Naming
- **Tydly** is the product/brand name: app name, bundle, App Store, settings window title, marketing.
- **Otto** is the default *persona* name of the archivist agent inside Tydly, chosen by the user during onboarding (fallback "Archivist" if skipped). The mocks say "Otto" wherever the user-chosen agent name appears at runtime; the product itself is always Tydly.

## Product in one paragraph
Tydly's agent watches only user-approved folders (Desktop, Downloads), understands files by project context (not extension), proposes grouped moves, demonstrates them in Finder before acting (ghost preview + named cursor), and earns per-category autonomy through accepted proposals. Every action is undoable. Nothing ever leaves the Mac — no account, no cloud, no telemetry of file contents.

## Non-negotiable product rules
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

## Suggested architecture (adapt to taste)
- Swift 5.10+, SwiftUI-first; AppKit where SwiftUI falls short.
- `MenuBarExtra` (window style) for the popover; custom template image for the icon with badge overlay states.
- Whisper bar: borderless nonactivating `NSPanel`, floating level, bottom-center of the active screen, ignores mouse except its buttons.
- Finder demonstration: full-screen transparent overlay window drawing ghost icons + Otto cursor over a live-positioned snapshot; **or** degrade gracefully to the plan window + inline diff if overlaying Finder proves fragile. Esc must always abort with zero filesystem changes.
- File ops: `FileManager` moves recorded in a journal (source, dest, timestamp, batchID) → powers undo.
- Folder access via security-scoped bookmarks from `NSOpenPanel` (sandbox-friendly).
- Watching: FSEvents/`DispatchSource`; sweeps only when idle (respect `ProcessInfo.thermalState`, user activity).
- Classification runs fully on-device. No network entitlement in the sandbox — make the privacy promise structurally true.
- Persistence: SQLite or SwiftData for rules/journal/stats, in App Support.

## Where each spec lives
- Screens, layout, exact copy → `README.md` §Screens
- Colors/type/materials/SF Symbols/motion → `DESIGN.md`
- Behavior + state machine → `README.md` §Interactions, §State Management
- Visual truth → `Archivaris Journey.dc.html` (open in browser, phases 01–07)
- Rationale/alternatives → `Archivaris Wireframes.dc.html` (archive)

## Copy voice
Follow DESIGN.md §Voice strictly. The agent's name is user-chosen (default "Archivist", suggested "Otto"); it signs receipts and asks humble questions ("I think this belongs with Project Atlas — am I right?"). All user-facing strings in a localizable table; Dutch localization is planned next.

## Definition of done per screen
Matches the Journey mock at 1x on a 2560×1440 display, light mode; dark mode via system materials; Reduce Motion respected; VoiceOver labels on every control; ⌘Z undoes the last batch while the popover is open.
