# AppMD

**Markdown files as the data layer for native apps.**

AppMD uses markdown files with YAML frontmatter to store application data. Every piece of user data is a plain `.md` file — readable in any text editor, any markdown tool, any AI agent.

A derived SQLite index makes queries fast. The files are always the source of truth.

## How It Works

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
date: 2026-02-13
mood: happy
tags: [outdoors, exercise]
---

Hiked the coastal trail at sunrise.
```

Edit this file in any editor — VS Code, Obsidian, vim, or your app — and everything stays in sync.

## Quick Start

### 1. Add AppMDKit to your package

```swift
dependencies: [
    .package(url: "https://github.com/nickhal/appmd.git", from: "1.0.0"),
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [
            .product(name: "AppMDKit", package: "appmd"),
        ],
        plugins: [
            .plugin(name: "AppMDPlugin", package: "appmd"),
        ]
    ),
]
```

### 2. Drop a `_schema.yaml` in your Sources directory

```yaml
name: Tasks
version: 1

Task:
  title: string
  status: todo | in-progress | done
  priority?: low | medium | high
  created: datetime
  body: text
```

### 3. Build — models are auto-generated

The build plugin reads your schema and generates typed Swift structs:

```swift
// Auto-generated — you never write this
struct Task: AppMDModel {
    static let typeName = "Task"
    let _path: String
    var _body: String
    var title: String
    var status: String
    var priority: String?
    var created: String
    // init(row:) and toDocument() generated automatically
}
```

### 4. Use in SwiftUI with `@Query`

```swift
struct TaskListView: View {
    @Query(
        filter: ("status", "todo"),
        sort: "created",
        descending: true
    ) var tasks: [Task]

    var body: some View {
        List(tasks) { task in
            Text(task.title)
        }
    }
}
```

That's it. `@Query` observes the GRDB index and auto-updates when files change on disk — from your app, an AI agent, a script, or a text editor.

## Features

### Typed Models via Build Plugin

Define your schema once in YAML. The build plugin generates:
- Swift structs conforming to `AppMDModel`
- `init(row:)` for GRDB deserialization
- `toDocument()` for round-trip safe file writes
- `Ref<T>` typed references for relationships
- Enum types for constrained fields
- Array decoding via `AppMDDecode`

Zero boilerplate. Schema is the single source of truth.

### `@Query` Property Wrapper

SwiftUI-native live queries, inspired by SwiftData:

```swift
// All entries, sorted by date
@Query(sort: "date", descending: true) var entries: [Entry]

// Filtered
@Query(filter: ("mood", "happy"), sort: "date") var happyDays: [Entry]

// Full control
@Query(query: TypedQuery<Card>()
    .where("column", equals: Ref<KColumn>.path("columns/todo"))
    .sort(by: "position")
) var todoCards: [Card]
```

Projected value gives you loading/error state:

```swift
if $entries.isLoading {
    ProgressView()
}
```

### Typed References with `Ref<T>`

Wiki-link references (`[[columns/todo]]`) become typed:

```swift
struct Card: AppMDModel {
    var column: Ref<KColumn>  // not a raw string
}

// Resolve to the actual model
let col = try card.column.resolve(in: store)

// Use in queries
let query = TypedQuery<Card>()
    .where("column", equals: Ref<KColumn>.path("columns/todo"))
```

### Manual Conformance (The Escape Hatch)

Don't want the build plugin? Conform to `AppMDModel` yourself:

```swift
struct Entry: AppMDModel {
    static let typeName = "Entry"

    let _path: String
    var _body: String
    var _source: AppMDDocument?

    var date: Date  // custom type, manual parsing
    var mood: Mood  // custom enum

    init(row: Row) {
        _path = row["_path"] as? String ?? ""
        _body = row["_body"] as? String ?? ""
        _source = nil
        date = AppMDDecode.dateOrDistantPast(from: row, column: "date")
        mood = Mood(rawValue: row["mood"] as? String ?? "") ?? .neutral
    }

    func toDocument() -> AppMDDocument {
        buildDocument(fields: [
            "date": AppMDDecode.encodeDateOnly(date),
            "mood": mood.rawValue,
        ], body: _body)
    }
}
```

The protocol IS the escape hatch. The plugin is the happy path. Both produce the same interface.

### Concurrent Access

WAL journal mode is enabled by default. Your app, AI agents, and scripts can read and write concurrently. Indexing is automatic and transactional.

### Full-Text Search

FTS5-backed search across all indexed documents:

```swift
let results = try store.search("coastal trail", type: "Entry")
```

### Position Rebalancing

Built-in support for float-based drag-and-drop ordering:

```swift
if try store.needsRebalancing(type: "Card", filterField: "column", filterValue: "todo") {
    try store.rebalancePositions(type: "Card", filterField: "column", filterValue: "todo")
}
```

### Graceful Error Handling

Corrupted or malformed files don't crash the indexer — they're skipped and logged. Everything else indexes normally.

## Schema Reference

### Field Types

| Type | Swift Type | Storage |
|------|-----------|---------|
| `string` | `String` | TEXT |
| `text` | `String` (in `_body`) | TEXT |
| `number` | `Double` | REAL |
| `date` | `String` | TEXT |
| `datetime` | `String` | TEXT |
| `boolean` | `Bool` | BOOLEAN |
| `[string]` | `[String]` | TEXT (JSON) |
| `[number]` | `[Double]` | TEXT (JSON) |
| `a \| b \| c` | `String` | TEXT |
| `-> Entity` | `Ref<Entity>` | TEXT (wiki-link) |
| `[-> Entity]` | `[Ref<Entity>]` | TEXT (JSON) |

### Optional Fields

Append `?` to the field name:

```yaml
Card:
  title: string
  due?: date        # Optional — generates String?
  labels?: [string] # Optional — generates [String]?
```

### Relationships

Use `->` for references between types:

```yaml
Card:
  column: -> KColumn    # Stored as [[columns/todo]] wiki-link
  related?: [-> Card]   # List of references
```

## Why AppMD

- **Own your data.** Files on your machine. No cloud, no account, no server.
- **No vendor lock-in.** Plain text outlives any app, company, or platform.
- **AI-native.** Agents read and write markdown naturally. No special API needed.
- **Human-readable.** Open any data file in any text editor.
- **Interoperable.** Works with Obsidian, VS Code, vim, or anything that reads markdown.

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
- [Building Apps Guide](./docs/guide.md) — step-by-step guide
- [Example: Journal](./docs/examples/journal/) — sample data files

## License

MIT
