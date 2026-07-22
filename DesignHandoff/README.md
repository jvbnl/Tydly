# Handoff: Tydly — Personal Mac Archivist (menubar app)

## Overview
Tydly is a local, trust-earning file archivist that lives in the macOS menu bar. Its agent persona (user-named, default suggestion "Otto") does the talking; "Otto" in the mocks marks wherever the chosen agent name renders. It watches user-approved folders (Desktop, Downloads), groups clutter by *project* (not file type), proposes moves, demonstrates them in Finder before acting, and earns per-category autonomy over time. Every move is undoable; nothing leaves the Mac.

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes showing intended look and behavior, NOT production code. The task is to **recreate these designs as a native macOS app** (Swift/SwiftUI + AppKit where needed: `NSStatusItem`, `MenuBarExtra`, `NSPopover`/`NSMenu`, `NSPanel` for the whisper bar). If a different stack is already chosen (e.g. Electron/Tauri), match the native look exactly; the design is deliberately indistinguishable from system UI.

- `Archivaris Journey.dc.html` — **the source of truth.** Seven phases, every screen in final locked style.
- `Archivaris Wireframes.dc.html` — the exploration archive (Rounds 1–8). Reference only; useful for rationale and rejected directions.

Open both directly in a browser. Ignore the outer canvas chrome (phase headers, captions); the mocks inside are the spec.

## Fidelity
**High-fidelity.** Colors, type, spacing, radii, materials, and copy in `Archivaris Journey.dc.html` are final. Recreate pixel-perfectly with system equivalents (see DESIGN.md for the token→SwiftUI/AppKit mapping). The wireframes file is low-fidelity and must not be used for visual specs.

## Screens / Views

### Phase 01 — Onboarding (3 steps)
One floating card per step (250×196pt min, glass material, radius 14), Apple page-control stepper on top (active dot = 16×6 pill, #007AFF; inactive 6×6, 15% black).
1. **Privacy**: green lock icon in 40×40 rounded-12 tile (`rgba(52,199,89,.14)` bg, icon #1d7a3a); title "Nothing leaves this Mac" (15/600, centered); sub "No account. No cloud. No exceptions." (11.5, 65% secondary); primary button "Continue" pinned bottom.
2. **Folder scope**: title "Where may I work?"; two white rows (radius 9, hairline ring) "Desktop" / "Downloads" with SF Symbols `display` / `arrow.down.circle` and a blue ✓; sub "The rest of your Mac stays off-limits."; button "Allow these 2 folders" (copy = exact scope, do not change).
3. **Naming**: title "Your archivist needs a name"; name chips (Otto selected = filled #007AFF pill; Ada, Juno, custom "own…" dashed); 4 color swatches (20pt circles: #3478f6 selected with ring, #2f9e8f, #8e6bd0, #c77d4a); preview row "Signs his work as [Otto]" (blue cursor-tag pill); buttons "Meet Otto" primary + "Skip" secondary. Skipping defaults the name to "Archivist".

### Phase 02 — First clean
1. **Observing**: menubar icon (archive-box glyph) with pulsing blue badge dot; popover line "Reading, changing nothing" + "Desktop & Downloads · a few minutes".
2. **Plan window** (470pt): standard titlebar "Otto's plan · 29 files"; left sidebar (150pt, 3% black bg) lists groups (Screenshots 12 — selected blue row, Invoices 5, Decks 8, Not sure yet 4 at 60%); right pane: group title, destination folder chip "Atlas › Screens", green confidence bar (92%), "why?" link, 3 file thumbnails + "+ 9 more"; footer: "Nothing moves until you approve" + "Skip group" secondary + "Show me in Finder" primary.
3. **Finder demonstration** (full-screen mode): top dark pill "Preview: nothing has moved yet · esc"; Desktop icons: files leaving are at 40% opacity; a ghost file (dashed #007AFF outline, 8% blue fill) travels along a dashed path carried by the **Otto cursor** (blue pointer + "Otto" tag pill — Figma-collaborator pattern); destination Finder window shows ghost files in place; bottom confirmation card (320pt glass, radius 12): title "Move 12 screenshots to "Screens"?", sub "In Atlas. You can undo this at any time.", buttons right-aligned macOS-style: "Not Quite…" (white push button) + "Looks Right" (blue gradient default button, 24pt tall, radius 6, min-width 84).
4. **Receipt + maintenance ask**: menu popover: green dot "29 files filed" + "Undo all" link; below: "Shall I keep it this way? 30 days free, every move undoable." + "Yes, quietly" primary / "Not yet" secondary.

### Phase 03 — Daily rhythm
**Menubar icon states** (never animate when idle):
- quiet: plain glyph
- working: blue badge dot, 1.6s pulse
- needs you: amber count badge (#FF9F0A, 13pt round, white 8.5/700)
- paused: 40% opacity
- broken: red badge dot (#FF3B30)

**Popover = native menu** (290pt, radius 11, menu material): header row "Otto" + status text + master toggle; separators are .5px 10% black inset 10pt. States:
- **All tidy**: Today section, rows "✓ Filed 3 screenshots [folder chip: Atlas] ↩" — log rows are always verb + count + folder chip + undo glyph. Footer "Settings… ⌘,".
- **Decision waiting**: amber badge "1 decision" in header; decision card (white 75% overlay, radius 9): avatar (22pt circle, project color), title "12 screenshots → Atlas › Screens" (12.5/600), confidence bar (50×4, green fill at 92%) + "why?" link (reason expands on click); buttons "Show me" primary (fills width) + "Skip" outline. Below: clock row "4 parked · asks again Fri ›". Footer: "Nothing moves without you".
- **Working**: pulsing blue dot + "Sorting 3 in Downloads"; live file list card (current file "reading…", others queued at 55%); footer "Next sweep when your Mac is idle".

### Phase 04 — Whisper bar (transient HUD)
Dark pill (`rgba(28,28,30,.88)` + blur, radius 999, white text, padding 7/14) bottom-center above the Dock. One at a time, auto-dismiss 4s, click opens popover, **never asks questions**. Off during screen sharing/presentation. Three variants:
1. **Working**: 22pt ✕ cancel circle (18% white) + 6 progress dots (3pt; done = white, pending = 35% white) + "3 of 6" (11pt, 70%).
2. **Receipt**: "Filed 3 screenshots" (12.5/600) + folder chip (14% white bg) + "Undo" pill button (24pt tall, 16% white bg).
3. **FYI**: "Screenshots now file themselves" (85% white) + "Change" pill button.

### Phase 05 — When it goes wrong (all in popover)
1. **Undo done**: "↩ 12 back on Desktop" + green "done" badge; follow-up row "Stop filing screenshots?" + "Yes" / "Just this once" links. One question, then silence.
2. **Silent correction**: Otto avatar + "Noticed — you moved it back"; "invoice_q3 stays in Downloads. Rule updated."; amber confidence bar at 58% + "confidence ↓".
3. **Self-demotion**: amber dot + "I got 2 wrong this week"; "Screenshots: back to asking first."; badge "auto → asks" + "See the 2" link.
4. **Broken destination**: red dot + "Atlas folder is gone"; "Renamed or deleted. 3 moves on hold."; "Show me where" outline button + "Forget Atlas" link. Work is held, never dropped.

### Phase 06 — Growing trust
1. **Rule offer**: header "Make it a rule?" + badge "12 accepts in a row"; card with full progress ring (32pt, 3pt stroke #007AFF, "12/12" center) + "Screenshots → Atlas" + "I'd handle these myself"; buttons "Make it a rule" primary / "Keep asking" secondary. Autonomy is offered, never taken.
2. **Rules pane** (settings window, Rules tab): rows per rule: name + stats ("41 filed · 0 undone") + trailing state: blue "auto" badge, progress bar ("8 more accepts"), or amber "always asks" with lock icon for Sensitive files (this row can never become auto — hard product rule).
3. **Weekly note (werkbriefje)**: popover: Otto avatar + "Your week, from Otto" + date range; 2×2 stat grid (20/700 numbers: 86 files filed, 7 projects tended, 6/7 days Desktop clear, ≈47m saved · estimate); card "4 files set aside for you" + "Review" link.
4. **Trial end**: "30 days with Otto" + 2 stats (312 filed, ≈3h saved) + "Keep Otto · €3/mo" primary + "Not now" link. **Declined state**: grey dot "Otto is resting" + "Still watching, no longer filing. Rules and undo history are safe." + "Wake him up" secondary. Nothing is deleted on decline.

### Phase 07 — Settings (General tab)
Standard settings window (420pt): sidebar (110pt: General/Folders/Rules/History), grouped rows with .5px separators: "Tend quietly — Only sweep when the Mac is idle" (toggle on), "Weekly note — Friday, 16:00" (toggle on), "Sounds" (toggle off), "Pause Otto — Until 5 pm · tomorrow · manually" (Pause… button), "Everything Otto knows — Rules, examples, history. All on this Mac" (**Erase** destructive button, visible, not buried).

## Interactions & Behavior
- Menubar icon click → popover (native menu behavior, dismiss on outside click / Esc).
- "Show me" → Finder demonstration mode; Esc always exits with zero changes; "Looks Right" executes; ghosts become real with a brief blue ring fading over ~1s.
- "why?" → expands one reason line inline (e.g. `Filenames match "atlas-*", saved while you worked on Atlas`).
- Undo (↩/Undo all) is instant and always available per action and per batch; undo history persists across sessions.
- Skip twice → item parks silently (visible in "parked" row, re-asks Friday, then stops asking).
- User manually moves a filed file back in Finder → Otto detects, lowers rule confidence, shows one "Noticed" message, never repeats.
- Auto-rule makes ≥2 mistakes in a week → self-demotes to asking; shows "I got 2 wrong" once.
- Whisper bar: fade/slide up 200ms ease-out on show, fade 300ms on dismiss after 4s; no bounce/elastic easing anywhere.
- Icon pulse animation: 1.6s infinite soft ring, only while actively analyzing.
- All motion: transform/opacity only, ease-out; respect Reduce Motion (disable pulse + ghost travel, keep state changes instant).

## State Management
- `agentState`: observing | working | idle-tidy | needs-decision(count) | paused(until) | error(kind)
- `autonomyLevel` per rule/category: observe → propose → trusted-rule → auto; sensitive category is permanently capped at propose.
- `ruleConfidence` (0–1) per rule; accepts increment toward promotion threshold (12), undo/corrections decrement; 2 mistakes/week → demote.
- `decisions[]` (pending groups), `parked[]` (with re-ask date), `actionLog[]` (timestamped, undoable), `weeklyStats`.
- Subscription: trial(daysLeft) | active | resting. Resting = watch-only, all data retained.

## Design Tokens
See DESIGN.md — single source for colors, type, materials, radii, shadows, spacing, SF Symbols mapping.

## Assets
No bitmap assets. All icons are SF Symbols (mapping in DESIGN.md). The menubar glyph is a custom template image: rounded-rect archive box with a lid line (see `.g`/`.hg` in the HTML, 15×12 @1.5px stroke) — export as template PDF so macOS tints it.

## Files
- `Archivaris Journey.dc.html` — hi-fi source of truth (phases 01–07)
- `Archivaris Wireframes.dc.html` — exploration archive (rationale, rejected variants)
- `DESIGN.md` — tokens + component specs
- `CLAUDE.md` — implementation briefing for Claude Code
