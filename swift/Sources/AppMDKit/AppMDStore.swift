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
