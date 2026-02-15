# AppMD Specification

**Version 0.1 · Draft**

AppMD (Application Markdown) is a set of conventions for using standard markdown and YAML as the data layer for applications. Every AppMD file is valid markdown. Every AppMD schema is valid YAML. There is no new format to learn — just conventions on top of what you already know.

---

## Principles

**1. Files are the source of truth.**
Any database, index, or cache is derived. Delete it, rebuild from files. The files are always authoritative.

**2. Every file is valid markdown.**
Open any AppMD file in any text editor, any markdown viewer, any OS. It just works. Backwards compatible with everything.

**3. Convention over invention.**
YAML frontmatter already exists. Wiki links already exist. Markdown tables already exist. AppMD standardizes what people already do — it doesn't invent new syntax.

**4. Progressive structure.**
Start with plain markdown. Add frontmatter when you want metadata. Add a schema when you want types. Add an index when you want performance. Each layer is optional.

**5. AI agents are first-class citizens.**
An LLM reads markdown natively. An agent discovers your data by reading files. No protocol, no API, no SDK required. Just `cat` and `grep`.

**6. Simplicity wins.**
Markdown won by what it left out, not what it included. AppMD follows the same principle.

---

## Quick Start

A complete journal app in three files:

**`Journal/_schema.yaml`**

```yaml
name: Journal
version: 1

Entry:
  date: date
  mood?: happy | sad | neutral | focused | anxious
  tags?: [string]
  body: text
```

**`Journal/2026-02-13.md`**

```markdown
---
type: Entry
date: 2026-02-13
mood: focused
tags: [work, design]
---

Spent the morning designing AppMD. The key insight: don't invent a new
format. Create conventions for the format everyone already uses.

Had coffee with [[Contacts/alex-chen]]. Talked about the gap between
files and databases. There shouldn't be one.
```

**`Journal/2026-02-12.md`**

```markdown
---
type: Entry
date: 2026-02-12
mood: happy
tags: [personal, cooking]
---

Made laksa from scratch. Turned out better than expected.
Finally getting the balance of coconut milk to chili right.
```

That's it. The schema defines the shape. The files hold the data. Any markdown viewer renders them. Any AI agent reads them. `grep mood Journal/*.md` queries them.

---

## Data Files

AppMD handles two shapes of data: **documents** and **records**.

### Documents

Documents are primarily narrative — a journal entry, a note, an essay. One file per document. YAML frontmatter for structured metadata, markdown body for content.

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

Every document has a `type` field in its frontmatter that points to a type defined in the app's `_schema.yaml`.

The markdown body maps to the `text` type in the schema. If the schema declares `body: text`, that's the file's markdown content below the frontmatter.

### Records

Records are primarily structured — a transaction, a habit log, a contact. Two patterns:

**Individual files** — for entities with rich data or relationships.

`Contacts/alex-chen.md`:

```markdown
---
type: Contact
name: Alex Chen
email: alex@example.com
company: Acme Corp
met: 2024-03-15
tags: [friend, developer]
---

Met Alex at a conference in KL. Works on developer tools.
Great taste in coffee shops.
```

**Collection files** — for high-volume tabular data. One file holds many records as a markdown table.

`Budget/transactions/2026-02.md`:

```markdown
---
type: TransactionLog
month: 2026-02
---

| date | amount | category | merchant | note |
|------|--------|----------|----------|------|
| 2026-02-13 | -4.50 | food | Feeka Coffee | Coffee with Alex |
| 2026-02-13 | -12.00 | transport | Grab | To office |
| 2026-02-12 | -89.00 | groceries | Jaya Grocer | Weekly shop |
| 2026-02-12 | 5000.00 | income | Employer | February salary |
```

Use individual files when records have relationships, long-form notes, or rich metadata. Use collection files when you have many simple records — dozens or hundreds of rows that are easier to scan as a table.

The schema declares which pattern a type uses. The developer or user picks the one that fits their data.

---

## Schema Files

Every app has a `_schema.yaml` in its root directory. It defines the types, fields, and constraints for that app's data.

### Basic Structure

```yaml
name: Budget
version: 1

Transaction:
  date: date
  amount: number
  category: food | transport | groceries | entertainment | utilities | rent | health
  merchant?: string
  note?: text
  account: -> Account
  tags?: [string]

Account:
  name: string
  type: checking | savings | credit | cash
  currency: string = USD
  institution?: string
```

A schema file has:
- `name` — the app name
- `version` — schema version (integer)
- One or more **type definitions** — capitalized names (like `Transaction`, `Account`) with their fields

### Type System

**Base types:**

| Type | Description | Example |
|------|-------------|---------|
| `string` | Short text | `"Feeka Coffee"` |
| `text` | Long text / markdown body | The file's markdown content |
| `number` | Integer or decimal | `42`, `-4.50` |
| `date` | ISO 8601 date | `2026-02-13` |
| `datetime` | ISO 8601 datetime | `2026-02-13T09:30:00` |
| `boolean` | True or false | `true`, `false` |

**Compound types:**

| Syntax | Meaning | Example |
|--------|---------|---------|
| `[type]` | List of a type | `[string]` → `[coffee, social]` |
| `val1 \| val2 \| val3` | Enum — one of the listed values | `food \| transport \| groceries` |
| `-> EntityName` | Relationship to another entity | `-> Account` |

**Modifiers:**

| Syntax | Meaning | Example |
|--------|---------|---------|
| `?` suffix | Optional field | `merchant?: string` |
| `= value` | Default value | `currency: string = USD` |

### Field Declarations

Fields follow a `name: type` pattern. Append `?` to the field name for optional fields:

```yaml
Transaction:
  date: date                    # required date field
  amount: number                # required number field
  merchant?: string             # optional string field
  tags?: [string]               # optional list of strings
  category: food | transport    # required enum
  account: -> Account           # required relationship
  currency: string = MYR        # required with default
```

### Enums

Simple enums use pipe syntax inline:

```yaml
mood: happy | sad | neutral | focused | anxious
```

For enums that need metadata, unfold into a YAML structure:

```yaml
category:
  - value: food
    icon: 🍕
    color: orange
  - value: transport
    icon: 🚗
    color: blue
  - value: groceries
    icon: 🛒
    color: green
```

Both forms are valid. Start simple, unfold when you need more.

### The `text` Type

The `text` type represents long-form markdown content. For document-type files, this maps to the file body — everything below the frontmatter. A schema typically declares one `text` field per document type:

```yaml
Entry:
  date: date
  mood?: happy | sad | neutral
  body: text              # ← this IS the markdown body of the file
```

For records stored in frontmatter only (like contacts or accounts), `text` fields are short markdown strings stored as frontmatter values.

### Example: Complete Schema

```yaml
name: Contacts
version: 1

Contact:
  name: string
  email?: string
  phone?: string
  company?: string
  role?: string
  met?: date
  birthday?: date
  tags?: [string]
  notes?: text
  relationships?: [-> Contact]
```

---

## Relationships

Entities reference each other through **wiki links** in frontmatter values. A wiki link is a file path wrapped in double brackets: `[[path/to/entity]]`.

### Within an App

A transaction references an account:

```yaml
---
type: Transaction
date: 2026-02-13
amount: -4.50
category: food
account: [[accounts/cash]]
---
```

The path is relative to the app's root directory. `[[accounts/cash]]` resolves to `Budget/accounts/cash.md`.

### Across Apps

A journal entry references a contact and a transaction:

```yaml
---
type: Entry
date: 2026-02-13
mood: focused
people:
  - [[Contacts/alex-chen]]
related:
  - [[Budget/transactions/2026-02]]
---
```

Cross-app paths are relative to the AppMD root directory (e.g., `~/AppMD/`).

### In the Schema

Relationships are declared with the `->` arrow syntax:

```yaml
Transaction:
  account: -> Account          # one-to-one relationship
  tags?: [string]

Contact:
  relationships?: [-> Contact] # list of relationships
```

The arrow tells tooling and agents: "this field is a link to another entity, not a plain string." Standard markdown links (`[text](path)`) also work as relationships, but wiki links are preferred for their brevity.

---

## Directory Conventions

```
~/AppMD/
├── _appmd.yaml                # Root manifest
├── Budget/
│   ├── _schema.yaml           # Budget types
│   ├── accounts/
│   │   ├── cash.md
│   │   └── maybank.md
│   └── transactions/
│       ├── 2026-01.md         # Collection file (table)
│       └── 2026-02.md
├── Journal/
│   ├── _schema.yaml           # Journal types
│   ├── 2026-02-13.md          # Individual documents
│   └── 2026-02-12.md
├── Contacts/
│   ├── _schema.yaml           # Contact types
│   └── alex-chen.md           # Individual records
└── Habits/
    ├── _schema.yaml           # Habit types
    ├── habits/
    │   ├── meditation.md      # Habit definition
    │   └── exercise.md
    └── logs/
        └── 2026-02.md         # Monthly log (table)
```

### Conventions

- **One folder per app.** Each app's data lives in its own top-level folder.
- **`_` prefix for meta files.** `_schema.yaml`, `_appmd.yaml` — these are infrastructure, not data. Like `_index.html` or `_config.yml`.
- **Subfolders for entity types.** `accounts/`, `transactions/`, `habits/`. These map to types defined in the schema.
- **File naming is free-form.** Use what makes sense: dates for journal entries (`2026-02-13.md`), slugs for entities (`alex-chen.md`), year-month for collection files (`2026-02.md`).
- **No hidden files for data.** AppMD data is always visible. Derived caches (like SQLite indexes) live in hidden folders (`.cache/`) and are always deletable.

---

## Discovery

How agents and tools find and understand AppMD data.

### Root Manifest: `_appmd.yaml`

The root directory contains a manifest that lists all apps:

```yaml
name: My Data
apps:
  - folder: Budget
    name: Budget Tracker
    description: Personal income and expenses

  - folder: Journal
    name: Daily Journal
    description: Daily reflections and notes

  - folder: Contacts
    name: Contacts
    description: People I know

  - folder: Habits
    name: Habit Tracker
    description: Daily habits and streaks
```

### Schema Files: `_schema.yaml`

Each app folder contains a schema that describes its types. An agent reads the schema to understand what data exists and how it's structured.

### Discovery Flow

An agent encountering AppMD data for the first time:

1. **Read `_appmd.yaml`** → learn what apps exist and what they do
2. **Read `Budget/_schema.yaml`** → learn that Budget has `Transaction` and `Account` types, understand their fields
3. **List `Budget/transactions/`** → find the data files
4. **Read a file** → parse frontmatter and content

Four file reads. Zero configuration. Zero authentication. The agent now understands the entire data model.

---

## Query Model

Three tiers, all reading the same files.

### Tier 1: File Operations

Works on any machine. Any agent. Zero setup.

```bash
# List all journal entries
ls Journal/

# Find entries mentioning "coffee"
grep -rl "coffee" Journal/

# Show all transaction files
find Budget/transactions/ -name "*.md"

# Find large expenses
grep "amount: -[0-9][0-9][0-9]" Budget/transactions/*.md
```

This is the universal baseline. It's slow, imprecise, and limited — but it works everywhere, including inside any AI agent that can execute shell commands.

### Tier 2: CLI Tool

With AppMD tooling installed, structured queries over files:

```bash
# Find expensive transactions this month
appmd query Transaction --where "amount < -50" --sort "date desc"

# List contacts tagged "developer"
appmd query Contact --where "tags contains developer"

# Show habits completed today
appmd query HabitLog --where "date = 2026-02-13" --where "done = true"

# Validate all files against their schemas
appmd validate
```

The CLI parses files, understands schemas, and returns structured results. Faster and more precise than raw `grep`, still fully portable.

### Tier 3: Indexed Query

With a running app or SDK, a derived SQLite index enables instant queries and reactive UI bindings:

```swift
@Query(
    filter: #Predicate<Transaction> { $0.amount < -50 },
    sort: \.date,
    order: .reverse
) var bigExpenses: [Transaction]
```

The index is derived from files. Delete it and it rebuilds. Change a file externally (agent, text editor, CLI) and the index updates. The files are the source of truth. The SQLite index is a cache — like a search engine's index over web pages. Useful for speed, but the pages are what matter.

**All three tiers read the same data.** Tier 1 is universal but slow. Tier 2 is precise and portable. Tier 3 is instant and reactive. Pick the tier that fits your context.

### Derived Index Layers

The SQLite index is the primary derived layer, but AppMD data supports multiple index types. Each answers a different shape of question, all derived from the same source files, all disposable and rebuildable:

**SQLite/GRDB** — structured queries. "Show me transactions over $50 this month, sorted by date." Filtering, sorting, aggregation, joins. This is what powers app UIs.

**Git** — version history. "What did this file look like 3 weeks ago?" `git init` on your AppMD directory gives you full history, diffs, and blame on every piece of personal data. Basically free.

**Embeddings** — semantic search. "Find journal entries about feeling burned out." Fuzzy matching that doesn't require exact words. Useful for journals and notes where you don't remember exact terms.

Zero redundancy between them. Each is optional, each is derived, each is deletable. Start with SQLite (essential for app performance), add Git (nearly free, high value), add embeddings when semantic search earns its place.

---

## Complete Example

A full setup with four apps. This is what `~/AppMD/` looks like in practice.

### Root Manifest

**`_appmd.yaml`**

```yaml
name: My Life
apps:
  - folder: Budget
    name: Budget Tracker
    description: Personal income and expenses

  - folder: Journal
    name: Daily Journal
    description: Daily reflections and notes

  - folder: Contacts
    name: Contacts
    description: People I know

  - folder: Habits
    name: Habit Tracker
    description: Daily habits and streaks
```

### Budget App

**`Budget/_schema.yaml`**

```yaml
name: Budget
version: 1

Transaction:
  date: date
  amount: number
  category: food | transport | groceries | entertainment | utilities | rent | health | income
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

**`Budget/accounts/cash.md`**

```markdown
---
type: Account
name: Cash
type: cash
currency: MYR
---
```

**`Budget/accounts/maybank.md`**

```markdown
---
type: Account
name: Maybank Checking
type: checking
currency: MYR
institution: Maybank
---
```

**`Budget/transactions/2026-02.md`**

```markdown
---
type: TransactionLog
month: 2026-02
---

| date | amount | category | merchant | account | note |
|------|--------|----------|----------|---------|------|
| 2026-02-13 | -4.50 | food | Feeka Coffee | [[accounts/cash]] | Coffee with Alex |
| 2026-02-13 | -12.00 | transport | Grab | [[accounts/cash]] | To office |
| 2026-02-12 | -89.00 | groceries | Jaya Grocer | [[accounts/maybank]] | Weekly shop |
| 2026-02-12 | 5000.00 | income | Employer | [[accounts/maybank]] | February salary |
| 2026-02-11 | -250.00 | utilities | TNB | [[accounts/maybank]] | Electricity bill |
| 2026-02-10 | -35.00 | entertainment | Netflix | [[accounts/maybank]] | Monthly sub |
```

### Journal App

**`Journal/_schema.yaml`**

```yaml
name: Journal
version: 1

Entry:
  date: date
  mood?: happy | sad | neutral | focused | anxious | grateful
  tags?: [string]
  people?: [-> Contacts/Contact]
  body: text
```

**`Journal/2026-02-13.md`**

```markdown
---
type: Entry
date: 2026-02-13
mood: focused
tags: [work, design]
people:
  - [[Contacts/alex-chen]]
---

Spent the morning designing AppMD. The core insight keeps coming back:
don't invent something new. Standardize what already works.

Had coffee with [[Contacts/alex-chen]] at Feeka. He pushed back on the
schema-as-YAML approach — said JSON Schema is more expressive. He's right
that it's more expressive. But expressiveness isn't the goal. Readability is.

Tomorrow: write the full spec. Make it feel inevitable.
```

**`Journal/2026-02-12.md`**

```markdown
---
type: Entry
date: 2026-02-12
mood: happy
tags: [personal, cooking]
---

Made laksa from scratch. The trick is toasting the spice paste longer
than you think — until the oil separates. Took 45 minutes but worth it.

Grocery run at Jaya Grocer cost RM89. Need to track food spending
more carefully this month.
```

### Contacts App

**`Contacts/_schema.yaml`**

```yaml
name: Contacts
version: 1

Contact:
  name: string
  email?: string
  phone?: string
  company?: string
  role?: string
  met?: date
  birthday?: date
  location?: string
  tags?: [string]
  notes?: text
```

**`Contacts/alex-chen.md`**

```markdown
---
type: Contact
name: Alex Chen
email: alex@example.com
company: Acme Corp
role: Senior Developer
met: 2024-03-15
location: Kuala Lumpur
tags: [friend, developer, coffee]
---

Met Alex at a dev conference in KL. Works on developer tools at Acme.
Great taste in coffee shops — he introduced me to Feeka.

Interested in local-first software and data ownership.
Always pushing back on my ideas, which makes them better.
```

### Habits App

**`Habits/_schema.yaml`**

```yaml
name: Habits
version: 1

Habit:
  name: string
  frequency: daily | weekly
  time?: morning | afternoon | evening
  streak?: number
  notes?: text

HabitLog:
  date: date
  habit: -> Habit
  done: boolean
  note?: string
```

**`Habits/habits/meditation.md`**

```markdown
---
type: Habit
name: Meditation
frequency: daily
time: morning
streak: 12
---

10 minutes minimum. Use the Waking Up app or just sit quietly.
```

**`Habits/habits/exercise.md`**

```markdown
---
type: Habit
name: Exercise
frequency: daily
time: afternoon
streak: 3
---

Any movement counts. Run, gym, swim, or a long walk.
```

**`Habits/logs/2026-02.md`**

```markdown
---
type: HabitLogMonth
month: 2026-02
---

| date | habit | done | note |
|------|-------|------|------|
| 2026-02-13 | [[habits/meditation]] | true | 15 min, felt clear after |
| 2026-02-13 | [[habits/exercise]] | true | 5k run at KLCC park |
| 2026-02-12 | [[habits/meditation]] | true | 10 min |
| 2026-02-12 | [[habits/exercise]] | false | Too tired, skipped |
| 2026-02-11 | [[habits/meditation]] | true | 10 min |
| 2026-02-11 | [[habits/exercise]] | true | Gym, upper body |
```

### Cross-App Intelligence

An agent reading this data can correlate across apps without any integration:

> **Agent reads:** Journal/2026-02-13.md mentions coffee with Alex Chen → follows `[[Contacts/alex-chen]]` → gets full context on who Alex is → checks Budget/transactions/2026-02.md → finds the RM4.50 at Feeka Coffee → connects the dots.

> **Agent reads:** Journal/2026-02-12.md mentions RM89 at Jaya Grocer → cross-references Budget → confirms the transaction → notices the "track food spending" comment → can proactively analyze food category trends.

> **Agent reads:** Habits/logs/2026-02.md shows exercise skipped on 2026-02-12 → Journal for that day says "made laksa" → mood was "happy" → pattern: rest days correlate with cooking days and good mood.

The filesystem IS the integration layer. File paths ARE the foreign keys. The agent IS the query engine. No APIs, no protocols, no middleware.

---

## FAQ / Design Decisions

### Why markdown and not a custom format?

Because markdown already won. Every text editor opens it. Every AI model reads it natively. Every developer knows it. GitHub renders it. Obsidian is built on it. Creating a new format means starting at zero adoption. Using markdown means starting at universal adoption.

### Why YAML schemas and not JSON Schema?

JSON Schema is more expressive but less readable. A developer can glance at an AppMD schema and understand the data model in 10 seconds:

```yaml
Transaction:
  date: date
  amount: number
  category: food | transport | groceries
  merchant?: string
```

The equivalent JSON Schema is 30+ lines of boilerplate. AppMD schemas are documentation and type definitions in one file. A human reads them as docs. An agent reads them as specs. Tooling reads them as validation rules.

### Why `_schema.yaml` and not `_schema.md`?

The schema is meant to be parsed by tools, not rendered as a document. YAML is the natural choice for structured configuration. The data files are markdown (for humans). The schema files are YAML (for machines and humans both).

### Why wiki links for relationships?

Wiki links (`[[path/to/entity]]`) are already a convention in Obsidian, Notion, and the broader PKM ecosystem. They're concise, readable, and unambiguous. They're also easy to parse — regex `\[\[(.+?)\]\]` extracts every reference in a file.

### What about performance with thousands of records?

The three-tier query model handles this. For small datasets (under ~1000 records), file scanning is fast enough. For larger datasets, the CLI tool or SDK maintains a derived SQLite index — same pattern Obsidian uses for hundreds of thousands of notes. The index is always derived from files, always deletable, always rebuildable.

### What about concurrent writes?

For most personal apps, this isn't an issue — one user, one device. Atomic file writes (write to temp, rename over original) guarantee that files are never half-written — corruption is impossible. When an agent and app write to different files simultaneously, there's no conflict at all. When both touch the same file, the app's in-memory state wins — the agent can redo its work when the file is no longer being edited. Smart agents already check file modification times before writing (the same pattern Claude Code uses). No coordination engine, no file locking, no merge logic required.

### What about schema evolution?

Add new optional fields freely — old files without the field are still valid. Add new required fields with a default value. Migration is just file processing — a script that reads files and adds the new field. Since it's all text, `sed` works. Since it's all markdown, any LLM can do it.

### Why not SQLite as the source of truth?

Because you can't `cat` a SQLite database. You can't `grep` it. You can't open it in a text editor. You can't diff it in git. You can't read it on a computer from 2060. SQLite is an excellent derived cache — fast, reliable, battle-tested. But the source of truth should be the format that survives everything: plain text.

### What about apps that need real databases?

AppMD is for personal data — journals, budgets, contacts, habits, health logs, notes. Data that belongs to the user and should outlast any app. Enterprise software, multiplayer games, and social networks have different requirements. AppMD doesn't try to replace PostgreSQL. It replaces the opaque SQLite databases that personal apps create in `~/Library/Application Support/`.

### Can I use this with Obsidian?

Yes. AppMD files are valid markdown with YAML frontmatter — exactly what Obsidian expects. Point an Obsidian vault at your AppMD directory and it works. The wiki links resolve. The frontmatter displays as properties. The files render as documents. You can use Obsidian as a viewer and editor for any AppMD data.

---

## Privacy Model

AppMD is private by architecture, not by feature. There is no cloud database to breach, no server to hack, no account to compromise. The data exists as files on the user's machine. That's the foundation — everything else is layered on top.

### Layer 1: Locality (Default)

Files live on the user's device. No cloud. No account. No server. Computation happens locally — AI agents read and write files on the same machine. The data never leaves the hardware unless the user explicitly moves it.

macOS FileVault (or equivalent full-disk encryption on other platforms) encrypts files at rest. This is already enabled on most modern machines. AppMD inherits this for free.

This layer covers the majority of users. "My data stays on my machine" is the pitch, and it's true by default.

### Layer 2: Selective Encryption (Opt-in)

Some data is more sensitive — health records, financial data, private journals. For these, AppMD supports per-app or per-folder encryption beyond what the OS provides.

Encrypted files are decrypted in memory by the app. On disk, they're opaque. A passphrase or biometric unlocks them. The schema and directory structure remain visible (so agents can discover what exists), but file contents are protected.

This layer uses standard encryption tools (`age`, macOS Keychain, or equivalent). No custom cryptography. No blockchain required.

### Layer 3: Encrypted Sharing (Future)

When users want to collaborate without sacrificing privacy — sharing a budget with an accountant, sending health data to a doctor — they need end-to-end encryption with identity.

This is where cryptographic identity systems (ENS, SNS, or simpler public-key schemes) become useful. Encrypt a file for a specific recipient's public key. They decrypt locally. No intermediary ever sees the plaintext.

This layer is opt-in, future work, and builds on the same file-based architecture. The files are still the source of truth — they're just encrypted before transmission and decrypted after receipt.

### The Principle

Privacy scales with need. Most users get full privacy from Layer 1 (locality) without thinking about it. Power users add Layer 2 (encryption) for sensitive data. Collaborators add Layer 3 (identity + sharing) when they need to work together securely. Each layer is independent and optional.

---

## Prior Art

AppMD stands on the shoulders of existing work:

- **Markdown** (John Gruber, 2004) — the insight that a text format should be readable as-is, without rendering. AppMD inherits this completely.
- **YAML frontmatter** (Jekyll, 2008) — the convention of structured metadata at the top of a markdown file. Now universal across static site generators, Obsidian, GitHub, and millions of files.
- **Obsidian** (Kepano / Steph Ango, 2020) — proved that markdown files with a derived index can be the foundation of a serious application used by millions. AppMD's architecture follows the same pattern.
- **File Over App** (Kepano, 2023) — the philosophical argument that files should outlast applications. AppMD is an implementation of this principle.
- **GNU Recutils** (Jose E. Marchesi) — a plain-text database with schemas, types, and queries. Solved the record-data problem elegantly. AppMD draws from its simplicity, while extending to handle documents and using markdown as the base format.
- **Obsidian Dataview** (Michael Brenan) — proved the demand for structured queries over plain text files. Its inline field syntax and query language showed what's possible when you treat markdown as data.
- **Markdoc** (Stripe, 2022) — demonstrated that markdown can be validated against schemas without losing readability.
- **TypeScript** (Microsoft, 2012) — the model for how to add structure to an existing format. TypeScript didn't replace JavaScript; it added types while remaining backwards compatible. AppMD follows the same superset strategy for markdown.
- **JSON Canvas** (Obsidian, 2024) — the naming convention. JSON Canvas = JSON for canvas data. AppMD = Markdown for application data.
- **llms.txt** (Jeremy Howard, 2024) — confirmed the industry convergence on markdown as the format for AI consumption.
- **Datasette** (Simon Willison) — demonstrated SQLite as a publishing and query format, validating the "derived index" approach.
- **Local-first software** (Ink & Switch, 2019) — the manifesto for software that works offline, syncs without servers, and gives users ownership. AppMD is local-first by default.
- **Personal Private Programmable** (Balaji Srinivasan, 2026) — the thesis that local AI + local files + crypto wallets create a stack where personal data becomes more programmable (computed on locally by AI) and more private (never leaves your machine). AppMD is the data layer that makes this concrete — structured files that agents read natively, on your machine, no cloud required.
- **"Golden age of local apps"** (Balaji Srinivasan, 2026) — the observation that Claude Code can clone any moderately complex cloud app into a local one that runs on only your files. An update to Kepano's "file over app": apps are suddenly portable too. AppMD provides the standard that makes these local apps interoperable — same files, different apps, shared agent access.

---

*AppMD is not a new idea. It's the inevitable convergence of ideas that already won — markdown's readability, TypeScript's progressive types, Obsidian's files-as-truth, and the Unix philosophy of simple tools that compose. The only new thing is writing it down.*
