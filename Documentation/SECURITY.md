# Tydly security and privacy architecture

Last reviewed: 23 July 2026

Tydly is a local file archivist with a deliberately narrow trust boundary. Security
properties are enforced by capabilities and deterministic policy, not by model prompts or
UI convention.

## Privacy claim

Tydly itself never transmits file names, metadata, content, embeddings, prompts, model
responses, rules, or usage data. The shipped app and every helper:

- run inside App Sandbox;
- have no network client or server entitlement;
- receive access only to folders the user selected;
- use Apple's on-device Foundation Models framework;
- contain no analytics, telemetry, crash uploader, cloud inference, remote model loader, or
  in-app updater.

This does not prevent another process from synchronizing a user-selected iCloud Drive,
Dropbox, network, or File Provider location. Tydly must identify provider-backed locations
and either reject them or explain that the existing provider may sync filesystem changes.
The product must not claim that removing a local file from Desktop can stop an already
configured sync provider.

## Threat model

| Threat | Consequence | Required defense |
|---|---|---|
| Malicious filename, symlink, alias, package, hard link, or special file | Escape an approved root or move the wrong object | Descriptor-relative traversal, no symlink following, strict file-type allowlist |
| Concurrent Finder, editor, provider, or hostile same-user process | Source or destination changes between inspection and move | Revalidate identity immediately before mutation; no-overwrite atomic rename |
| Crash, force quit, power loss, disk full, or volume removal | Filesystem and journal disagree | Durable prepare-before-mutation ledger and launch-time reconciliation |
| Malformed PDF, image, archive, model, or metadata importer | Parser compromise in the process holding write access | Bounded extraction in a read-only, networkless XPC worker |
| Prompt injection embedded in a document or filename | Model attempts to override policy or invent an action | No model tools; allowlisted identifiers; deterministic output validation and policy gate |
| Incorrect classification | Sensitive or unrelated file moves automatically | Sensitive/unknown lattice, explicit consent, calibrated abstention, persistent undo |
| Lost Mac, backup, logs, or support export | Disclosure of paths, bookmarks, vectors, or history | Minimal encrypted persistence, Keychain-held key, private/redacted logging |
| Compromised dependency or update | Arbitrary code executes with folder access | Minimal dependencies, pinned releases, Hardened Runtime, signing, notarization |

Kernel, root, firmware, and physical attacks against an unlocked Mac are outside the app's
enforceable boundary. Tydly must still avoid becoming a confused deputy for another process
running as the same user.

## Non-negotiable enforcement boundaries

1. A model may classify and rank only. It cannot enumerate arbitrary paths, move, delete,
   rename, overwrite, promote autonomy, or call tools.
2. `TydlyCore` owns consent, sensitivity, subscription, autonomy, and execution gates.
3. Sensitive, unknown, partially analyzed, unsupported, or changed files are never eligible
   for automatic filing.
4. A promoted rule is a permission ceiling, not an obligation. Operational or confidence
   checks can still require consent.
5. Every mutation has a durable `prepared` record before the filesystem is touched.
6. Neither execution nor undo may overwrite an existing item.
7. FSEvents is an invalidation signal. A callback path never directly becomes an operation.
8. Ambiguous recovery stops all new mutations and asks the user to repair.
9. Extracted text, images, prompts, and model responses are transient and never logged.
10. Resting, paused, or unavailable-AI modes retain data and cannot mutate files.

## Capability design

The main app obtains each source and destination through a user-initiated `NSOpenPanel` and
stores an app-scoped security bookmark. It must:

- reject the filesystem root, home directory, overlapping roots, recursive destinations,
  remote volumes, and unsupported provider-backed locations;
- resolve bookmarks with security scope and no path fallback;
- recreate stale bookmarks only after successfully resolving the authorized resource;
- balance every successful `startAccessingSecurityScopedResource()` call;
- stop watchers and operations before relinquishing a scope;
- request reauthorization in the popover when access is revoked.

Absolute paths and bookmark bytes are sensitive. Persistence uses root identifiers plus
encrypted relative components. Logs use only operation IDs, bounded counts, safe state names,
and numeric error codes.

## Process boundaries

```text
Tydly UI
  -> deterministic coordinator and policy
  -> capability-scoped mover and journal
  -> read-only extraction XPC service
  -> local Foundation Models classifier
```

The extraction service receives already-open read-only handles or bounded data, not folder
bookmarks. It has no network or arbitrary write entitlement. The language model receives
only bounded evidence records and allowlisted candidate IDs. The process capable of moving
files does not parse untrusted document formats or model files.

No privileged helper, system extension, dynamic plug-in host, JIT entitlement, disabled
library validation, Apple Events entitlement, Accessibility permission, or Full Disk Access
is permitted.

## Safe inventory and watching

- Create FSEvent streams only for currently authorized roots.
- Perform an initial inventory and use events only to mark roots dirty.
- Debounce and rescan after coalesced/dropped events, root changes, or event-ID wrap.
- Wait for size and modification time to stabilize before extraction.
- Skip partial downloads, lock files, packages, aliases, symlinks, mount points, provider
  placeholders, executables, and unsupported special files.
- Do not materialize a cloud placeholder merely to classify it.
- Never retain raw event paths as a second history of the user's filenames.

## Move and undo protocol

The initial engine supports ordinary same-volume files only. Cross-volume moves, packages,
directories, hard links, executable files, provider-backed items, and ambiguous files remain
unsupported or ask-first until separately designed and tested.

For each move:

1. Resolve the authorized source and destination roots.
2. Coordinate access with `NSFileCoordinator`.
3. Walk relative path components without following links and validate the source identity.
4. Validate the destination parent and prove the destination is absent.
5. Commit a durable `prepared` operation record.
6. Perform a no-overwrite, same-volume atomic rename.
7. Re-read the destination identity.
8. Commit `applied`, then publish the receipt.

SQLite and the filesystem cannot share one transaction. Recovery therefore reconciles every
nonterminal operation before watchers or new moves start:

- matching source present and destination absent: safely retry or mark aborted;
- source absent and matching destination present: finalize;
- both present, neither present, destination conflict, or identity mismatch: enter
  `needsRepair` and do not guess;
- unavailable bookmark: persist the hold event without destroying the resumable phase, then
  retry observation only after explicit reauthorization.

Undo is a new durable inverse operation linked to the original. Batch undo runs in reverse
order and records partial progress. If the original location is occupied or the destination
item changed, undo stops rather than overwriting.

## Persistence and encryption

The source-of-truth foundation is implemented in `TydlyPersistence`: SQLCipher 4.17.0 through
Zetetic's managed GRDB 7.11.1 fork, both pinned to immutable revisions. It uses one serialized
writer, foreign keys, compare-and-swap transitions, named migrations, full integrity checks,
and verified encrypted backups.

For the low-write safety ledger, prefer rollback journaling with:

```sql
PRAGMA journal_mode = DELETE;
PRAGMA synchronous = EXTRA;
PRAGMA fullfsync = ON;
PRAGMA foreign_keys = ON;
```

The schema records immutable root generations, batches, operations, typed authorization,
relative paths, expected/observed identities, exact inverse links, repair reasons, and an
append-only event sequence. It rejects root retargeting, no-op/inconsistent intent,
destination identity rewrites, and active resource conflicts.

The 256-bit database key is nonsynchronizing and never stored in defaults, the database, or
source code. Production defaults to `kSecUseDataProtectionKeychain` with
`WhenUnlockedThisDeviceOnly`. Apple requires a provisioned signing identity for that
restricted access group; an ad-hoc signature cannot reproduce it. CI therefore verifies
legacy local Keychain plumbing from the signed app, while a provisioned release must run:

```sh
Tydly.app/Contents/MacOS/Tydly --verify-data-protection-keychain
```

Backups are compact encrypted local snapshots using the same device-only key. They are not
cross-device recovery exports. Each backup is written to an obvious partial sibling, opened
and fully checked, synced, then atomically renamed and its parent directory synced.

The erase flow deletes the encryption key first, then the database, sidecars, bookmarks,
preferences, caches, and local diagnostics. It must not promise physical secure deletion on
APFS or SSD storage.

## Logging and diagnostics

- No filenames, URLs, paths, folder names, document text, OCR, prompts, responses, bookmark
  bytes, vectors, or content hashes in logs.
- Do not log complete `NSError` descriptions because they commonly contain paths.
- No third-party crash SDK. Keep bounded local MetricKit diagnostics where available.
- Support export is explicit, redacted by default, and written through `NSSavePanel`.
- Never install signal handlers that dump process memory.

## Signing and release

All assembled development apps are ad-hoc signed so local testing exercises App Sandbox,
no-network policy, embedded SQLCipher, and local Keychain plumbing. Ad-hoc signatures cannot
claim Apple's provisioned Data Protection Keychain group. Release builds use a stable
provisioned Developer ID or App Store identity, App ID prefix, Hardened Runtime, secure
timestamps, notarization, and stapling.

Release checks inspect every bundled executable:

```sh
codesign -d --entitlements :- Tydly.app
codesign --verify --deep --strict --verbose=4 Tydly.app
syspolicy_check distribution Tydly.app
xcrun stapler validate Tydly.app
```

The direct-distribution update path is manual download of a signed, notarized release. The
App Store is preferred because the store performs updates without granting Tydly networking.
Do not embed Sparkle or another network-enabled updater.

## Verification gates

- Crash injection after every journal transition.
- Symlink substitution, `..`, Unicode normalization, case collision, hard-link, alias,
  package, FIFO, and mount-point fixtures.
- Concurrent rename/edit/provider materialization.
- Destination races and zero-overwrite assertions.
- Stale/revoked bookmarks, disk full, I/O error, sleep, logout, and volume ejection.
- FSEvent drops and event storms.
- Undo conflicts and interrupted batch undo.
- Adversarial visible and hidden prompt injection.
- No sensitive/unknown automatic-execution attempt.
- No raw content in persistence or logs.
- Negative socket tests for the app and every helper.
- Signed entitlement audit in CI.

## Primary references

- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Diagnosing App Sandbox violations](https://developer.apple.com/documentation/security/discovering-and-diagnosing-app-sandbox-violations)
- [Security-scoped resource access](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource())
- [FSEvents Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/Introduction/Introduction.html)
- [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- [FileManager move semantics](https://developer.apple.com/documentation/foundation/filemanager/moveitem(at:to:))
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [CryptoKit AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Keychain data protection](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)
- [Privacy-preserving logging](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code)
- [SQLite atomic commit](https://sqlite.org/atomiccommit.html)
- [SQLite durability pragmas](https://sqlite.org/pragma.html)
