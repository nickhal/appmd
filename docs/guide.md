# The AppMD Guide

**The definitive, self-contained reference for building apps with AppMD.**

*Last updated: 2025-07-28 · AppMD Spec v1.0 · AppMDKit (Swift) · Battle-tested*

---

## 1. What is AppMD

AppMD (Application Markdown) is an open standard and Swift framework that uses **markdown files with YAML frontmatter** as the data layer for native macOS applications. Every piece of user data is a plain `.md` file that any text editor, AI agent, or markdown tool can read. Structured metadata lives in YAML frontmatter; long-form content lives in the markdown body. A schema file (`_schema.yaml`) defines types and fields. A derived SQLite index (via GRDB) makes queries fast, but the files are always the source of truth — delete the index and it rebuilds from files. The result: apps where user data is portable, human-readable, agent-accessible, and permanent.

---

## 2. The Standard

### 2.1 File Format

Every AppMD data file is a valid markdown file with optional YAML frontmatter:

```markdown
---
type: Entry
date: 2026-02-13
mood: focused
tags: [work, design]
---

The body is standard markdown. Write anything here.

Use **bold**, *italic*, [links](https://example.com), and
[[wiki links]] to other entities. It's just markdown.
```

**Rules:**
- Frontmatter is delimited by `---` on its own line (opening and closing)
- Frontmatter is valid YAML
- Every document **must** have a `type` field in frontmatter that matches a type in `_schema.yaml`
- The markdown body (everything below the closing `---`) maps to the `text` field type in the schema
- Files without valid frontmatter delimiters are treated as pure markdown (no metadata)
- File encoding is UTF-8

### 2.2 Two Data Shapes

**Documents** — primarily narrative. One file per document. YAML frontmatter for structured metadata, markdown body for content. Journal entries, notes, essays.

```markdown
---
type: Entry
date: 2026-02-13
mood: focused
tags: [work, design]
---

Spent the morning designing AppMD...
```

**Records** — primarily structured. Can be individual files (one entity per file) or collection files (many records as a markdown table in one file).

Individual record file (`Contacts/alex-chen.md`):
```markdown
---
type: Contact
name: Alex Chen
email: alex@example.com
company: Acme Corp
---

Met Alex at a conference in KL.
```

Collection file (`Budget/transactions/2026-02.md`):
```markdown
---
type: TransactionLog
month: 2026-02
---

| date | amount | category | merchant | note |
|------|--------|----------|----------|------|
| 2026-02-13 | -4.50 | food | Feeka Coffee | Coffee with Alex |
| 2026-02-12 | -89.00 | groceries | Jaya Grocer | Weekly shop |
```

### 2.3 Schema Definition (`_schema.yaml`)

Every app has a `_schema.yaml` in its root directory:

```yaml
name: Journal
version: 1

Entry:
  date: date
  mood?: happy | sad | neutral | focused | anxious | grateful
  tags?: [string]
  body: text
```

**Structure:**
- `name` — app name (string)
- `version` — schema version (integer)
- Type definitions — capitalized names (e.g., `Entry`, `Transaction`) with field declarations

**Base Types:**

| Type | Description | YAML Example | SQLite Column |
|------|-------------|-------------|---------------|
| `string` | Short text | `"Feeka Coffee"` | TEXT |
| `text` | Long markdown (maps to file body) | *(the markdown body)* | TEXT |
| `number` | Integer or decimal | `42`, `-4.50` | REAL |
| `date` | ISO 8601 date | `2026-02-13` | TEXT |
| `datetime` | ISO 8601 datetime | `2026-02-13T09:30:00` | TEXT |
| `boolean` | True or false | `true`, `false` | BOOLEAN |

**Compound Types:**

| Syntax | Meaning | Example |
|--------|---------|---------|
| `[type]` | List of a type | `[string]` → `[coffee, social]` |
| `val1 \| val2 \| val3` | Enum (one of listed values) | `food \| transport \| groceries` |
| `-> EntityName` | Relationship (wiki link) | `-> Account` |
| `[-> EntityName]` | List of relationships | `[-> Contact]` |
| `ref` (with `to:`) | Typed reference to another document type | `type: ref`, `to: Category` |
| `object` (with `fields:`) | Nested object (one level deep) | `type: object`, `fields: {street: string}` |

**Modifiers:**

| Syntax | Meaning | Example |
|--------|---------|---------|
| `?` suffix on field name | Optional field | `merchant?: string` |
| `= value` | Default value | `currency: string = MYR` |

**Full example:**

```yaml
name: Budget
version: 1

Transaction:
  date: date
  amount: number
  category: food | transport | groceries | entertainment | utilities
  merchant?: string
  note?: text
  account: -> Account
  tags?: [string]

Account:
  name: string
  type: checking | savings | credit | cash
  currency: string = MYR
  institution?: string
```

### 2.4 Relationships

Entities reference each other through **wiki links** (`[[path/to/entity]]`):

```yaml
---
type: Transaction
date: 2026-02-13
amount: -4.50
account: [[accounts/cash]]
---
```

- Within an app: paths are relative to the app root. `[[accounts/cash]]` → `Budget/accounts/cash.md`
- Across apps: paths are relative to the AppMD root. `[[Contacts/alex-chen]]` → `~/AppMD/Contacts/alex-chen.md`

### 2.5 Directory Conventions

```
~/AppMD/
├── _appmd.yaml                # Root manifest (lists all apps)
├── Journal/
│   ├── _schema.yaml           # Journal types
│   ├── 2026-02-13.md          # Individual documents
│   └── 2026-02-12.md
├── Budget/
│   ├── _schema.yaml           # Budget types
│   ├── accounts/
│   │   └── cash.md
│   └── transactions/
│       └── 2026-02.md         # Collection file (table)
└── Contacts/
    ├── _schema.yaml
    └── alex-chen.md
```

- One folder per app
- `_` prefix for meta files (`_schema.yaml`, `_appmd.yaml`)
- Subfolders for entity types
- File naming is free-form: dates for journals, slugs for entities
- Derived caches live in `.cache/` (hidden, always deletable)

### 2.6 Body Content

The `text` field type in a schema maps to the markdown body of the file — everything below the frontmatter `---` delimiter. A schema typically declares one `text` field per document type:

```yaml
Entry:
  date: date
  mood?: string
  body: text    # ← this IS the markdown body
```

The field name (`body`) is conventional; what matters is the `text` type. When the file is parsed, the markdown body is stored in the `_body` column of the GRDB index.

---

## 3. Architecture

### 3.1 The Core Pattern

```
Markdown Files  →  SQLite/GRDB Index  →  App Queries / SwiftUI
  (source of truth)    (derived, disposable)    (reactive UI)
```

Files are truth. The SQLite index is Spotlight for your app data — derived, rebuildable, disposable. Delete the index and rebuild from files with zero data loss.

### 3.2 The Three Layers You Build

**1. Atomic File I/O** — Write to `.tmp` file, rename over original. Rename is atomic on APFS. File is never half-written. Corruption is impossible.

**2. FSEvents Watcher** — macOS file system event stream. Watches app directories. Fires when any file changes — whether the app wrote it, an agent wrote it, or the user edited it in a text editor. On change: re-parse that file, update its row in GRDB.

**3. GRDB Index Sync** — On launch: scan all `.md` files, parse frontmatter, populate GRDB. Runtime: FSEvents triggers incremental re-index of changed files. GRDB's `ValueObservation` pushes updates to SwiftUI automatically.

### 3.3 Read Flow

1. **Launch** → scan all `.md` files → parse YAML frontmatter → populate GRDB index
2. **Runtime queries** → all queries hit GRDB (fast, sub-millisecond)
3. **External change** → FSEvents fires → re-parse changed file → update GRDB → SwiftUI auto-refreshes via `ValueObservation`

### 3.4 Write Flow

1. User saves (or debounced autosave fires)
2. Serialize to YAML frontmatter + markdown body
3. Write to `.tmp` file, rename over original (atomic)
4. Register the file's SHA256 hash for bounce-back prevention
5. Update GRDB index row
6. SwiftUI observes the GRDB change and re-renders

### 3.5 Agent Integration

**Agent reads:** `cat ~/AppMD/Journal/2026-02-13.md`. Done. Agents read markdown natively.

**Agent writes:** Same atomic pattern — write tmp, rename. The agent doesn't know GRDB exists.

**The glue:** Agent writes file → FSEvents detects change → app checks hash (not our write) → re-parses file → GRDB updates → UI refreshes. The filesystem IS the integration layer.

### 3.6 Bounce-Back Prevention

When the app writes a file, FSEvents will fire back. To avoid re-processing our own writes:

1. After writing, compute SHA256 of written content
2. Store hash in `writtenHashes[relativePath]`
3. When FSEvents fires, compute hash of the changed file
4. If hash matches `writtenHashes`, skip (it's our own write) and clear the hash
5. If hash doesn't match, it's an external change — process it

### 3.7 Concurrency Model

For personal apps (one user, one machine), concurrency is simple:

- **No file locking.** App writes freely, agent writes freely. Atomic writes prevent corruption.
- **No merge logic.** If the user has unsaved edits and an external change arrives, user's in-memory state wins. Agent can redo its work later. **User always wins.**
- **Race conditions are theoretical.** Two processes writing at the exact same millisecond to the same file doesn't happen on one person's laptop.
- **FSEvents bounce-back** is handled via hash tracking (see 3.6).
- **Crash recovery:** Debounced autosave means the user loses at most a few hundred milliseconds of typing on crash. For v1, this is acceptable.

### 3.8 Incremental Indexing

After the initial full rebuild, the index uses file modification dates:
1. Enumerate all `.md` files and their modification timestamps
2. Compare against stored `modified` timestamps in the `_files` table
3. Only re-parse files modified since last index
4. Clean up index entries for deleted files

Normal launch with 0-3 changed files: ~5ms. Cold rebuild of 365 files (1 year of journal): ~100ms. The index is fast.

### 3.9 WAL Mode (Concurrent Safety)

The SQLite index uses WAL (Write-Ahead Logging) journal mode, configured at database creation:

```swift
var config = Configuration()
config.prepareDatabase { db in
    try db.execute(sql: "PRAGMA journal_mode=WAL")
}
self.dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
```

**What this means:** Multiple processes can safely read and write the index simultaneously. Your app, an AI agent, and a CLI script can all hit the same SQLite database without coordination.

### 3.10 Batch Indexing

Both `rebuildIndex()` and `incrementalSync()` use a two-phase approach:

1. **Parse phase** — all `.md` files are read and parsed outside any database transaction
2. **Write phase** — all parsed records are written in a single GRDB transaction

This is automatic — you don't configure it. If anything fails mid-transaction, the entire batch rolls back cleanly.

### 3.11 Corrupted File Resilience

Malformed YAML frontmatter doesn't crash the indexer. Each file is parsed in a `do/catch` block. Bad files are logged and skipped:

```
[AppMDKit WARNING] Skipping file broken.md: Could not parse YAML frontmatter
```

Every other file continues indexing normally. This applies to `rebuildIndex()`, `incrementalSync()`, and `indexFile(at:)`.

### 3.12 SQL Reserved Word Safety

All GRDB table names are backtick-quoted in generated SQL. Schema types named `Column`, `Order`, `Group`, `Index`, or any other SQL reserved word work without issues.

### 3.13 Performance Characteristics

For personal-scale data (hundreds to low thousands of files), everything is fast:

- **Cold index rebuild** — scans all files, parses YAML, populates GRDB in a single transaction. Imperceptible for typical app sizes.
- **Incremental sync** — only re-parses files modified since last index. Normal app launch touches 0–3 files.
- **Queries** — sub-millisecond. SQLite is absurdly fast for these volumes.
- **Writes** — YAML serialize + atomic write + GRDB upsert, a few milliseconds per file.
- **Disk** — years of app data in single-digit megabytes.

---

## 4. AppMDKit API Reference

AppMDKit is a Swift package with six source files. Here is every public type, method, and property.

### 4.1 Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppMDKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppMDKit", targets: ["AppMDKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "AppMDKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(name: "AppMDKitTests", dependencies: ["AppMDKit"]),
    ]
)
```

**Dependencies:**
- **GRDB.swift** (≥6.29.0) — Type-safe SQLite for Swift. Provides `DatabaseQueue`, `Row`, `ValueObservation`, `StatementArguments`.
- **Yams** (≥5.1.0) — YAML parser/emitter for Swift (YAML 1.1 via libyaml).

### 4.2 `AppMDDocument`

A parsed AppMD markdown file: YAML frontmatter + markdown body.

```swift
public struct AppMDDocument: @unchecked Sendable {
    /// The parsed YAML frontmatter as a dictionary.
    public var frontmatter: [String: Any]

    /// The markdown body content (everything below the frontmatter).
    public var body: String

    /// The `type` field from frontmatter, if present.
    public var type: String? { get }

    public init(frontmatter: [String: Any] = [:], body: String = "")
}
```

### 4.3 `FileEngine`

Static methods for reading, writing, and atomic file operations. This is the lowest-level API.

```swift
public enum FileEngine {

    // --- Parsing ---

    /// Parse an AppMD markdown string into frontmatter + body.
    /// Handles `---` delimited YAML frontmatter.
    /// Applies Norway-problem normalization (bare yes/no → string, not Bool).
    public static func parse(content: String) -> AppMDDocument

    /// Parse a file at the given URL.
    public static func parse(fileAt url: URL) throws -> AppMDDocument

    // --- Serialization ---

    /// Serialize an AppMDDocument back to a markdown string with YAML frontmatter.
    public static func serialize(_ document: AppMDDocument) -> String

    // --- Atomic Write ---

    /// Write content to a file atomically: write to .tmp, then rename.
    /// Returns the SHA256 hash of the written content.
    @discardableResult
    public static func atomicWrite(content: String, to url: URL) throws -> String

    /// Write an AppMDDocument to a file atomically.
    @discardableResult
    public static func atomicWrite(document: AppMDDocument, to url: URL) throws -> String

    // --- Markdown Table ---

    /// Represents a parsed markdown table.
    public struct MarkdownTable: Sendable {
        public var headers: [String]
        public var rows: [[String: String]]
        public init(headers: [String] = [], rows: [[String: String]] = [])
    }

    /// Parse a markdown table from the body of a document.
    /// Returns nil if no valid table is found.
    public static func parseMarkdownTable(from body: String) -> MarkdownTable?

    /// Serialize a markdown table back to a string.
    public static func serializeMarkdownTable(_ table: MarkdownTable) -> String

    // --- Delete ---

    /// Move a file to the macOS Trash. Returns true if successful.
    @discardableResult
    public static func moveToTrash(url: URL) throws -> Bool

    // --- Hashing ---

    /// Compute SHA256 hash of data, returned as hex string.
    public static func sha256(_ data: Data) -> String
}
```

### 4.4 Schema Types

#### `AppMDSchema`

```swift
public struct AppMDSchema: Sendable {
    public let name: String
    public let version: Int
    public let types: [String: TypeDefinition]

    public init(name: String, version: Int, types: [String: TypeDefinition])
}
```

#### `TypeDefinition`

```swift
public struct TypeDefinition: Sendable {
    public let name: String
    public let fields: [FieldDefinition]

    public init(name: String, fields: [FieldDefinition])

    /// Look up a field by name.
    public func field(named name: String) -> FieldDefinition?
}
```

#### `FieldDefinition`

```swift
public struct FieldDefinition: Sendable {
    public let name: String
    public let type: FieldType
    public let isOptional: Bool
    public let defaultValue: String?

    public init(name: String, type: FieldType, isOptional: Bool = false, defaultValue: String? = nil)
}
```

#### `FieldType`

```swift
public indirect enum FieldType: Sendable, Equatable {
    case string
    case text
    case number
    case date
    case datetime
    case boolean
    case list(FieldType)
    case `enum`([String])
    case relationship(String)      // -> EntityName
    case listRelationship(String)  // [-> EntityName]

    /// The SQLite column type for GRDB table creation.
    public var sqliteType: String { get }
    // Returns "TEXT" for string/text/date/datetime/relationship/list/enum/listRelationship
    // Returns "REAL" for number
    // Returns "BOOLEAN" for boolean
}
```

#### `SchemaParser`

```swift
public enum SchemaParser {
    /// Load and parse a `_schema.yaml` file from a URL.
    public static func parse(at url: URL) throws -> AppMDSchema

    /// Parse schema from a YAML string.
    public static func parse(yaml: String) throws -> AppMDSchema
}
```

#### `SchemaValidator`

```swift
public enum SchemaValidator {
    /// Validate a document's frontmatter against a schema type definition.
    /// Returns a list of validation error strings (empty if valid).
    public static func validate(document: AppMDDocument, against typeDef: TypeDefinition) -> [String]
}
```

#### `SchemaError`

```swift
public enum SchemaError: Error, LocalizedError {
    case invalidFormat(String)
    case missingField(String)
    case invalidFieldType(String)
}
```

### 4.5 `AppMDIndex`

The GRDB-backed index. Scans markdown files, parses frontmatter, populates SQLite. The database lives in `.cache/index.sqlite` and is always deletable/rebuildable.

```swift
public final class AppMDIndex: @unchecked Sendable {
    /// The root directory of the AppMD app.
    public let rootURL: URL

    /// The schema for this app.
    public let schema: AppMDSchema

    /// The GRDB database queue.
    public let dbQueue: DatabaseQueue

    /// Path to the .cache directory.
    public let cacheURL: URL

    /// Callback invoked when the index is updated.
    public var onIndexUpdated: (() -> Void)?

    /// Initialize: creates .cache dir, GRDB database, schema-driven tables, FTS5 table.
    public init(rootURL: URL, schema: AppMDSchema) throws

    // --- Indexing ---

    /// Full scan of all .md files → rebuild entire index.
    public func rebuildIndex() throws

    /// Re-index only files modified since last index. Cleans up deleted files.
    public func incrementalSync() throws

    /// Parse and index a single file.
    public func indexFile(at url: URL, modified: Date? = nil) throws

    /// Remove a file from the index.
    public func removeFile(at url: URL) throws

    // --- Hash Tracking (bounce-back prevention) ---

    /// Register a hash for a file we just wrote.
    public func registerWrittenHash(_ hash: String, for path: String)

    /// Check if a file change was caused by our own write.
    /// Returns true and clears the hash if it matches.
    public func isOurWrite(for url: URL) -> Bool

    // --- Query ---

    /// The GRDB database queue for direct queries.
    public var database: DatabaseQueue { get }

    /// Full-text search across all indexed files.
    public func search(_ query: String) throws -> [(path: String, type: String?, snippet: String)]

    // --- Write Through ---

    /// Write a document and update the index. Handles atomic write + hash tracking.
    public func writeDocument(_ document: AppMDDocument, to url: URL) throws

    // --- Position Rebalancing ---

    /// Rebalance position values for items of a given type, optionally filtered.
    /// Reassigns positions to clean integers (1.0, 2.0, 3.0, ...) while preserving order.
    /// Returns the number of items rebalanced.
    @discardableResult
    public func rebalancePositions(
        type typeName: String,
        positionField: String = "position",
        filterField: String? = nil,
        filterValue: String? = nil
    ) throws -> Int

    /// Check if positions in a group are too fragmented and need rebalancing.
    /// Returns true if any gap between consecutive positions is smaller than `threshold`.
    public func needsRebalancing(
        type typeName: String,
        positionField: String = "position",
        filterField: String? = nil,
        filterValue: String? = nil,
        threshold: Double = 0.001
    ) throws -> Bool

    // --- Path Helpers ---

    /// Get relative path of a file URL from the root directory.
    /// Uses case-insensitive comparison for APFS compatibility.
    public func relativePath(for url: URL) -> String

    /// Get absolute URL for a relative path.
    public func absoluteURL(for relativePath: String) -> URL
}
```

**Index Tables Created:**

For a schema with type `Entry`, the index creates:

1. `_files` table — tracks all indexed files:
   - `path` (TEXT, PK) — relative file path
   - `type` (TEXT) — the `type` frontmatter value
   - `modified` (REAL) — file modification date as timeInterval
   - `hash` (TEXT) — SHA256 of file content

2. `entry` table (lowercased type name) — one row per file of that type:
   - `_path` (TEXT, PK) — relative file path
   - `_modified` (REAL) — modification timestamp
   - `_body` (TEXT) — the markdown body content
   - One column per schema field (except `text` fields, which map to `_body`)

3. `_fts` table — FTS5 contentless virtual table for full-text search:
   - `path`, `type`, `body`
   - Tokenizer: `porter unicode61`

### 4.6 `FSEventsWatcher`

Watches a directory for file changes using macOS FSEvents.

```swift
public final class FSEventsWatcher: @unchecked Sendable {
    /// The directory being watched.
    public let watchURL: URL

    /// Callback invoked when files change (after debouncing).
    public var onChange: (([URL]) -> Void)?

    /// Whether the watcher is currently active.
    public private(set) var isWatching: Bool

    public init(watchURL: URL, index: AppMDIndex? = nil)

    /// Start watching for file changes.
    public func start()

    /// Stop watching.
    public func stop()
}
```

**Behavior:**
- Uses `kFSEventStreamCreateFlagFileEvents` for file-level granularity
- 0.5s latency, 0.3s debounce on the callback
- Filters to `.md` files only, skips hidden files/directories
- Checks `index.isOurWrite()` for bounce-back prevention
- On file modify/create: calls `index.indexFile(at:)`
- On file remove: calls `index.removeFile(at:)`
- Dispatches `onChange` callback on main queue after debouncing

### 4.7 `AppMDQuery`

A fluent query builder over the GRDB index.

```swift
public struct AppMDQuery {
    public init(type typeName: String)
    // Note: tableName is typeName.lowercased()

    // --- Filtering ---
    public func `where`(_ column: String, equals value: DatabaseValueConvertible?) -> AppMDQuery
    public func `where`(_ column: String, notEquals value: DatabaseValueConvertible?) -> AppMDQuery
    public func `where`(_ column: String, lessThan value: DatabaseValueConvertible?) -> AppMDQuery
    public func `where`(_ column: String, greaterThan value: DatabaseValueConvertible?) -> AppMDQuery
    public func `where`(_ column: String, like pattern: String) -> AppMDQuery
    public func `where`(_ column: String, contains value: String) -> AppMDQuery  // LIKE %value%
    public func whereNull(_ column: String) -> AppMDQuery
    public func whereNotNull(_ column: String) -> AppMDQuery

    // --- Sorting ---
    public func sort(by column: String, descending: Bool = false) -> AppMDQuery

    // --- Pagination ---
    public func limit(_ count: Int) -> AppMDQuery
    public func offset(_ count: Int) -> AppMDQuery

    // --- Execution ---
    public func buildSQL() -> (String, StatementArguments)
    public func fetch(from db: Database) throws -> [Row]
    public func fetch(from dbQueue: DatabaseQueue) throws -> [Row]
    public func count(from db: Database) throws -> Int
}
```

**Example usage:**
```swift
let query = AppMDQuery(type: "Entry")
    .where("mood", equals: "happy")
    .sort(by: "date", descending: true)
    .limit(10)

let rows = try query.fetch(from: store.database)
```

### 4.8 `AppMDObservation`

Provides GRDB `ValueObservation`-based reactive queries for SwiftUI.

```swift
public struct AppMDObservation {
    /// Create a ValueObservation that watches for changes to a query.
    public static func observe(
        query: AppMDQuery,
        in dbQueue: DatabaseQueue
    ) -> ValueObservation<ValueReducers.Fetch<[Row]>>

    /// Create a ValueObservation that watches a specific table for all rows.
    public static func observeAll(
        type typeName: String,
        sortBy column: String? = nil,
        descending: Bool = false,
        in dbQueue: DatabaseQueue
    ) -> ValueObservation<ValueReducers.Fetch<[Row]>>
}
```

### 4.9 `AppMDSearchQuery`

Full-text search across indexed documents.

```swift
public struct AppMDSearchQuery {
    public init(text: String, type: String? = nil)

    /// Execute the search. Returns matching paths with snippets.
    public func execute(on dbQueue: DatabaseQueue) throws -> [(path: String, type: String?, snippet: String)]
}
```

### 4.10 `AppMDStore`

The main entry point. Manages schema, GRDB index, FSEvents watcher, and atomic writes.

```swift
public final class AppMDStore: ObservableObject, @unchecked Sendable {
    /// The root directory of the AppMD app.
    public let rootURL: URL

    /// The parsed schema.
    public let schema: AppMDSchema

    /// The GRDB index.
    public let index: AppMDIndex

    /// The FSEvents watcher.
    public let watcher: FSEventsWatcher

    /// Published signal for SwiftUI to react to changes.
    @Published public var lastChangeDate: Date

    /// Callback when external files change.
    public var onExternalChange: (([URL]) -> Void)?

    /// Initialize: reads _schema.yaml, creates GRDB index, performs initial scan,
    /// starts FSEvents watcher. Throws if _schema.yaml is missing.
    public init(rootURL: URL) throws

    // --- Read ---
    public func readDocument(at relativePath: String) throws -> AppMDDocument
    public func readDocument(at url: URL) throws -> AppMDDocument

    // --- Write ---
    /// Atomic write + index update. Triggers objectWillChange for SwiftUI.
    public func writeDocument(_ document: AppMDDocument, to relativePath: String) throws
    public func writeDocument(_ document: AppMDDocument, to url: URL) throws

    // --- Delete ---
    /// Move to Trash + remove from index.
    public func deleteDocument(at relativePath: String) throws
    public func deleteDocument(at url: URL) throws

    // --- Query ---
    public func query(type: String) -> AppMDQuery
    public func fetch(query: AppMDQuery) throws -> [Row]
    public func search(_ text: String, type: String? = nil) throws -> [(path: String, type: String?, snippet: String)]
    public func observe(query: AppMDQuery) -> ValueObservation<ValueReducers.Fetch<[Row]>>

    /// The underlying GRDB database queue for advanced/raw queries.
    public var database: DatabaseQueue { get }

    // --- Position Rebalancing ---

    /// Rebalance position values — reassigns clean integers while preserving order.
    @discardableResult
    public func rebalancePositions(
        type typeName: String,
        positionField: String = "position",
        filterField: String? = nil,
        filterValue: String? = nil
    ) throws -> Int

    /// Check if positions are too fragmented and need rebalancing.
    public func needsRebalancing(
        type typeName: String,
        positionField: String = "position",
        filterField: String? = nil,
        filterValue: String? = nil,
        threshold: Double = 0.001
    ) throws -> Bool

    // --- Re-index ---
    public func rebuildIndex() throws
    public func sync() throws  // incremental
}
```

**Errors:**

```swift
public enum AppMDStoreError: Error, LocalizedError {
    case schemaNotFound(String)
    case typeNotFound(String)
    case fileNotFound(String)
}
```

---

## 5. Building an App: Step by Step

This section teaches the patterns for building any AppMD-powered app. The examples use a Journal app but the approach works for any domain (budget tracker, habit tracker, notes, bookmarks, etc.).

### 5.1 The Shape of an AppMD App

Every AppMD app has the same structure:

1. **Schema file** — `_schema.yaml` in your data directory, defines types and fields
2. **Data directory** — folder of `.md` files with YAML frontmatter
3. **Store layer** — a Swift class that wraps `AppMDStore`, exposes published properties for SwiftUI
4. **Views** — standard SwiftUI views that read from the store

The derived cache (`.cache/index.sqlite`) is created automatically. You never manage it.

### 5.2 Package.swift Setup

Add AppMDKit as a dependency. Use `.executableTarget` for a standalone app:

```swift
dependencies: [
    .package(path: "../AppMDKit"),  // local, or use a git URL
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [.product(name: "AppMDKit", package: "AppMDKit")],
        path: "Sources"
    ),
]
```

Platform minimum is `.macOS(.v14)`.

### 5.3 Writing a Schema

Create `_schema.yaml` in your data directory. Each top-level key is a type name. Fields have a type and optional constraints:

```yaml
name: Journal
version: 1

Entry:
  fields:
    title: string
    date: date
    mood:
      type: enum
      values: [happy, neutral, sad, anxious, excited]
    tags:
      type: array
      items: string
```

Supported field types: `string`, `int`, `float`, `bool`, `date`, `datetime`, `enum`, `array`, `ref`, `object`.

### 5.4 Writing Data Files

Each document is a `.md` file. Frontmatter fields match the schema. Body is freeform markdown:

```markdown
---
type: Entry
title: Morning Hike
date: 2026-02-11
mood: happy
tags: [outdoors, exercise]
---

Hiked the coastal trail at sunrise. The fog was rolling in
over the cliffs and it felt like walking through clouds.
```

The `type` field links the document to its schema definition. Documents MAY also include an `id` field as a stable unique identifier within the type — if present, `id` takes priority over the filename for reference resolution (see the spec for details). Filename is up to you — dates, slugs, UUIDs all work.

### 5.5 Creating a Store

Your store wraps `AppMDStore` and publishes reactive state for SwiftUI:

```swift
import AppMDKit
import Combine

@MainActor
class MyStore: ObservableObject {
    @Published var entries: [AppMDDocument] = []
    @Published var searchText: String = ""
    
    private var store: AppMDStore?
    
    func start() async throws {
        let dataDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AppMD/Journal")
        
        store = try await AppMDStore(directory: dataDir)
        
        // Subscribe to changes (FSEvents triggers this on any file edit)
        store?.onUpdate = { [weak self] docs in
            self?.entries = docs
        }
    }
}
```

Key pattern: `AppMDStore` handles file reading, indexing, and watching. Your store just receives updates and publishes them.

### 5.6 Querying Documents

Use `AppMDStore` to filter, sort, and search:

```swift
// All entries, sorted by date descending
let entries = try store.query(type: "Entry", sortBy: "date", ascending: false)

// Filter by field value
let happyDays = try store.query(type: "Entry", where: ["mood": "happy"])

// Full-text search across body content
let results = try store.search("coastal trail")
```

Queries hit the derived SQLite index — fast even with thousands of files.

### 5.7 Writing Documents

Create or update documents through `AppMDStore`:

```swift
// Build a new document
var doc = AppMDDocument()
doc.frontmatter["type"] = "Entry"
doc.frontmatter["title"] = "Evening Walk"
doc.frontmatter["date"] = "2026-02-15"
doc.frontmatter["mood"] = "neutral"
doc.frontmatter["tags"] = ["outdoors"]
doc.body = "Short walk around the neighborhood after dinner."

// Save — writes the .md file atomically, index updates via FSEvents
try store.save(doc, filename: "2026-02-15.md")
```

Atomic writes (tmp file + rename) prevent corruption. The FSEvents watcher picks up the change and re-indexes automatically.

### 5.8 Wiring into SwiftUI

Standard SwiftUI patterns — `@StateObject` for the store, pass documents to views:

```swift
@main
struct MyApp: App {
    @StateObject private var store = MyStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .task { try? await store.start() }
        }
    }
}
```

Documents are plain dictionaries — access fields via `doc.frontmatter["title"]` and body via `doc.body`. No Core Data, no SwiftData, no model classes needed.

### 5.9 App Lifecycle Note

Pure SwiftUI executable targets (no Xcode, `swift run`) need an explicit app delegate to keep the app alive:

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// In your App struct:
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

Without this, the app launches and immediately exits.

### 5.10 End-to-End Data Flow

```
User edits .md file (any editor)
        ↓
FSEvents fires (file changed)
        ↓
FileEngine re-reads the file
        ↓
GRDBIndex updates the SQLite row
        ↓
AppMDStore publishes new document list
        ↓
SwiftUI view updates automatically
```

This is the magic: edit a file in VS Code, Obsidian, vim, or anything — the app updates in real time. The file is always the source of truth.

## 6. Key Decisions & Gotchas

### 6.1 The Norway Problem (YAML Bool Coercion)

**The bug:** In YAML 1.1, bare `yes`, `no`, `on`, `off` are interpreted as booleans, not strings. A country field with value `no` becomes `false`:

```yaml
country: no   # → boolean false, not "Norway"
```

**How AppMDKit handles it:** `FileEngine.parse()` includes `normalizeBooleans()` which:
1. Parses YAML with Yams (which uses YAML 1.1 rules)
2. For any value Yams returned as `Bool`, checks the raw YAML text
3. If the raw value was `yes`/`no`/`on`/`off` (not literally `true`/`false`), restores it as a string

**When building an app:** Always be aware that Yams will coerce ambiguous values. If you're serializing frontmatter, quote string values that could be misinterpreted: `country: "no"`.

### 6.2 FTS5 Contentless Tables

**The pattern:** AppMDKit creates an FTS5 virtual table with `content=''` (contentless):

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS _fts USING fts5(
    path, type, body,
    content='',
    tokenize='porter unicode61'
);
```

**Why contentless:** The actual content lives in the per-type tables and the files. Storing it again in FTS5 would double storage. Contentless FTS5 only stores the inverted index — enough for `MATCH` queries and `snippet()` extraction.

**Gotcha:** Contentless FTS5 tables don't support `REPLACE`. You must `DELETE` then `INSERT`:

```swift
try db.execute(sql: "DELETE FROM _fts WHERE path = ?", arguments: [relativePath])
try db.execute(sql: "INSERT INTO _fts (path, type, body) VALUES (?, ?, ?)", arguments: [...])
```

### 6.3 APFS Case Insensitivity

macOS uses APFS with case-insensitive (but case-preserving) file paths by default. `Journal/Entry.md` and `Journal/entry.md` are the same file.

**How AppMDKit handles it:** `AppMDIndex.relativePath(for:)` uses lowercased comparison for path matching:

```swift
let rootPath = rootURL.standardizedFileURL.path.lowercased()
let filePathLower = filePath.lowercased()
if filePathLower.hasPrefix(rootPath) { ... }
```

**When building an app:** Don't create files that differ only by case. Use consistent lowercase or date-based naming.

### 6.4 Atomic Writes

**The pattern:** Write to `.tmp`, then rename over original. Rename is atomic on APFS.

```swift
public static func atomicWrite(content: String, to url: URL) throws -> String {
    let data = Data(content.utf8)
    let hash = sha256(data)
    let tmpURL = url.appendingPathExtension("tmp")

    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: tmpURL)

    if FileManager.default.fileExists(atPath: url.path) {
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
    } else {
        try FileManager.default.moveItem(at: tmpURL, to: url)
    }

    return hash
}
```

**Why:** Guarantees files are never half-written. If the app crashes mid-write, the original file is intact (the `.tmp` is garbage). This is critical for data integrity.

### 6.5 NSApplicationDelegateAdaptor

**The issue:** Pure SwiftUI macOS apps don't quit when the last window is closed — they keep running in the dock.

**The fix:** Use `NSApplicationDelegateAdaptor` with a custom `AppDelegate`:

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // ...
}
```

This is a common macOS SwiftUI pattern — not AppMD-specific, but you'll need it for any standalone utility app.

### 6.6 GRDB Table Names Are Lowercased Type Names

The index creates GRDB tables using `typeName.lowercased()`. A schema type `Entry` maps to table `entry`. A type `TransactionLog` maps to table `transactionlog`.

**When querying:** `AppMDQuery(type: "Entry")` handles this automatically. But if you're writing raw SQL against `store.database`, use the lowercase name.

### 6.7 The `_body` Column

For document-type files, the markdown body is stored in the `_body` column of the GRDB table. It's the content below the frontmatter `---`. When constructing your model from a `Row`:

```swift
self.body = row["_body"] as? String ?? ""
```

### 6.8 The `_path` and `_modified` Columns

Every row in a type table has:
- `_path` (TEXT, primary key) — relative file path from the app root
- `_modified` (REAL) — file modification date as `timeIntervalSince1970`

These are added automatically by `AppMDIndex`. The `_path` serves as the stable identifier for each document.

### 6.9 Tags/Lists Stored as JSON

Array fields (like `tags?: [string]`) are stored as JSON strings in the GRDB index. When reading:

```swift
if let tagsStr = row["tags"] as? String, tagsStr.hasPrefix("[") {
    if let data = tagsStr.data(using: .utf8),
       let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
        self.tags = arr
    }
}
```

When filtering by list contents, use `contains` (which becomes `LIKE %value%`):
```swift
query.where("tags", contains: "work")
```

### 6.10 Schema Evolution Is Free

- **Add optional fields:** Old files without the field are still valid. The column returns `nil`.
- **Add required fields with defaults:** `currency: string = MYR`. Old files get the default.
- **Rename fields:** Update every file with `sed` or a script. It's text.
- **No migration files.** No version management. The files are the data. The schema describes their current shape.

### 6.11 Delete Uses Trash, Not rm

`FileEngine.moveToTrash(url:)` uses `FileManager.trashItem(at:)`, which moves the file to macOS Trash. The user can recover it. This is intentional — never permanently delete user data.

### 6.12 Yams Serialization Key Ordering

When `FileEngine.serialize()` dumps frontmatter back to YAML via `Yams.dump()`, dictionary key ordering is not guaranteed. The YAML will be valid but keys may appear in a different order than the original file. This is cosmetic — it doesn't affect parsing.

### 6.13 Body Leading/Trailing Newlines

When creating an `AppMDDocument` for writing, the convention is to add a leading newline to the body:

```swift
AppMDDocument(frontmatter: frontmatter, body: "\n" + body + "\n")
```

This ensures the serialized file has a blank line between the closing `---` and the body content, which is standard markdown formatting.

### 6.14 Position Rebalancing (Float Ordering)

**The problem:** Drag-and-drop ordering uses float positions. Insert between items A (position 1.0) and B (position 2.0) → new item gets position 1.5. Keep inserting: 1.25, 1.125, 1.0625... Eventually IEEE 754 doubles lose precision and positions collapse.

**The fix:** AppMDKit provides two methods:

```swift
// Detect fragmentation — returns true if any gap < threshold
let needsIt = try store.needsRebalancing(
    type: "Card",
    positionField: "position",
    filterField: "column",
    filterValue: "todo",
    threshold: 0.001  // default
)

// Reassign clean integers (1.0, 2.0, 3.0, ...) preserving order
let count = try store.rebalancePositions(
    type: "Card",
    positionField: "position",
    filterField: "column",
    filterValue: "todo"
)
// count = number of files actually updated (skips already-clean positions)
```

**How it works:** Reads all items sorted by current position, then writes back with positions 1.0, 2.0, 3.0, etc. Each file is atomically rewritten with the updated frontmatter. The index updates accordingly.

**When to call it:** After drag-and-drop operations, check `needsRebalancing()`. If true, call `rebalancePositions()`. Or call it periodically (e.g., on app launch). It's fast — only touches files whose positions actually change.

### 6.15 Importing GRDB in App Code

Your app needs to `import GRDB` directly (in addition to `import AppMDKit`) to work with `Row`, `ValueObservation`, `AnyDatabaseCancellable`, and other GRDB types. Add GRDB as a direct dependency of your app target, or access it transitively through AppMDKit.

In the demo app, `JournalStore.swift` imports both:
```swift
import AppMDKit
import GRDB
```

---

## 7. Quick Reference

### To Build an AppMD App, You Need:

1. **Schema file** — `_schema.yaml` in your data directory defining your types and fields
2. **Data directory** — a folder (e.g., `~/AppMD/Journal/`) containing your `.md` files
3. **AppMDKit dependency** — add the package to your `Package.swift` or Xcode project
4. **Store class** — an `ObservableObject` that wraps `AppMDStore`, defines your model types, and sets up `ValueObservation` for reactive queries
5. **SwiftUI views** — standard SwiftUI views that consume the store via `@EnvironmentObject` or `@ObservedObject`

### Minimal Checklist

```
☐ Create data directory (e.g., ~/AppMD/MyApp/)
☐ Write _schema.yaml with your types
☐ Create sample .md files with YAML frontmatter
☐ Add AppMDKit as Swift package dependency
☐ Create model struct with init(row: Row) and toDocument() -> AppMDDocument
☐ Create store class:
    ☐ Initialize AppMDStore(rootURL:) in init
    ☐ Set up AppMDObservation for reactive queries
    ☐ Store the AnyDatabaseCancellable (keep observation alive)
    ☐ Implement CRUD methods (create/update/delete)
☐ Create SwiftUI views consuming the store
☐ Add NSApplicationDelegateAdaptor for macOS window behavior
☐ Test: edit a .md file externally → app should auto-update
```

### Column Name Cheat Sheet

| Source | Column Name | Description |
|--------|------------|-------------|
| AppMDKit auto | `_path` | Relative file path (PRIMARY KEY) |
| AppMDKit auto | `_modified` | File modification timestamp |
| AppMDKit auto | `_body` | Markdown body content |
| Schema field | `{fieldname}` | Exactly as declared in schema |
| Schema `text` field | *(maps to `_body`)* | Not a separate column |

### Query Pattern Cheat Sheet

```swift
// Basic query
let q = AppMDQuery(type: "Entry")
    .where("mood", equals: "happy")
    .sort(by: "date", descending: true)
    .limit(10)
let rows = try store.fetch(query: q)

// Full-text search
let results = try store.search("coffee", type: "Entry")

// Reactive observation (for SwiftUI)
let observation = AppMDObservation.observe(query: q, in: store.database)
let cancellable = observation.start(in: store.database,
    onError: { error in ... },
    onChange: { rows in ... }
)

// Raw GRDB (advanced)
let count = try store.database.read { db in
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry WHERE mood = ?", arguments: ["happy"])
}
```

### Write Pattern Cheat Sheet

```swift
// Create a document
let doc = AppMDDocument(
    frontmatter: ["type": "Entry", "date": "2026-03-01", "mood": "happy"],
    body: "\nToday was great.\n"
)
try store.writeDocument(doc, to: "2026-03-01.md")

// Delete a document (moves to Trash)
try store.deleteDocument(at: "2026-03-01.md")
```

### File Format Cheat Sheet

```markdown
---
type: TypeName        ← required, matches a type in _schema.yaml
field1: value         ← required fields
field2: value
optionalField: value  ← optional fields (may be absent)
listField:            ← list fields
  - item1
  - item2
---

Markdown body goes here. Maps to `text` type fields.
```

---

*This document is self-contained. An AI coding agent reading only this file has everything needed to build a working AppMD-powered macOS app.*
