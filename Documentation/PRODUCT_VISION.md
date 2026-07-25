# Tydly product vision

Last reviewed: 25 July 2026

This is the product-level source of truth. `DesignHandoff/` remains the visual and screen
source of truth; `Documentation/SECURITY.md` and `Documentation/AI_ENGINE.md` remain the
security and inference sources of truth. Where this document and an older one disagree about
*what Tydly is*, this document wins.

## Otto is the product

Tydly is not a file utility with an AI feature bolted on. It is an **agent-native, private
local archivist**. The user does not experience a classifier, a rules engine, or a sync
daemon — they experience Otto, a named colleague who watches two folders, notices what
belongs together, asks before touching anything, and can always be undone.

Three consequences follow, and they are binding:

1. **Otto orchestrates every user-visible workflow.** There is no path through the product
   where files are grouped, proposed, demonstrated, moved, or undone outside the agent loop.
   A future settings toggle does not get its own private mover.
2. **Local AI is required for novel understanding.** Recognising that four unrelated-looking
   files belong to one project is the product. That reasoning happens on-device or it does
   not happen.
3. **The model is not the security boundary.** `TydlyCore` owns consent, sensitivity,
   autonomy, execution authorization, and resting behaviour. Otto can be wrong without being
   dangerous.

## What "magic" means here

The felt quality we are building is *being understood without being surveilled*. It
decomposes into six capabilities, in the order the user notices them:

- **Project understanding** — grouping by what a file is *for*, not by its extension. A
  screenshot, a PDF invoice, and a Keynote deck can belong to one project; two screenshots
  can belong to different ones.
- **Local memory** — Otto remembers the projects you have, the destinations you authorized,
  the examples you accepted, and the corrections you made. Memory is encrypted, data-minimized,
  and never leaves the Mac.
- **Evidence** — every proposal can answer "why?" with a real reason drawn from typed facts,
  not a generated justification. A reason the user cannot verify is worse than no reason.
- **Demonstration** — Otto shows the exact move before it happens. What is displayed is what
  executes, bound by one immutable digest.
- **Abstention** — Otto says "not sure yet" and parks the file. An archivist who guesses is
  not trustworthy, and a wrong move costs far more trust than a missing one gains.
- **Learning** — corrections change future behaviour visibly and immediately, and lower
  confidence rather than silently retrying.

## The agent loop

```text
perceive → remember → reason → plan → demonstrate → act → learn
```

| Stage | Owner | Boundary |
|---|---|---|
| perceive | scoped inventory + isolated read-only extraction | no content parsing in the main app; raw text never persisted |
| remember | encrypted agent memory | opaque IDs and typed facts only; no source text, no transcripts |
| reason | deterministic retrieval, then the local model | model sees bounded path-free evidence and an allowlist |
| plan | `TydlyAgent` | plans carry no absolute paths and no execution authorization |
| demonstrate | Finder demonstration | displayed state and executed state share one digest |
| act | ledger, then the race-safe mover | journal `prepared` before any mutation |
| learn | agent memory | outcome recorded against prediction, model, and extractor revision |

`TydlyAgent` orchestrates read-only evidence and memory. **It never moves a file itself** and
never issues an execution capability; it hands an immutable plan to the demonstration, and the
user's explicit approval is what authorizes execution.

## When the model is unavailable

Apple Intelligence can be switched off, the system model can be unprepared, and the device or
locale can be ineligible. In every one of those states:

- Otto becomes **watch-only**. The icon reflects a calm, non-broken state.
- No new semantic proposal is produced and no move is executed.
- **There is no cloud fallback.** Not Private Cloud Compute, not a bundled model, not a
  downloaded model, not a local inference server.
- Nothing already learned is deleted, and undo history stays fully available.

Watch-only is also the correct posture when the user has paused Otto, when the subscription is
`resting` (Rule 9), when a folder capability needs reauthorization, and when the ledger holds
an unresolved repair. These are different reasons for the same restraint, and the product
should be able to say which one is in effect.

## The working alpha

The first build a human can genuinely test is entirely **ask-first**. Automatic filing is not
enabled, no matter how confident Otto is.

1. Authorize Desktop and Downloads through the real Powerbox flow.
2. Drop a mixed project fixture into both folders.
3. Otto performs a real local scan and groups real files.
4. The proposed project maps to a user-selected local destination.
5. The Finder demonstration shows the exact plan.
6. Approving one group moves exactly those files and nothing else.
7. One file is undone; then the remaining batch is undone.
8. Force-quitting at any ledger or mover boundary recovers cleanly on relaunch.
9. Disabling Apple Intelligence produces watch-only behaviour with no new decisions.

## Product-quality metrics

Measured locally, shown to the user only as the weekly note — never uploaded.

| Metric | Target | Why |
|---|---|---|
| Wrong-move rate | ≈ 0 per week | one bad move costs more trust than ten good ones earn |
| Abstention honesty | a parked file is genuinely ambiguous | abstention must not become a dumping ground |
| Reason verifiability | every "why?" traces to a typed fact | an unverifiable reason is a liability |
| Undo success | 100 %, including across restart | Rule 3 is absolute |
| Time to first useful proposal | minutes, not days | trust starts at first contact |
| Watch-only clarity | the user can tell *why* Otto is quiet | silence without explanation reads as broken |

## What this vision forbids

- Any outbound network capability, telemetry, crash uploader, or model hub.
- Any cloud or remote inference, including Private Cloud Compute.
- Auto-filing sensitive files, ever (Rule 2).
- Moving anything the user has not consented to, until they explicitly promote a rule (Rule 1).
- Taking autonomy rather than being offered it (Rule 4).
- Deleting anything on decline, paywall, or resting (Rule 9).
- Notification frameworks of any kind (Rule 7).

## Related documents

- `DesignHandoff/README.md` — screens, interactions, state machine.
- `DesignHandoff/DESIGN.md` — tokens, components, voice.
- `Documentation/SECURITY.md` — threat model, capabilities, move/undo protocol, release gates.
- `Documentation/AI_ENGINE.md` — inference boundary and prompt contract.
- `CODEX_HANDOFF.md` — the working-alpha implementation sequence.
