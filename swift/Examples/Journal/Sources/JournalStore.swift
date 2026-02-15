import Foundation
import SwiftUI
import AppMDKit
import GRDB
import Combine

// MARK: - Journal Entry Model

struct JournalEntry: Identifiable, Equatable {
    let id: String  // relative file path
    var date: Date
    var mood: String?
    var tags: [String]
    var body: String

    /// The filename (without extension) used for display.
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    /// Short date string for sidebar.
    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Create from a GRDB Row.
    init(row: Row) {
        self.id = row["_path"] as? String ?? ""

        // Parse date from string
        let dateStr = row["date"] as? String ?? ""
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.date = formatter.date(from: dateStr) ?? Date()

        self.mood = row["mood"] as? String
        self.body = row["_body"] as? String ?? ""

        // Parse tags from JSON array or string
        if let tagsStr = row["tags"] as? String {
            if tagsStr.hasPrefix("[") {
                // JSON array
                if let data = tagsStr.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    self.tags = arr
                } else {
                    self.tags = []
                }
            } else {
                self.tags = tagsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        } else {
            self.tags = []
        }
    }

    /// Create a new entry.
    init(date: Date, mood: String? = nil, tags: [String] = [], body: String = "") {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)
        self.id = "\(dateStr).md"
        self.date = date
        self.mood = mood
        self.tags = tags
        self.body = body
    }

    /// Convert to an AppMDDocument for writing.
    func toDocument() -> AppMDDocument {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)

        var frontmatter: [String: Any] = [
            "type": "Entry",
            "date": dateStr,
        ]

        if let mood = mood, !mood.isEmpty {
            frontmatter["mood"] = mood
        }

        if !tags.isEmpty {
            frontmatter["tags"] = tags
        }

        return AppMDDocument(frontmatter: frontmatter, body: "\n" + body + "\n")
    }
}

// MARK: - Journal Store

/// The main data store for the Journal demo app.
/// Wraps AppMDStore and provides a SwiftUI-friendly interface.
final class JournalStore: ObservableObject {
    @Published var entries: [JournalEntry] = []
    @Published var error: String?
    @Published var isLoaded: Bool = false

    private var appmdStore: AppMDStore?
    private var observation: AnyDatabaseCancellable?

    static let journalURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Agentic/Journal", isDirectory: true)
    }()

    static let moods = ["happy", "sad", "neutral", "focused", "anxious", "grateful"]

    init() {
        loadStore()
    }

    private func loadStore() {
        do {
            let url = Self.journalURL

            // Ensure directory exists
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

            // Ensure schema exists
            let schemaURL = url.appendingPathComponent("_schema.yaml")
            if !FileManager.default.fileExists(atPath: schemaURL.path) {
                let schemaContent = """
                name: Journal
                version: 1

                Entry:
                  date: date
                  mood?: happy | sad | neutral | focused | anxious | grateful
                  tags?: [string]
                  body: text
                """
                try schemaContent.write(to: schemaURL, atomically: true, encoding: .utf8)
            }

            let store = try AppMDStore(rootURL: url)
            self.appmdStore = store

            // Set up reactive observation via GRDB ValueObservation
            let query = AppMDQuery(type: "Entry").sort(by: "date", descending: true)
            let observation = AppMDObservation.observe(query: query, in: store.database)

            self.observation = observation.start(in: store.database, onError: { [weak self] error in
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }, onChange: { [weak self] rows in
                DispatchQueue.main.async {
                    self?.entries = rows.map { JournalEntry(row: $0) }
                    self?.isLoaded = true
                }
            })

            // Also listen for external file changes
            store.onExternalChange = { [weak self] urls in
                // The GRDB ValueObservation handles UI updates automatically
                // This is just for any additional side effects
                _ = self
            }

        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - CRUD Operations

    /// Create a new journal entry.
    func createEntry(date: Date, mood: String?, tags: [String], body: String) {
        guard let store = appmdStore else { return }

        let entry = JournalEntry(date: date, mood: mood, tags: tags, body: body)
        let document = entry.toDocument()
        let relativePath = entry.id

        do {
            try store.writeDocument(document, to: relativePath)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Update an existing journal entry.
    func updateEntry(_ entry: JournalEntry) {
        guard let store = appmdStore else { return }

        let document = entry.toDocument()

        do {
            try store.writeDocument(document, to: entry.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Delete a journal entry (move to trash).
    func deleteEntry(_ entry: JournalEntry) {
        guard let store = appmdStore else { return }

        do {
            try store.deleteDocument(at: entry.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Full-text search across entries.
    func search(_ query: String) -> [JournalEntry] {
        guard let store = appmdStore, !query.isEmpty else { return entries }

        do {
            let results = try store.search(query, type: "Entry")
            let matchingPaths = Set(results.map { $0.path })
            return entries.filter { matchingPaths.contains($0.id) }
        } catch {
            self.error = error.localizedDescription
            return entries
        }
    }

    /// Filter entries by mood.
    func filterByMood(_ mood: String?) -> [JournalEntry] {
        guard let mood = mood, !mood.isEmpty else { return entries }
        return entries.filter { $0.mood == mood }
    }

    /// Filter entries by tag.
    func filterByTag(_ tag: String) -> [JournalEntry] {
        return entries.filter { $0.tags.contains(tag) }
    }

    /// Get all unique tags across all entries.
    var allTags: [String] {
        let all = entries.flatMap { $0.tags }
        return Array(Set(all)).sorted()
    }
}
