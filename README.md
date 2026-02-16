# AppMD

**Markdown files as the data layer for native apps.**

AppMD is an open standard that uses markdown files with YAML frontmatter to store application data. Every piece of user data is a plain `.md` file — readable in any text editor, any markdown tool, any AI agent.

A derived SQLite index makes queries fast. The files are always the source of truth.

## How It Works

A schema file defines your data model. Data lives as `.md` files with YAML frontmatter. The GRDB-backed SQLite index is derived, disposable, and rebuildable.

```yaml
# _schema.yaml
name: Journal
version: 1

Entry:
  date: date
  mood?: happy | sad | neutral | focused | anxious
  tags?: [string]
  body: text
```

```markdown
---
type: Entry
title: Morning Hike
date: 2026-02-13
mood: happy
tags: [outdoors, exercise]
---

Hiked the coastal trail at sunrise.
```

Edit this file in any editor — VS Code, Obsidian, vim, or your app — and everything stays in sync.

## Why

- **Own your data.** Files on your machine. No cloud, no account, no server.
- **No vendor lock-in.** Plain text outlives any app, company, or platform.
- **AI-native.** Agents read and write markdown naturally. No special API needed.
- **Human-readable.** Open any data file in any text editor.
- **Interoperable.** Works with Obsidian, VS Code, vim, or anything that reads markdown.

## Quick Start

```swift
import AppMDKit

// Point at your data directory (contains _schema.yaml + .md files)
let store = try AppMDStore(rootURL: journalURL)

// Query — hits the derived SQLite index
let rows = try AppMDQuery(type: "Entry")
    .where("mood", equals: "happy")
    .sort(by: "date", descending: true)
    .limit(10)
    .fetch(from: store.database)

// Write — atomic file write + index update
let doc = AppMDDocument(
    frontmatter: ["type": "Entry", "date": "2026-03-01", "mood": "happy"],
    body: "\nToday was great.\n"
)
try store.writeDocument(doc, to: "2026-03-01.md")

// External edits (VS Code, vim, AI agents) auto-sync via FSEvents
```

The SQLite index uses WAL mode — your app, AI agents, and scripts can read and write concurrently. Indexing is automatic and transactional. Malformed files are skipped gracefully.

## Features

**Concurrent access.** WAL journal mode is enabled by default. Multiple processes safely share the index.

**Automatic batch indexing.** `rebuildIndex()` and `incrementalSync()` handle everything in single transactions. No manual batching needed.

**Graceful error handling.** Corrupted or malformed files don't crash the indexer — they're skipped and logged. Everything else indexes normally.

**Position rebalancing.** Built-in support for float-based drag-and-drop ordering:

```swift
// Detect when float positions have become too fragmented
if try store.needsRebalancing(type: "Card", filterField: "column", filterValue: "todo") {
    // Reassign clean integers (1.0, 2.0, 3.0, ...) preserving current order
    try store.rebalancePositions(type: "Card", filterField: "column", filterValue: "todo")
}
```

**SQL-safe schema names.** Table names are always quoted — types named `Order`, `Group`, `Column`, etc. work fine.

**Full-text search.** FTS5-backed search across all indexed documents:

```swift
let results = try store.search("coastal trail", type: "Entry")
```

## Implementations

| Language | Package | Status |
|----------|---------|--------|
| Swift | [`swift/`](./swift) | ✅ Production-ready |
| Python | — | Planned |
| TypeScript | — | Planned |
| Rust | — | Planned |

## Documentation

- [Specification](./docs/spec.md) — the full AppMD standard
- [Architecture](./docs/architecture.md) — how it works under the hood
- [Building Apps Guide](./docs/guide.md) — step-by-step guide to building AppMD-powered apps
- [Example Data](./docs/examples/journal/) — sample journal app data files

## License

MIT
