import Foundation
import GRDB

// MARK: - AppMDModel Protocol

/// The core protocol for typed AppMD models.
///
/// Conforming types get typed queries, observations, and round-trip safe
/// file persistence — all backed by GRDB's native infrastructure.
///
/// Conform manually or let the AppMD build plugin generate conformance
/// from `_schema.yaml`.
///
/// ```swift
/// struct Card: AppMDModel {
///     static let typeName = "Card"
///     let _path: String
///     let _body: String
///     var _source: AppMDDocument?
///     var title: String
///     var column: Ref<KanbanColumn>
///     var position: Double
/// }
/// ```
public protocol AppMDModel: FetchableRecord, Sendable, Identifiable, Equatable where ID == String {

    /// The schema type name (e.g. "Card", "Entry"). Must match the type
    /// key in `_schema.yaml` and the frontmatter `type:` field.
    static var typeName: String { get }

    /// The GRDB table name. Defaults to `typeName.lowercased()`.
    static var databaseTableName: String { get }

    /// Relative file path (e.g. "cards/my-card-abc123.md").
    /// Also serves as the stable identity.
    var _path: String { get }

    /// Markdown body content (everything below the frontmatter).
    var _body: String { get }

    /// The original document, preserved for round-trip fidelity.
    /// When saving, typed fields are merged on top of this so unknown
    /// frontmatter keys are never lost.
    var _source: AppMDDocument? { get }

    /// Serialize the model's typed fields into frontmatter.
    /// The `type` key is injected automatically — don't include it.
    /// If `_source` is set, the returned document should merge typed
    /// fields on top of `_source.frontmatter` to preserve unknown keys.
    func toDocument() -> AppMDDocument
}

// MARK: - Defaults

public extension AppMDModel {

    /// Default table name: typeName lowercased.
    static var databaseTableName: String {
        typeName.lowercased()
    }

    /// Identity is the file path.
    var id: String { _path }

    /// Default equality: two models are equal if they have the same file path.
    /// Override in your type if you need value-level equality.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs._path == rhs._path
    }

    /// Builds the final document with `type` injected and unknown keys preserved.
    /// Call this from `toDocument()` implementations instead of building from scratch.
    func buildDocument(fields: [String: Any], body: String? = nil) -> AppMDDocument {
        // Start with source frontmatter to preserve unknown keys
        var fm = _source?.frontmatter ?? [:]

        // Merge typed fields on top
        for (key, value) in fields {
            fm[key] = value
        }

        // Always inject type
        fm["type"] = Self.typeName

        return AppMDDocument(
            frontmatter: fm,
            body: body ?? _body
        )
    }
}

// MARK: - Ref<T> (Typed Wiki-Link Reference)

/// A typed reference to another AppMD model, stored as a wiki-link
/// (e.g. `[[columns/todo]]`) in frontmatter.
///
/// ```swift
/// struct Card: AppMDModel {
///     var column: Ref<KanbanColumn>
///     // ...
/// }
///
/// // Resolve the reference:
/// let col = try card.column.resolve(in: store)
/// ```
public struct Ref<T: AppMDModel>: Sendable, Equatable, Hashable {

    /// The raw wiki-link string as stored in frontmatter (e.g. "[[columns/todo]]").
    public let rawValue: String

    /// The resolved file path (e.g. "columns/todo.md").
    public var path: String {
        var ref = rawValue
        // Strip wiki-link brackets
        if ref.hasPrefix("[[") && ref.hasSuffix("]]") {
            ref = String(ref.dropFirst(2).dropLast(2))
        }
        // Ensure .md extension
        if !ref.hasSuffix(".md") {
            ref += ".md"
        }
        return ref
    }

    /// The wiki-link formatted string (e.g. "[[columns/todo]]").
    public var wikiLink: String {
        if rawValue.hasPrefix("[[") && rawValue.hasSuffix("]]") {
            return rawValue
        }
        var clean = rawValue
        if clean.hasSuffix(".md") {
            clean = String(clean.dropLast(3))
        }
        return "[[\(clean)]]"
    }

    // MARK: - Init

    /// Create from a raw string (wiki-link or path).
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Create from a file path, converting to wiki-link format.
    public static func path(_ filePath: String) -> Ref<T> {
        var clean = filePath
        if clean.hasSuffix(".md") {
            clean = String(clean.dropLast(3))
        }
        return Ref("[[\(clean)]]")
    }

    /// Create from a model instance.
    public static func to(_ model: T) -> Ref<T> {
        return .path(model._path)
    }

    // MARK: - Resolve

    /// Resolve this reference, returning nil if not found instead of throwing.
    public func resolveOptional(in store: AppMDStore) -> T? {
        try? resolve(in: store)
    }

    /// Resolve this reference to a typed model by reading from the store.
    public func resolve(in store: AppMDStore) throws -> T {
        let row = try store.database.read { db -> Row in
            let tableName = T.databaseTableName
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM `\(tableName)` WHERE `_path` = ?", arguments: [path]) else {
                throw RefError.notFound(path: path, type: T.typeName)
            }
            return row
        }
        return try T(row: row)
    }
}

// MARK: - Ref: DatabaseValueConvertible

/// Allows `Ref<T>` to be read directly from GRDB rows and used in query arguments.
extension Ref: DatabaseValueConvertible {

    public var databaseValue: DatabaseValue {
        rawValue.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Ref<T>? {
        guard let string = String.fromDatabaseValue(dbValue) else { return nil }
        return Ref(string)
    }
}

// MARK: - Ref Errors

public enum RefError: Error, LocalizedError {
    case notFound(path: String, type: String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let path, let type):
            return "Referenced \(type) not found at path: \(path)"
        }
    }
}

// MARK: - Row Decoding Helpers

/// Convenience helpers for decoding common AppMD field types from GRDB rows.
public enum AppMDDecode {

    /// Decode a JSON array stored as a text column.
    /// Returns an empty array if the column is nil or not valid JSON.
    ///
    /// ```swift
    /// self.tags = AppMDDecode.array(from: row, column: "tags")
    /// ```
    public static func array(from row: Row, column: String) -> [String] {
        guard let str = row[column] as? String,
              str.hasPrefix("["),
              let data = str.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return arr
    }

    /// Decode a JSON array of numbers stored as a text column.
    public static func numberArray(from row: Row, column: String) -> [Double] {
        guard let str = row[column] as? String,
              str.hasPrefix("["),
              let data = str.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Double] else {
            return []
        }
        return arr
    }

    /// Decode an ISO 8601 date string from a row column.
    /// Returns nil if the column is nil or the string isn't valid ISO 8601.
    ///
    /// ```swift
    /// self.created = AppMDDecode.date(from: row, column: "created")
    /// ```
    public static func date(from row: Row, column: String) -> Date? {
        guard let str = row[column] as? String else { return nil }
        return Self.dateFormatter.date(from: str)
            ?? Self.dateOnlyFormatter.date(from: str)
    }

    /// Decode a required ISO 8601 date, falling back to `.distantPast`.
    public static func dateOrDistantPast(from row: Row, column: String) -> Date {
        date(from: row, column: column) ?? .distantPast
    }

    /// Format a Date to ISO 8601 string for frontmatter.
    public static func encodeDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Format a Date to date-only string (YYYY-MM-DD) for frontmatter.
    public static func encodeDateOnly(_ date: Date) -> String {
        dateOnlyFormatter.string(from: date)
    }

    // MARK: - Formatters

    /// ISO 8601 with fractional seconds.
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Date-only formatter (YYYY-MM-DD).
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Encode a string array to JSON for frontmatter storage.
    public static func encodeArray(_ values: [String]) -> [String] {
        values // YAML arrays are native, no JSON encoding needed for frontmatter
    }
}
