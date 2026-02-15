// AppMDKit — Application Markdown data layer
//
// AppMD uses standard markdown files with YAML frontmatter as the data layer
// for apps. Files are the source of truth. A derived SQLite index (via GRDB)
// makes queries fast. FSEvents detects external changes and keeps everything in sync.
//
// Main types:
//   - AppMDStore: The main entry point. Manages schema, index, watcher.
//   - AppMDDocument: A parsed markdown file (frontmatter + body).
//   - AppMDSchema: A parsed _schema.yaml file.
//   - AppMDIndex: The GRDB-backed index.
//   - AppMDQuery: Type-safe query builder.
//   - FSEventsWatcher: File system change detection.
//   - FileEngine: Low-level file parsing and atomic writes.

@_exported import GRDB
