# AppMD Architecture

**The mental model, the build plan, and why concurrency isn't scary.**

---

## The Core Pattern

AppMD follows one pattern: **files are truth, everything else is derived.**

This is the same pattern as embeddings for memory search:
- Memory files = source of truth
- Embedding index = derived, rebuildable, disposable
- `memory_search` = queries the index, not the files

AppMD:
- Markdown files = source of truth
- SQLite/GRDB index = derived, rebuildable, disposable
- App queries = hit the index, not the files

Delete the index, rebuild from files, zero data loss. The index is Spotlight for your app data.

---

## The Layers

**SQLite** — a database in a single file. Every iOS app uses it under the hood. Not a server. Just a `.sqlite` file.

**GRDB** — a Swift library that gives you a type-safe API over SQLite. Instead of raw SQL strings, you write Swift code. Compiler catches mistakes. Autocomplete works.

**How they fit:** You can't efficiently query 500 markdown files to find "all entries where mood is happy, sorted by date." You'd open every file, parse YAML, check fields, collect matches, sort. Slow. Instead: scan files once, dump every field into GRDB/SQLite, query the index. Milliseconds.

---

## Three Index Layers

Each answers a different question. Zero redundancy.

**SQLite/GRDB** — "show me transactions over $50 this month sorted by date"
Structured queries. Filtering, sorting, aggregation. Essential. This is how the app finds data fast.

**Git** — "what did this file look like 3 weeks ago"
Version history. Basically free. `git init`, auto-commit on saves. Undo anything forever.

**Embeddings** — "find journal entries about feeling burned out"
Fuzzy semantic search. Doesn't need exact word matches.

**v1:** SQLite + Git.
**v2:** Add embeddings when it earns its spot.

---

## What You Actually Build

Not a database engine. Not a coordination layer. Three things:

**1. Atomic file I/O**
Write to `.tmp` file, rename over original. Rename is atomic on APFS. File is never half-written. Corruption is impossible.

**2. FSEvents watcher**
macOS file system event stream. Watches app directories. Fires when any file changes — whether the app wrote it, an agent wrote it, or the user edited it in Obsidian. On change: re-parse that file, update its row in GRDB.

**3. GRDB index sync**
On launch: scan all `.md` files, parse frontmatter, populate GRDB. Runtime: FSEvents triggers incremental re-index of changed files. GRDB's reactive bindings (`ValueObservation`) push updates to SwiftUI automatically.

That's the entire engine. Everything else is app logic.

---

## The Read/Write Flow

**App reads:**
1. Launch → scan all `.md` files → parse frontmatter → populate GRDB
2. Runtime → all queries hit GRDB (fast, milliseconds)
3. FSEvents fires → re-parse changed file → update GRDB → SwiftUI auto-refreshes

**App writes:**
1. User saves (or autosave fires)
2. Serialize to YAML frontmatter + markdown body
3. Write to `.tmp`, rename over original (atomic)
4. Update GRDB row
5. Note the file hash so FSEvents ignores the bounce-back

**Agent reads:**
`cat ~/AppMD/Journal/2026-02-13.md`. Done.

**Agent writes:**
Same atomic pattern. Write tmp, rename. Agent doesn't know GRDB exists. Doesn't need to.

**The glue:**
Agent writes file → FSEvents detects → app re-parses → GRDB updates → UI refreshes. No middleware. The filesystem is the integration layer.

---

## Concurrency: Resolved

The deep think doc painted concurrency as a terrifying engineering challenge. It's not. For personal apps — one user, one machine — every concern has a simple answer.

**1. "User typing, agent modifies same file, unsaved words lost"**
App has unsaved edits → ignore external changes to that file. User's version saves on next autosave. Agent can redo its work later. **User always wins.**

**2. "Which merge strategy?"**
None. User's in-memory state wins. No merge logic.

**3. "File-level locking blocks agents"**
No locking. Agent writes freely, app writes freely. Atomic writes prevent corruption.

**4. "Two things append to same collection file simultaneously"**
Atomic writes prevent corruption. Race condition requires two processes writing at the exact same millisecond. For one person on one laptop, this doesn't happen.

**5. "File concurrency can't match SQLite's ACID"**
True. Don't need it. ACID is for multi-user databases, not personal journal apps.

**6. "FSEvents fires back at us after our own write"**
Track hashes of files we wrote. FSEvents fires → hash matches our write → ignore.

**7. "Crash recovery needs a WAL"**
Debounced autosave. User loses at most a few seconds of typing on crash. Good enough.

**8. "Agent needs to know file changed before writing"**
Agent checks file modification time before writing. If changed since last read, re-read first. Standard agent behavior (Claude Code already does this). Not our problem to build.

**No coordination engine. No locking. No merge logic. Atomic writes + FSEvents + "user wins" = done.**

---

## The Overengineering Trap

The deep think doc was valuable as a stress test but wrong as a build plan. It imagined every edge case and designed for all of them simultaneously. That's how you turn a 4-week build into a 6-month project that never ships.

The move: ship the simple version. Let actual usage tell you what needs fixing. If concurrent editing becomes a real problem (it probably won't), build the merge layer then. Not before.

Thorough research → simple decisions. Not thorough research → complex architecture.
