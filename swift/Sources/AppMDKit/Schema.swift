import Foundation
import Yams

// MARK: - Schema Types

/// Represents a parsed `_schema.yaml` file.
public struct AppMDSchema: Sendable {
    public let name: String
    public let version: Int
    public let types: [String: TypeDefinition]

    public init(name: String, version: Int, types: [String: TypeDefinition]) {
        self.name = name
        self.version = version
        self.types = types
    }
}

/// A type definition within a schema (e.g., Entry, Transaction, Contact).
public struct TypeDefinition: Sendable {
    public let name: String
    public let fields: [FieldDefinition]

    public init(name: String, fields: [FieldDefinition]) {
        self.name = name
        self.fields = fields
    }

    /// Look up a field by name.
    public func field(named name: String) -> FieldDefinition? {
        fields.first { $0.name == name }
    }
}

/// A single field definition within a type.
public struct FieldDefinition: Sendable {
    public let name: String
    public let type: FieldType
    public let isOptional: Bool
    public let defaultValue: String?

    public init(name: String, type: FieldType, isOptional: Bool = false, defaultValue: String? = nil) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
        self.defaultValue = defaultValue
    }
}

/// The type of a field.
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
    public var sqliteType: String {
        switch self {
        case .string, .text, .date, .datetime, .relationship:
            return "TEXT"
        case .number:
            return "REAL"
        case .boolean:
            return "BOOLEAN"
        case .list, .enum, .listRelationship:
            return "TEXT" // stored as JSON array or comma-separated
        }
    }
}

// MARK: - Schema Parser

public enum SchemaParser {

    /// Load and parse a `_schema.yaml` file.
    public static func parse(at url: URL) throws -> AppMDSchema {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(yaml: content)
    }

    /// Parse schema from a YAML string.
    public static func parse(yaml: String) throws -> AppMDSchema {
        guard let raw = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw SchemaError.invalidFormat("Schema must be a YAML dictionary")
        }

        guard let name = raw["name"] as? String else {
            throw SchemaError.missingField("name")
        }

        let version = (raw["version"] as? Int) ?? 1

        var types: [String: TypeDefinition] = [:]

        for (key, value) in raw {
            // Skip metadata keys
            guard key != "name" && key != "version" else { continue }

            // Type names are capitalized
            guard key.first?.isUppercase == true else { continue }

            guard let fieldDict = value as? [String: Any] else { continue }

            let typeDef = try parseType(name: key, fields: fieldDict)
            types[key] = typeDef
        }

        return AppMDSchema(name: name, version: version, types: types)
    }

    // MARK: - Private

    private static func parseType(name: String, fields: [String: Any]) throws -> TypeDefinition {
        var fieldDefs: [FieldDefinition] = []

        for (fieldName, fieldValue) in fields {
            let fieldDef = try parseField(name: fieldName, rawType: fieldValue)
            fieldDefs.append(fieldDef)
        }

        return TypeDefinition(name: name, fields: fieldDefs)
    }

    private static func parseField(name: String, rawType: Any) throws -> FieldDefinition {
        var fieldName = name
        var isOptional = false

        // Check for optional marker
        if fieldName.hasSuffix("?") {
            fieldName = String(fieldName.dropLast())
            isOptional = true
        }

        // Handle string type definitions
        if let typeString = rawType as? String {
            let (fieldType, defaultValue) = try parseTypeString(typeString)
            return FieldDefinition(name: fieldName, type: fieldType, isOptional: isOptional, defaultValue: defaultValue)
        }

        // Handle YAML arrays — could be [string], [number], [-> Entity], etc.
        // Yams parses `[string]` as a YAML array ["string"]
        if let array = rawType as? [String], array.count == 1 {
            let inner = array[0].trimmingCharacters(in: .whitespaces)
            if inner.hasPrefix("->") {
                let entity = String(inner.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return FieldDefinition(name: fieldName, type: .listRelationship(entity), isOptional: isOptional)
            }
            let innerType = try parseFieldType(inner)
            return FieldDefinition(name: fieldName, type: .list(innerType), isOptional: isOptional)
        }

        // Handle array-style enum definitions (with metadata)
        if let enumArray = rawType as? [[String: Any]] {
            let values = enumArray.compactMap { $0["value"] as? String }
            return FieldDefinition(name: fieldName, type: .enum(values), isOptional: isOptional)
        }

        throw SchemaError.invalidFieldType("Cannot parse field type for '\(name)': \(rawType)")
    }

    private static func parseTypeString(_ raw: String) throws -> (FieldType, String?) {
        var typeStr = raw.trimmingCharacters(in: .whitespaces)
        var defaultValue: String? = nil

        // Check for default value: `type = defaultValue`
        if let eqRange = typeStr.range(of: " = ") {
            defaultValue = String(typeStr[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            typeStr = String(typeStr[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        let fieldType = try parseFieldType(typeStr)
        return (fieldType, defaultValue)
    }

    private static func parseFieldType(_ typeStr: String) throws -> FieldType {
        let trimmed = typeStr.trimmingCharacters(in: .whitespaces)

        // List type: [type]
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)

            // List of relationships: [-> EntityName]
            if inner.hasPrefix("->") {
                let entity = String(inner.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return .listRelationship(entity)
            }

            let innerType = try parseFieldType(inner)
            return .list(innerType)
        }

        // Relationship: -> EntityName
        if trimmed.hasPrefix("->") {
            let entity = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return .relationship(entity)
        }

        // Enum: val1 | val2 | val3
        if trimmed.contains("|") {
            let values = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return .enum(values)
        }

        // Base types
        switch trimmed {
        case "string": return .string
        case "text": return .text
        case "number": return .number
        case "date": return .date
        case "datetime": return .datetime
        case "boolean", "bool": return .boolean
        default:
            throw SchemaError.invalidFieldType("Unknown type: '\(trimmed)'")
        }
    }
}

// MARK: - Schema Validation

public enum SchemaValidator {

    /// Validate a document's frontmatter against a schema type definition.
    /// Returns a list of validation errors (empty if valid).
    public static func validate(document: AppMDDocument, against typeDef: TypeDefinition) -> [String] {
        var errors: [String] = []
        let fm = document.frontmatter

        for field in typeDef.fields {
            // Skip 'type' field — it's metadata
            if field.name == "type" { continue }

            // For text fields, the value is the body
            if field.type == .text {
                if !field.isOptional && document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append("Required text field '\(field.name)' is empty")
                }
                continue
            }

            let value = fm[field.name]

            if value == nil && !field.isOptional && field.defaultValue == nil {
                errors.append("Required field '\(field.name)' is missing")
                continue
            }

            if let value = value {
                errors.append(contentsOf: validateValue(value, field: field))
            }
        }

        return errors
    }

    private static func validateValue(_ value: Any, field: FieldDefinition) -> [String] {
        switch field.type {
        case .enum(let allowed):
            if let strValue = value as? String {
                if !allowed.contains(strValue) {
                    return ["Field '\(field.name)' value '\(strValue)' is not one of: \(allowed.joined(separator: ", "))"]
                }
            }
        case .number:
            if !(value is Int) && !(value is Double) && !(value is Float) {
                // Try string->number conversion
                if let str = value as? String, Double(str) == nil {
                    return ["Field '\(field.name)' is not a valid number"]
                }
            }
        case .boolean:
            if !(value is Bool) {
                return ["Field '\(field.name)' is not a valid boolean"]
            }
        case .list:
            if !(value is [Any]) {
                return ["Field '\(field.name)' should be a list"]
            }
        default:
            break
        }
        return []
    }
}

// MARK: - Errors

public enum SchemaError: Error, LocalizedError {
    case invalidFormat(String)
    case missingField(String)
    case invalidFieldType(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return "Invalid schema format: \(msg)"
        case .missingField(let name): return "Missing required schema field: \(name)"
        case .invalidFieldType(let msg): return "Invalid field type: \(msg)"
        }
    }
}
