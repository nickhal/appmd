import Foundation
import GRDB
import Combine

// MARK: - AppMDStore

/// The main entry point for AppMDKit. Manages an AppMD app directory:
/// schema, GRDB index, FSEvents watcher, and atomic writes.
///
/// Usage:
/// ```swift
/// let store = try AppMDStore(rootURL: journalURL)
/// ```
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
    @Published public var lastChangeDate: Date = Date()

    /// Callback when external files change.
    public var onExternalChange: (([URL]) -> Void)?

    // MARK: - Init

    /// Initialize a store for an AppMD app directory.
    /// Reads _schema.yaml, creates the GRDB index, performs initial scan, starts FSEvents watcher.
    public init(rootURL: URL) throws {
        self.rootURL = rootURL

        // Load schema
        let schemaURL = rootURL.appendingPathComponent("_schema.yaml")
        guard FileManager.default.fileExists(atPath: schemaURL.path) else {
            throw AppMDStoreError.schemaNotFound(schemaURL.path)
        }
        self.schema = try SchemaParser.parse(at: schemaURL)

        // Create index
        self.index = try AppMDIndex(rootURL: rootURL, schema: schema)

        // Create watcher
        self.watcher = FSEventsWatcher(watchURL: rootURL, index: index)

        // Perform initial index
        try index.rebuildIndex()

        // Set up watcher callbacks
        watcher.onChange = { [weak self] urls in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.lastChangeDate = Date()
                self.objectWillChange.send()
            }
            self.onExternalChange?(urls)
        }

        index.onIndexUpdated = { [weak self] in
            DispatchQueue.main.async {
                self?.lastChangeDate = Date()
                self?.objectWillChange.send()
            }
        }

        // Start watching
        watcher.start()
    }

    deinit {
        watcher.stop()
    }

    // MARK: - Read

    /// Read and parse a document at the given relative path.
    public func readDocument(at relativePath: String) throws -> AppMDDocument {
        let url = index.absoluteURL(for: relativePath)
        return try FileEngine.parse(fileAt: url)
    }

    /// Read and parse a document at the given URL.
    public func readDocument(at url: URL) throws -> AppMDDocument {
        return try FileEngine.parse(fileAt: url)
    }

    // MARK: - Write

    /// Write a document to the given relative path.
    /// Uses atomic write and updates the index.
    public func writeDocument(_ document: AppMDDocument, to relativePath: String) throws {
        let url = index.absoluteURL(for: relativePath)
        try index.writeDocument(document, to: url)
        DispatchQueue.main.async {
            self.lastChangeDate = Date()
            self.objectWillChange.send()
        }
    }

    /// Write a document to the given URL.
    public func writeDocument(_ document: AppMDDocument, to url: URL) throws {
        try index.writeDocument(document, to: url)
        DispatchQueue.main.async {
            self.lastChangeDate = Date()
            self.objectWillChange.send()
        }
    }

    // MARK: - Delete

    /// Delete a document (move to trash).
    public func deleteDocument(at relativePath: String) throws {
        let url = index.absoluteURL(for: relativePath)
        try FileEngine.moveToTrash(url: url)
        try index.removeFile(at: url)
        DispatchQueue.main.async {
            self.lastChangeDate = Date()
            self.objectWillChange.send()
        }
    }

    /// Delete a document by URL (move to trash).
    public func deleteDocument(at url: URL) throws {
        try FileEngine.moveToTrash(url: url)
        try index.removeFile(at: url)
        DispatchQueue.main.async {
            self.lastChangeDate = Date()
            self.objectWillChange.send()
        }
    }

    // MARK: - Query

    /// Create a query builder for a type.
    public func query(type: String) -> AppMDQuery {
        AppMDQuery(type: type)
    }

    /// Execute a query and return rows.
    public func fetch(query: AppMDQuery) throws -> [Row] {
        try query.fetch(from: index.dbQueue)
    }

    /// Full-text search across all documents.
    public func search(_ text: String, type: String? = nil) throws -> [(path: String, type: String?, snippet: String)] {
        let query = AppMDSearchQuery(text: text, type: type)
        return try query.execute(on: index.dbQueue)
    }

    /// Get a reactive observation for a query (for SwiftUI).
    public func observe(query: AppMDQuery) -> ValueObservation<ValueReducers.Fetch<[Row]>> {
        AppMDObservation.observe(query: query, in: index.dbQueue)
    }

    /// The underlying GRDB database queue for advanced queries.
    public var database: DatabaseQueue {
        index.dbQueue
    }

    // MARK: - Position Rebalancing

    /// Rebalance position values for items of a given type, optionally filtered.
    /// Reassigns positions to clean integers (1.0, 2.0, 3.0, ...) while preserving order.
    @discardableResult
    public func rebalancePositions(
        type typeName: String,
        positionField: String = "position",
        filterField: String? = nil,
        filterValue: String? = nil
    ) throws -> Int {
        let count = try index.rebalancePositions(
            type: typeName,
            positionField: positionField,
            filterField: filterField,
            filterValue: filterValue
        )
        if count > 0 {
            DispatchQueue.main.async {
                self.lastChangeDate = Date()
                self.objectWillChange.send()
            }
        }
        return count
    }

    /// Check if positions in a group are too fragmented and need rebalancing.
    public func needsRebalancing(
        type typeName: String,
        positionField: String = "position",
        filterField: String? = nil,
        filterValue: String? = nil,
        threshold: Double = 0.001
    ) throws -> Bool {
        try index.needsRebalancing(
            type: typeName,
            positionField: positionField,
            filterField: filterField,
            filterValue: filterValue,
            threshold: threshold
        )
    }

    // MARK: - Re-index

    /// Force a full re-index from files.
    public func rebuildIndex() throws {
        try index.rebuildIndex()
        DispatchQueue.main.async {
            self.lastChangeDate = Date()
            self.objectWillChange.send()
        }
    }

    /// Perform incremental sync (only re-index changed files).
    public func sync() throws {
        try index.incrementalSync()
    }
}

// MARK: - Typed Model API

public extension AppMDStore {

    /// Create a typed query for a model type.
    ///
    /// ```swift
    /// let cards: [Card] = try store.fetch(
    ///     store.query(Card.self)
    ///         .where("column", equals: colRef)
    ///         .sort(by: "position")
    /// )
    /// ```
    func query<T: AppMDModel>(_ type: T.Type) -> TypedQuery<T> {
        TypedQuery<T>()
    }

    /// Fetch all models matching a typed query.
    func fetch<T: AppMDModel>(_ query: TypedQuery<T>) throws -> [T] {
        try query.fetch(from: index.dbQueue)
    }

    /// Fetch a single model matching a typed query.
    func fetchOne<T: AppMDModel>(_ query: TypedQuery<T>) throws -> T? {
        try query.fetchOne(from: index.dbQueue)
    }

    /// Fetch all models of a type.
    func fetchAll<T: AppMDModel>(_ type: T.Type) throws -> [T] {
        try TypedQuery<T>().fetch(from: index.dbQueue)
    }

    /// Fetch a model by its file path.
    func fetchByPath<T: AppMDModel>(_ type: T.Type, path: String) throws -> T? {
        try index.dbQueue.read { db in
            try T.fetchOne(db, sql: "SELECT * FROM `\(T.databaseTableName)` WHERE `_path` = ?", arguments: [path])
        }
    }

    /// Save a model back to its markdown file.
    /// Merges typed fields on top of the original document to preserve unknown keys.
    func save<T: AppMDModel>(_ model: T) throws {
        let doc = model.toDocument()
        try writeDocument(doc, to: model._path)
    }

    /// Create a reactive observation for a typed query.
    /// Returns a GRDB `ValueObservation` that can be started for SwiftUI binding.
    ///
    /// ```swift
    /// let observation = store.observe(
    ///     store.query(Card.self).sort(by: "position")
    /// )
    /// cancellable = observation.start(in: store.database, onError: { ... }) { cards in
    ///     self.cards = cards
    /// }
    /// ```
    func observe<T: AppMDModel>(_ query: TypedQuery<T>) -> ValueObservation<ValueReducers.Fetch<[T]>> {
        query.observation()
    }

    /// Create a reactive observation for all models of a type.
    func observeAll<T: AppMDModel>(
        _ type: T.Type,
        sortBy column: String? = nil,
        descending: Bool = false
    ) -> ValueObservation<ValueReducers.Fetch<[T]>> {
        var q = TypedQuery<T>()
        if let column = column {
            q = q.sort(by: column, descending: descending)
        }
        return q.observation()
    }
}

// MARK: - Errors

public enum AppMDStoreError: Error, LocalizedError {
    case schemaNotFound(String)
    case typeNotFound(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .schemaNotFound(let path): return "Schema not found at: \(path)"
        case .typeNotFound(let name): return "Type not found in schema: \(name)"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }
}
