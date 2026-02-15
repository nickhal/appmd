# AppMD

**Markdown files as the data layer for native apps.**

AppMD is an open standard that uses markdown files with YAML frontmatter to store application data. Every piece of user data is a plain `.md` file — readable in any text editor, any markdown tool, any AI agent.

## How It Works

A schema file defines your data model. Data lives as `.md` files with YAML frontmatter. A derived SQLite index makes queries fast. The files are always the source of truth.

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

## Implementations

| Language | Package | Status |
|----------|---------|--------|
| Swift | [`swift/`](./swift) | ✅ Available |
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
