import Foundation
import GRDB

// MARK: - AppMD Index

/// The GRDB-backed index for an AppMD app directory.
/// Scans markdown files, parses frontmatter, and populates a SQLite database.
/// The database lives in `.cache/` and is always deletable/rebuildable.
public final class AppMDIndex: @unchecked Sendable {
    /// The root directory of the AppMD app (where .md files and _schema.yaml live).
    public let rootURL: URL

    /// The schema for this app.
    public let schema: AppMDSchema

    /// The GRDB database queue.
    public let dbQueue: DatabaseQueue

    /// Path to the cache directory.
    public let cacheURL: URL

    /// Tracks hashes of files we wrote, to ignore FSEvents bounce-back.
    private var writtenHashes: [String: String] = [:] // path -> hash
    private let hashLock = NSLock()

    /// Callback invoked when the index is updated.
    public var onIndexUpdated: (() -> Void)?

    // MARK: - Init

    /// Initialize the index for an app directory.
    /// Creates the .cache directory and GRDB database, then performs initial scan.
    public init(rootURL: URL, schema: AppMDSchema) throws {
        self.rootURL = rootURL
        self.schema = schema

        // Create .cache directory
        let cacheDir = rootURL.appendingPathComponent(".cache", isDirectory: true)
        self.cacheURL = cacheDir
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Create GRDB database with WAL mode for concurrent read/write safety
        let dbPath = cacheDir.appendingPathComponent("index.sqlite").path
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL")
        }
        self.dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

        // Create tables from schema
        try createTables()

        // Create FTS table for full-text search
        try createFTSTable()
    }

    // MARK: - Table Creation

    private func createTables() throws {
        try dbQueue.write { db in
            // Metadata table to track file modification times
            try db.create(table: "_files", ifNotExists: true) { t in
                t.primaryKey("path", .text).notNull()
                t.column("type", .text)
                t.column("modified", .double) // file modification date as timeInterval
                t.column("hash", .text)
            }

            // Create a table for each type in the schema
            for (typeName, typeDef) in schema.types {
                let tableName = tableName(for: typeName)
                try db.create(table: tableName, ifNotExists: true) { t in
                    t.primaryKey("_path", .text).notNull()
                    t.column("_modified", .double)

                    for field in typeDef.fields {
                        let colType: Database.ColumnType
                        switch field.type {
                        case .number:
                            colType = .real
                        case .boolean:
                            colType = .boolean
                        default:
                            colType = .text
                        }

                        if field.isOptional || field.defaultValue != nil {
                            t.column(field.name, colType)
                        } else {
                            t.column(field.name, colType)
                        }
                    }

                    // Store the body text for full-text search
                    t.column("_body", .text)
                }
            }
        }
    }

    private func createFTSTable() throws {
        try dbQueue.write { db in
            // Full-text search virtual table
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS _fts USING fts5(
                    path,
                    type,
                    body,
                    content='',
                    tokenize='porter unicode61'
                )
            """)
        }
    }

    // MARK: - Full Index Rebuild

    /// Perform a full scan of all .md files and rebuild the index.
    /// Uses a single GRDB transaction for all files (batch indexing).
    public func rebuildIndex() throws {
        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var files: [(URL, Date)] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            guard url.lastPathComponent != "_schema.yaml" else { continue }

            let attrs = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard attrs.isRegularFile == true else { continue }

            let modified = attrs.contentModificationDate ?? Date.distantPast
            files.append((url, modified))
        }

        // Batch: parse all files first, then write to DB in a single transaction
        var parsed: [(AppMDDocument, URL, Date, String)] = [] // (doc, url, modified, hash)
        for (fileURL, modified) in files {
            do {
                let document = try FileEngine.parse(fileAt: fileURL)
                let contentData = try Data(contentsOf: fileURL)
                let hash = FileEngine.sha256(contentData)
                parsed.append((document, fileURL, modified, hash))
            } catch {
                FileEngine.logWarning("Skipping file \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        try dbQueue.write { db in
            for (document, fileURL, modified, hash) in parsed {
                let relativePath = self.relativePath(for: fileURL)
                try self.insertFileRecord(db: db, document: document, relativePath: relativePath, modified: modified, hash: hash)
            }
        }

        // Remove stale entries for files that no longer exist on disk
        try cleanupDeletedFiles()
    }

    // MARK: - Incremental Index

    /// Re-index only files that have been modified since last index.
    /// Uses a single GRDB transaction for all changed files (batch indexing).
    public func incrementalSync() throws {
        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        // First pass: collect files that need re-indexing (read transaction)
        var filesToIndex: [(URL, Date)] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }

            let attrs = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard attrs.isRegularFile == true else { continue }

            let modified = attrs.contentModificationDate ?? Date.distantPast
            let relativePath = self.relativePath(for: url)

            // Check if file is already indexed with same modification date
            let existingModified = try dbQueue.read { db -> Double? in
                try Double.fetchOne(db, sql: "SELECT modified FROM _files WHERE path = ?", arguments: [relativePath])
            }

            if let existing = existingModified, existing >= modified.timeIntervalSince1970 {
                continue // Already up to date
            }

            filesToIndex.append((url, modified))
        }

        // Second pass: parse all changed files outside the transaction
        if !filesToIndex.isEmpty {
            var parsed: [(AppMDDocument, URL, Date, String)] = []
            for (fileURL, modified) in filesToIndex {
                do {
                    let document = try FileEngine.parse(fileAt: fileURL)
                    let contentData = try Data(contentsOf: fileURL)
                    let hash = FileEngine.sha256(contentData)
                    parsed.append((document, fileURL, modified, hash))
                } catch {
                    FileEngine.logWarning("Skipping file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }

            // Single write transaction for all changed files
            try dbQueue.write { db in
                for (document, fileURL, modified, hash) in parsed {
                    let relativePath = self.relativePath(for: fileURL)
                    try self.insertFileRecord(db: db, document: document, relativePath: relativePath, modified: modified, hash: hash)
                }
            }
        }

        // Clean up deleted files
        try cleanupDeletedFiles()
    }

    // MARK: - Index Single File

    /// Parse and index a single file (opens its own transaction).
    public func indexFile(at url: URL, modified: Date? = nil) throws {
        let document: AppMDDocument
        do {
            document = try FileEngine.parse(fileAt: url)
        } catch {
            FileEngine.logWarning("Skipping file \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }
        let relativePath = self.relativePath(for: url)

        let mod: Date
        if let modified = modified {
            mod = modified
        } else {
            let attrs = try url.resourceValues(forKeys: [.contentModificationDateKey])
            mod = attrs.contentModificationDate ?? Date()
        }

        let contentData = try Data(contentsOf: url)
        let hash = FileEngine.sha256(contentData)

        try dbQueue.write { db in
            try self.insertFileRecord(db: db, document: document, relativePath: relativePath, modified: mod, hash: hash)
        }
    }

    /// Insert/update a file record within an existing database transaction.
    /// Shared by `indexFile`, `rebuildIndex`, and `incrementalSync` for batch operations.
    func insertFileRecord(db: Database, document: AppMDDocument, relativePath: String, modified: Date, hash: String) throws {
        // Update _files table
        try db.execute(
            sql: "INSERT OR REPLACE INTO _files (path, type, modified, hash) VALUES (?, ?, ?, ?)",
            arguments: [relativePath, document.type, modified.timeIntervalSince1970, hash]
        )

        // Insert into type-specific table
        if let typeName = document.type, let typeDef = schema.types[typeName] {
            let table = tableName(for: typeName)

            // Build column names and values
            var columns = ["_path", "_modified", "_body"]
            var placeholders = ["?", "?", "?"]
            var values: [DatabaseValueConvertible?] = [
                relativePath,
                modified.timeIntervalSince1970,
                document.body.trimmingCharacters(in: .whitespacesAndNewlines)
            ]

            for field in typeDef.fields {
                if field.type == .text { continue } // body is already handled

                columns.append(field.name)
                placeholders.append("?")

                if let value = document.frontmatter[field.name] {
                    values.append(fieldToDBValue(value, type: field.type))
                } else if let defaultValue = field.defaultValue {
                    values.append(defaultValue)
                } else {
                    values.append(nil as String?)
                }
            }

            let sql = "INSERT OR REPLACE INTO `\(table)` (\(columns.joined(separator: ", "))) VALUES (\(placeholders.joined(separator: ", ")))"
            try db.execute(sql: sql, arguments: StatementArguments(values))
        }

        // Update FTS index — contentless FTS5 tables don't support REPLACE,
        // so we delete first then insert
        try db.execute(
            sql: "DELETE FROM _fts WHERE path = ?",
            arguments: [relativePath]
        )
        try db.execute(
            sql: "INSERT INTO _fts (path, type, body) VALUES (?, ?, ?)",
            arguments: [relativePath, document.type, document.body]
        )
    }

    /// Remove a file from the index.
    public func removeFile(at url: URL) throws {
        let relativePath = self.relativePath(for: url)

        try dbQueue.write { db in
            // Get file type before deleting
            let type = try String.fetchOne(db, sql: "SELECT type FROM _files WHERE path = ?", arguments: [relativePath])

            // Remove from _files
            try db.execute(sql: "DELETE FROM _files WHERE path = ?", arguments: [relativePath])

            // Remove from type table
            if let typeName = type {
                let table = tableName(for: typeName)
                try db.execute(sql: "DELETE FROM `\(table)` WHERE _path = ?", arguments: [relativePath])
            }

            // Remove from FTS
            // FTS5 content='' tables need special handling
            try db.execute(sql: "DELETE FROM _fts WHERE path = ?", arguments: [relativePath])
        }
    }

    // MARK: - Hash Tracking (bounce-back prevention)

    /// Register a hash for a file we just wrote, so FSEvents can ignore it.
    public func registerWrittenHash(_ hash: String, for path: String) {
        hashLock.lock()
        defer { hashLock.unlock() }
        writtenHashes[path] = hash
    }

    /// Check if a file change was caused by our own write.
    /// Returns true if we wrote this exact content, and clears the hash.
    public func isOurWrite(for url: URL) -> Bool {
        let relativePath = self.relativePath(for: url)
        hashLock.lock()
        defer { hashLock.unlock() }

        guard let expectedHash = writtenHashes[relativePath] else { return false }

        // Compute current file hash
        guard let data = try? Data(contentsOf: url) else { return false }
        let currentHash = FileEngine.sha256(data)

        if currentHash == expectedHash {
            writtenHashes.removeValue(forKey: relativePath)
            return true
        }

        return false
    }

    // MARK: - Query Helpers

    /// The GRDB database queue for direct queries.
    public var database: DatabaseQueue { dbQueue }

    /// Full-text search across all indexed files.
    public func search(_ query: String) throws -> [(path: String, type: String?, snippet: String)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT _fts.path, _fts.type, snippet(_fts, 2, '<b>', '</b>', '...', 32) as snippet
                FROM _fts
                WHERE _fts MATCH ?
                ORDER BY rank
            """, arguments: [query])

            return rows.map { row in
                (
                    path: row["path"] as String,
                    type: row["type"] as String?,
                    snippet: row["snippet"] as? String ?? ""
                )
            }
        }
    }

    // MARK: - Write Through Index

    /// Write a document and update the index. Handles atomic write + hash tracking.
    public func writeDocument(_ document: AppMDDocument, to url: URL) throws {
        let hash = try FileEngine.atomicWrite(document: document, to: url)
        let relativePath = self.relativePath(for: url)
        registerWrittenHash(hash, for: relativePath)
        try indexFile(at: url, modified: Date())
    }

    // MARK: - Position Rebalancing

    /// Rebalance position values for items of a given type, optionally filtered.
    /// Reassigns positions to clean integers (1.0, 2.0, 3.0, ...) while preserving order.
    /// - Parameters:
    ///   - typeName: The schema type to rebalance (e.g., "Card")
    ///   - positionField: The field name containing the position value (default: "position")
    ///   - filterField: Optional field to filter by (e.g., "column")
    ///   - filterValue: Value to match for the filter field
    /// - Returns: Number of items rebalanced
    @discardableResult
    public func rebalancePositions(
        type typeName: String,
        positionField: String = "position",
        filterField: String? = nil,
        filterValue: String? = nil
    ) throws -> Int {
        let table = tableName(for: typeName)

        // Build query to get items sorted by current position
        var sql = "SELECT _path, \(positionField) FROM `\(table)`"
        var args: [DatabaseValueConvertible?] = []

        if let filterField = filterField, let filterValue = filterValue {
            sql += " WHERE \(filterField) = ?"
            args.append(filterValue)
        }

        sql += " ORDER BY \(positionField) ASC"

        let rows = try dbQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }

        guard !rows.isEmpty else { return 0 }

        var count = 0
        for (i, row) in rows.enumerated() {
            let path: String = row["_path"]
            let newPosition = Double(i + 1)

            // Read current position
            let currentPosition: Double? = row[positionField]
            if currentPosition == newPosition { continue } // Already clean

            // Read the file, update frontmatter, write back
            let url = absoluteURL(for: path)
            var document = try FileEngine.parse(fileAt: url)
            document.frontmatter[positionField] = newPosition
            try writeDocument(document, to: url)
            count += 1
        }

        return count
    }

    /// Check if positions in a group are too fragmented and need rebalancing.
    /// Returns true if any gap between consecutive positions is smaller than `threshold`.
    public func needsRebalancing(
        type typeName: String,
        positionField: String = "position",
        filterField: String? = nil,
        filterValue: String? = nil,
        threshold: Double = 0.001
    ) throws -> Bool {
        let table = tableName(for: typeName)

        var sql = "SELECT \(positionField) FROM `\(table)`"
        var args: [DatabaseValueConvertible?] = []

        if let filterField = filterField, let filterValue = filterValue {
            sql += " WHERE \(filterField) = ?"
            args.append(filterValue)
        }

        sql += " ORDER BY \(positionField) ASC"

        let positions: [Double] = try dbQueue.read { db in
            try Double.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }

        guard positions.count >= 2 else { return false }

        for i in 1..<positions.count {
            let gap = positions[i] - positions[i - 1]
            if gap < threshold {
                return true
            }
        }

        return false
    }

    // MARK: - Helpers

    /// Get the relative path of a file URL from the root directory.
    /// Uses case-insensitive comparison for APFS compatibility.
    public func relativePath(for url: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path.lowercased()
        let filePath = url.standardizedFileURL.path
        let filePathLower = filePath.lowercased()
        if filePathLower.hasPrefix(rootPath) {
            var rel = String(filePath.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
            return rel
        }
        return url.lastPathComponent
    }

    /// Get the absolute URL for a relative path.
    public func absoluteURL(for relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }

    /// Get the table name for a type.
    func tableName(for typeName: String) -> String {
        typeName.lowercased()
    }

    // MARK: - Private

    private func fieldToDBValue(_ value: Any, type: FieldType) -> DatabaseValueConvertible? {
        switch type {
        case .number:
            if let intVal = value as? Int { return Double(intVal) }
            if let dblVal = value as? Double { return dblVal }
            if let str = value as? String { return Double(str) }
            return nil
        case .boolean:
            if let boolVal = value as? Bool { return boolVal }
            return nil
        case .list, .listRelationship:
            // Store arrays as JSON
            if let arr = value as? [Any] {
                let strings = arr.map { "\($0)" }
                if let data = try? JSONSerialization.data(withJSONObject: strings),
                   let json = String(data: data, encoding: .utf8) {
                    return json
                }
            }
            return nil
        case .enum:
            return "\(value)"
        case .relationship:
            return "\(value)"
        default:
            return "\(value)"
        }
    }

    private func cleanupDeletedFiles() throws {
        let indexedPaths = try dbQueue.read { db -> [String] in
            try String.fetchAll(db, sql: "SELECT path FROM _files")
        }

        let fm = FileManager.default
        for path in indexedPaths {
            let url = absoluteURL(for: path)
            if !fm.fileExists(atPath: url.path) {
                try removeFile(at: url)
            }
        }
    }
}
