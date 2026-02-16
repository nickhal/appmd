import Foundation
import Yams

// MARK: - AppMD Document

/// Represents a parsed AppMD markdown file: YAML frontmatter + markdown body.
public struct AppMDDocument: @unchecked Sendable {
    /// The parsed YAML frontmatter as a dictionary.
    public var frontmatter: [String: Any]
    /// The markdown body content (everything below the frontmatter).
    public var body: String

    /// The `type` field from frontmatter, if present.
    public var type: String? {
        frontmatter["type"] as? String
    }

    public init(frontmatter: [String: Any] = [:], body: String = "") {
        self.frontmatter = frontmatter
        self.body = body
    }
}

// MARK: - File Engine

/// Handles reading, writing, and atomic file operations for AppMD files.
public enum FileEngine {

    // MARK: - Parsing

    /// Parse an AppMD markdown file into frontmatter + body.
    /// Supports `---` delimited YAML frontmatter.
    public static func parse(content: String) -> AppMDDocument {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("---") else {
            return AppMDDocument(frontmatter: [:], body: content)
        }

        // Find the closing ---
        let lines = content.components(separatedBy: "\n")
        var yamlLines: [String] = []
        var bodyStartIndex: Int? = nil

        // Skip the first line (opening ---)
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                bodyStartIndex = i + 1
                break
            }
            yamlLines.append(lines[i])
        }

        guard let startIdx = bodyStartIndex else {
            // No closing ---, treat entire content as body
            return AppMDDocument(frontmatter: [:], body: content)
        }

        let yamlString = yamlLines.joined(separator: "\n")
        let bodyLines = Array(lines[startIdx...])
        let body = bodyLines.joined(separator: "\n")

        // Parse YAML with safe bool handling
        // Yams (YAML 1.1) treats bare yes/no/on/off/true/false as booleans.
        // AppMD frontmatter expects these as strings when they appear as field values
        // (the "Norway problem"). We re-parse the raw YAML lines to detect this and
        // preserve the original string when Yams returns a Bool for a non-boolean-looking key.
        var frontmatter: [String: Any] = [:]
        if let parsed = try? Yams.load(yaml: yamlString) as? [String: Any] {
            frontmatter = normalizeBooleans(parsed: parsed, rawYAML: yamlString)
        }

        return AppMDDocument(frontmatter: frontmatter, body: body)
    }

    /// Parse a file at the given path.
    public static func parse(fileAt url: URL) throws -> AppMDDocument {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content: content)
    }

    // MARK: - Serialization

    /// Serialize an AppMDDocument back to a markdown string with YAML frontmatter.
    public static func serialize(_ document: AppMDDocument) -> String {
        var result = ""

        if !document.frontmatter.isEmpty {
            // Use Yams to dump the frontmatter, preserving order as best we can
            if let yamlString = try? Yams.dump(object: sortedForYAML(document.frontmatter),
                                                 allowUnicode: true) {
                result += "---\n"
                result += yamlString.trimmingCharacters(in: .whitespacesAndNewlines)
                result += "\n---\n"
            }
        }

        let body = document.body
        if !body.isEmpty {
            // Ensure there's a blank line between frontmatter and body
            if !body.hasPrefix("\n") {
                result += "\n"
            }
            result += body
        }

        // Ensure file ends with newline
        if !result.hasSuffix("\n") {
            result += "\n"
        }

        return result
    }

    // MARK: - Atomic Write

    /// Write content to a file atomically: write to .tmp, then rename.
    /// Returns the SHA256 hash of the written content.
    @discardableResult
    public static func atomicWrite(content: String, to url: URL) throws -> String {
        let data = Data(content.utf8)
        let hash = sha256(data)

        let tmpURL = url.appendingPathExtension("tmp")
        let dir = url.deletingLastPathComponent()

        // Ensure directory exists
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Write to .tmp
        try data.write(to: tmpURL)

        // Atomic rename
        // Remove existing file first if it exists (rename won't overwrite on some systems)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } else {
            try FileManager.default.moveItem(at: tmpURL, to: url)
        }

        return hash
    }

    /// Write an AppMDDocument to a file atomically.
    @discardableResult
    public static func atomicWrite(document: AppMDDocument, to url: URL) throws -> String {
        let content = serialize(document)
        return try atomicWrite(content: content, to: url)
    }

    // MARK: - Markdown Table Parsing

    /// Represents a parsed markdown table.
    public struct MarkdownTable: Sendable {
        public var headers: [String]
        public var rows: [[String: String]]

        public init(headers: [String] = [], rows: [[String: String]] = []) {
            self.headers = headers
            self.rows = rows
        }
    }

    /// Parse a markdown table from the body of a document.
    /// Returns nil if no valid table is found.
    public static func parseMarkdownTable(from body: String) -> MarkdownTable? {
        let lines = body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Find table header line (contains |)
        guard let headerIdx = lines.firstIndex(where: { $0.contains("|") && !$0.allSatisfy({ $0 == "|" || $0 == "-" || $0 == " " }) }) else {
            return nil
        }

        let headers = parseTableRow(lines[headerIdx])
        guard !headers.isEmpty else { return nil }

        // Skip separator line (the |---|---| line)
        let dataStartIdx = headerIdx + 2
        guard dataStartIdx <= lines.count else {
            return MarkdownTable(headers: headers, rows: [])
        }

        var rows: [[String: String]] = []
        for i in dataStartIdx..<lines.count {
            let line = lines[i]
            guard line.contains("|") else { break }
            let values = parseTableRow(line)
            var row: [String: String] = [:]
            for (j, header) in headers.enumerated() {
                if j < values.count {
                    row[header] = values[j]
                }
            }
            rows.append(row)
        }

        return MarkdownTable(headers: headers, rows: rows)
    }

    /// Serialize a markdown table back to a string.
    public static func serializeMarkdownTable(_ table: MarkdownTable) -> String {
        guard !table.headers.isEmpty else { return "" }

        var lines: [String] = []

        // Header line
        let headerLine = "| " + table.headers.joined(separator: " | ") + " |"
        lines.append(headerLine)

        // Separator line
        let sepLine = "|" + table.headers.map { _ in "------" }.joined(separator: "|") + "|"
        lines.append(sepLine)

        // Data rows
        for row in table.rows {
            let values = table.headers.map { row[$0] ?? "" }
            let rowLine = "| " + values.joined(separator: " | ") + " |"
            lines.append(rowLine)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Delete (Trash)

    /// Move a file to the trash. Returns true if successful.
    @discardableResult
    public static func moveToTrash(url: URL) throws -> Bool {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return true
    }

    // MARK: - Logging

    /// Log a warning to stderr. Used for non-fatal issues like corrupted files.
    public static func logWarning(_ message: String) {
        FileHandle.standardError.write(Data("[AppMDKit WARNING] \(message)\n".utf8))
    }

    // MARK: - Hashing

    /// Compute SHA256 hash of data, returned as hex string.
    public static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private Helpers

    private static func parseTableRow(_ line: String) -> [String] {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        // Remove leading/trailing pipes
        var inner = stripped
        if inner.hasPrefix("|") { inner = String(inner.dropFirst()) }
        if inner.hasSuffix("|") { inner = String(inner.dropLast()) }

        return inner.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Normalize booleans that Yams incorrectly parsed from YAML 1.1 rules.
    /// Bare `yes`/`no`/`on`/`off` become Bool in Yams but should stay as strings
    /// in AppMD frontmatter unless the raw YAML actually used `true`/`false`.
    private static func normalizeBooleans(parsed: [String: Any], rawYAML: String) -> [String: Any] {
        // Build a lookup of raw values from the YAML text
        var rawValues: [String: String] = [:]
        for line in rawYAML.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let rawVal = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !rawVal.isEmpty {
                rawValues[key] = rawVal
            }
        }

        var result = parsed
        for (key, value) in parsed {
            guard value is Bool else { continue }
            // Check what the raw YAML value was
            if let raw = rawValues[key] {
                let lower = raw.lowercased()
                // Only keep as Bool if the raw value is literally true/false
                if lower != "true" && lower != "false" {
                    // It was yes/no/on/off — restore as string
                    result[key] = raw
                }
            }
        }
        return result
    }

    /// Sort dictionary keys for consistent YAML output.
    /// Puts 'type' first, then alphabetical.
    private static func sortedForYAML(_ dict: [String: Any]) -> [String: Any] {
        // Yams.dump handles the dict as-is; ordering is best-effort
        return dict
    }
}

import CryptoKit
