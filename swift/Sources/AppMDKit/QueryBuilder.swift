import Foundation
import GRDB

// MARK: - Query Builder

/// A type-safe query builder over the GRDB index.
public struct AppMDQuery {
    let tableName: String
    var conditions: [(String, String, DatabaseValueConvertible?)] = [] // column, operator, value
    var sortColumn: String?
    var sortDescending: Bool = false
    var queryLimit: Int?
    var queryOffset: Int?

    public init(type typeName: String) {
        self.tableName = typeName.lowercased()
    }

    // MARK: - Filtering

    /// Filter where column equals value.
    public func `where`(_ column: String, equals value: DatabaseValueConvertible?) -> AppMDQuery {
        var copy = self
        copy.conditions.append((column, "=", value))
        return copy
    }

    /// Filter where column does not equal value.
    public func `where`(_ column: String, notEquals value: DatabaseValueConvertible?) -> AppMDQuery {
        var copy = self
        copy.conditions.append((column, "!=", value))
        return copy
    }

    /// Filter where column is less than value.
    public func `where`(_ column: String, lessThan value: DatabaseValueConvertible?) -> AppMDQuery {
        var copy = self
        copy.conditions.append((column, "<", value))
        return copy
    }

    /// Filter where column is greater than value.
    public func `where`(_ column: String, greaterThan value: DatabaseValueConvertible?) -> AppMDQuery {
        var copy = self
        copy.conditions.append((column, ">", value))
        return copy
    }

    /// Filter where column LIKE pattern.
    public func `where`(_ column: String, like pattern: String) -> AppMDQuery {
        var copy = self
        copy.conditions.append((column, "LIKE", pattern))
        return copy
    }

    /// Filter where column contains a value (for JSON arrays stored as text).
    public func `where`(_ column: String, contains value: String) -> AppMDQuery {
        var copy = self
        copy.conditions.append((column, "LIKE", "%\(value)%"))
        return copy
    }

    /// Filter where column is NULL.
    public func whereNull(_ column: String) -> AppMDQuery {
        var copy = self
        copy.conditions.append((column, "IS", nil))
        return copy
    }

    /// Filter where column is NOT NULL.
    public func whereNotNull(_ column: String) -> AppMDQuery {
        var copy = self
        copy.conditions.append((column, "IS NOT", nil))
        return copy
    }

    // MARK: - Sorting

    /// Sort by column ascending.
    public func sort(by column: String, descending: Bool = false) -> AppMDQuery {
        var copy = self
        copy.sortColumn = column
        copy.sortDescending = descending
        return copy
    }

    // MARK: - Limiting

    /// Limit the number of results.
    public func limit(_ count: Int) -> AppMDQuery {
        var copy = self
        copy.queryLimit = count
        return copy
    }

    /// Offset results (for pagination).
    public func offset(_ count: Int) -> AppMDQuery {
        var copy = self
        copy.queryOffset = count
        return copy
    }

    // MARK: - Execution

    /// Build the SQL query and arguments.
    public func buildSQL() -> (String, StatementArguments) {
        var sql = "SELECT * FROM \(tableName)"
        var args: [DatabaseValueConvertible?] = []

        if !conditions.isEmpty {
            var whereClauses: [String] = []
            for (column, op, value) in conditions {
                if value == nil {
                    whereClauses.append("\(column) \(op) NULL")
                } else {
                    whereClauses.append("\(column) \(op) ?")
                    args.append(value)
                }
            }
            sql += " WHERE " + whereClauses.joined(separator: " AND ")
        }

        if let sortColumn = sortColumn {
            sql += " ORDER BY \(sortColumn)"
            if sortDescending {
                sql += " DESC"
            }
        }

        if let limit = queryLimit {
            sql += " LIMIT \(limit)"
        }

        if let offset = queryOffset {
            sql += " OFFSET \(offset)"
        }

        return (sql, StatementArguments(args))
    }

    /// Execute the query and return rows.
    public func fetch(from db: Database) throws -> [Row] {
        let (sql, args) = buildSQL()
        return try Row.fetchAll(db, sql: sql, arguments: args)
    }

    /// Execute the query on a database queue and return rows.
    public func fetch(from dbQueue: DatabaseQueue) throws -> [Row] {
        try dbQueue.read { db in
            try fetch(from: db)
        }
    }

    /// Execute the query and return the count.
    public func count(from db: Database) throws -> Int {
        var sql = "SELECT COUNT(*) FROM \(tableName)"
        var args: [DatabaseValueConvertible?] = []

        if !conditions.isEmpty {
            var whereClauses: [String] = []
            for (column, op, value) in conditions {
                if value == nil {
                    whereClauses.append("\(column) \(op) NULL")
                } else {
                    whereClauses.append("\(column) \(op) ?")
                    args.append(value)
                }
            }
            sql += " WHERE " + whereClauses.joined(separator: " AND ")
        }

        return try Int.fetchOne(db, sql: sql, arguments: StatementArguments(args)) ?? 0
    }
}

// MARK: - Reactive Observation

/// Provides GRDB ValueObservation-based reactive queries for SwiftUI.
public struct AppMDObservation {

    /// Create a ValueObservation that watches for changes to a query.
    public static func observe(
        query: AppMDQuery,
        in dbQueue: DatabaseQueue
    ) -> ValueObservation<ValueReducers.Fetch<[Row]>> {
        let (sql, args) = query.buildSQL()
        return ValueObservation.tracking { db in
            try Row.fetchAll(db, sql: sql, arguments: args)
        }
    }

    /// Create a ValueObservation that watches a specific table for all rows.
    public static func observeAll(
        type typeName: String,
        sortBy column: String? = nil,
        descending: Bool = false,
        in dbQueue: DatabaseQueue
    ) -> ValueObservation<ValueReducers.Fetch<[Row]>> {
        var query = AppMDQuery(type: typeName)
        if let column = column {
            query = query.sort(by: column, descending: descending)
        }
        return observe(query: query, in: dbQueue)
    }
}

// MARK: - Full-Text Search Query

public struct AppMDSearchQuery {
    let searchText: String
    let typeName: String?

    public init(text: String, type: String? = nil) {
        self.searchText = text
        self.typeName = type
    }

    /// Execute the search and return matching paths with snippets.
    public func execute(on dbQueue: DatabaseQueue) throws -> [(path: String, type: String?, snippet: String)] {
        try dbQueue.read { db in
            // Escape the search text for FTS5
            let ftsQuery = searchText
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { "\($0)*" }
                .joined(separator: " ")

            var sql = """
                SELECT path, type, snippet(_fts, 2, '', '', '...', 48) as snippet
                FROM _fts
                WHERE _fts MATCH ?
            """
            var args: [DatabaseValueConvertible] = [ftsQuery]

            if let typeName = typeName {
                sql += " AND type = ?"
                args.append(typeName)
            }

            sql += " ORDER BY rank"

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map { row in
                (
                    path: row["path"] as String,
                    type: row["type"] as String?,
                    snippet: row["snippet"] as? String ?? ""
                )
            }
        }
    }
}
