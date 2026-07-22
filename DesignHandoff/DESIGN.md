# DESIGN.md — Tydly (macOS menubar archivist)

Design language: **native macOS, indistinguishable from system UI.** shadcn component anatomy, Apple skin. When in doubt, do what the Wi-Fi menu does.

## Color
| Token | Value | Use |
|---|---|---|
| primary | #007AFF (system blue) | primary buttons, selection, links, working state |
| success | #34C759 | tidy dot, done badges, confidence-high bar |
| warning | #FF9F0A | needs-you badges/dots, demotion, confidence-low bar |
| danger | #FF3B30 | broken/error only — never for "busy" |
| text | #1d1d1f | primary text |
| textSecondary | rgba(60,60,67,.6) | subtitles, metadata (use .75 on small sizes for AA) |
| separator | rgba(0,0,0,.1) at .5px | menu + list separators |
| Project avatar palette | #3478f6, #2f9e8f, #8e6bd0, #c77d4a | deterministic per project |

Color semantics are exclusive: green=tidy, blue=working, amber=waiting-on-user, grey=paused, red=broken.

SwiftUI: use semantic system colors where they exist (`.tint`, `Color.accentColor`, `.secondary`); the values above are their light-mode equivalents. Dark mode: derive from system materials, do not hand-pick.

## Materials
| Surface | Spec | Native equivalent |
|---|---|---|
| Menu/popover | rgba(246,246,248,.9) + blur(30) saturate(1.6), radius 11, shadow 0 10 34 rgba(0,0,0,.18) + .5px ring rgba(0,0,0,.12) | NSVisualEffectView `.menu` / `MenuBarExtra` default |
| Card inside menu | rgba(255,255,255,.75), radius 9, .5px ring 7% | grouped inset |
| Window | rgba(246,246,248,.97), radius 12 | standard NSWindow |
| Whisper bar | rgba(28,28,30,.88) + blur(20), radius 999 | NSPanel, nonactivating, `.hudWindow`-like |
| Onboarding card | glass, radius 14, shadow 0 14 44 rgba(0,0,0,.18) | NSVisualEffectView `.popover` |

Hairline ring + soft shadow together is intentional (it is the literal macOS menu material).

## Typography — SF only
| Style | Size/Weight | Use |
|---|---|---|
| Menu title | 13/600 | popover headers ("Otto", state lines) |
| Menu row | 13/400 | menu items |
| Card title | 12.5/600 | decision titles, rule names |
| Body small | 12/400 | supporting copy in cards |
| Meta | 11/400 · secondary | timestamps, hints, footers |
| Section label | 11/600 · secondary | "Today", "Needs you" |
| Stat number | 20/700 | werkbriefje grid |
| Onboarding title | 15/600 | step titles |
| Shortcut hints | SF Mono equivalents (⌘, ⌘Z ⌘K) | trailing menu hints |

## Radii
menu 11 · window 12 · card 9 · onboarding card 14 · buttons 7 (small 6) · badges/chips/pills 999. Nothing above 16 except pills.

## Components (shadcn anatomy → native)
- **Button**: primary filled #007AFF (26pt, radius 7; small 22pt radius 6); secondary rgba(120,120,128,.14); outline white + .5px ring; link/ghost plain blue; destructive rgba(255,59,48,.1) fill + #d70015 text. macOS dialog buttons: 24pt, radius 6, min-width 84, primary = blue gradient (#2f8bff→#007AFF), right-aligned, primary rightmost.
- **Badge**: 17pt pill, 10/600. Variants: default grey, ok green, warn amber, outline (ring only).
- **Folder chip** (key pattern): folder SF Symbol + name in grey pill (radius 5, 10.5/500). Every log row = `✓ Filed <n> <kind> [folder chip] ↩` — verb + count + destination, never "3 → Atlas".
- **Confidence bar**: 50×4 radius 2, track 16% grey; fill green ≥85%, amber below. Never show percentages as text.
- **Progress ring**: 32pt, 3pt stroke, #007AFF on 8% track, count centered 8.5/700 (goal-gradient for rule promotion).
- **Toggle**: standard macOS switch (32×19).
- **Segmented tabs**: rgba(120,120,128,.13) track radius 8, white selected segment with shadow, 11/600.
- **Avatar**: circle, project color, white initial 10/600; stacks overlap −7pt.
- **Otto cursor**: blue pointer triangle + "Otto" pill tag (10/600 white on #007AFF) — only in Finder preview mode.
- **Ghost file**: 1.5px dashed #007AFF border, rgba(0,122,255,.08) fill — the "not yet real" state.

## SF Symbols mapping
lock → `lock` · clock/parked → `clock` · folder chip → `folder` · Desktop → `display` (or `menubar.dock.rectangle`) · Downloads → `arrow.down.circle` · never/off-limits → `nosign` · settings → `gearshape` · undo → `arrow.uturn.backward` · done → `checkmark` · cancel → `xmark` · menubar glyph → custom template image (archive box, 15×12, 1.5px stroke).
All icons stroke-style, 1.5px weight equivalent (SF regular). **No emoji anywhere.**

## Motion
- Only transform/opacity. Ease-out (quart/quint). No bounce/elastic.
- Icon badge pulse: 1.6s soft ring, only while analyzing.
- Whisper bar: in 200ms slide-up+fade, out 300ms fade after 4s.
- Ghost→real: blue ring fades ~1s on approval.
- Respect Reduce Motion: state swaps become instant.

## Voice (copy rules — enforced)
1. Numbers beat sentences ("86" + label, never "You filed 86 files").
2. Reasons on demand — every "why" behind a tap.
3. One full sentence max per surface; the reassurance line is the only sentence allowed ("Nothing moves without you").
4. Otto speaks in receipts: verb + count + destination ("Filed 12 → Atlas"). Personality lives in questions, not status.
5. Humble, never celebratory. Errors are Otto's fault; recovery is one tap.
6. English now; all strings localizable (Dutch planned).
