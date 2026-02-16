import Foundation

// MARK: - AppMD Code Generator
//
// Reads a _schema.yaml file and generates Swift source code with
// AppMDModel conformance for each type defined in the schema.
//
// Usage: appmd-codegen <schema-path> <output-path>

@main
struct AppMDCodeGen {
    static func main() throws {
        let args = CommandLine.arguments

        guard args.count >= 3 else {
            fputs("Usage: appmd-codegen <schema-path> <output-path>\n", stderr)
            exit(1)
        }

        let schemaPath = args[1]
        let outputPath = args[2]

        // Read and parse schema
        let schemaContent = try String(contentsOfFile: schemaPath, encoding: .utf8)
        let schema = try SchemaReader.parse(yaml: schemaContent)

        // Generate Swift code
        let swift = SwiftGenerator.generate(schema: schema)

        // Write output
        try swift.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Minimal Schema Reader (no Yams dependency)
// Build plugins run in a sandbox — we use a minimal YAML parser
// that handles the subset of YAML used in _schema.yaml files.

enum SchemaReader {

    struct Schema {
        let name: String
        let version: Int
        let types: [TypeDef]
    }

    struct TypeDef {
        let name: String
        let fields: [FieldDef]
    }

    struct FieldDef {
        let name: String
        let type: FieldType
        let isOptional: Bool
    }

    indirect enum FieldType: Equatable {
        case string
        case text
        case number
        case date
        case datetime
        case boolean
        case list(FieldType)
        case enumType([String])
        case relationship(String)
        case listRelationship(String)
    }

    static func parse(yaml: String) throws -> Schema {
        let lines = yaml.components(separatedBy: "\n")
        var name = "App"
        var version = 1
        var types: [TypeDef] = []
        var currentType: String?
        var currentFields: [FieldDef] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Top-level key: value
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.contains(":") {
                // Flush previous type
                if let typeName = currentType {
                    types.append(TypeDef(name: typeName, fields: currentFields))
                    currentFields = []
                    currentType = nil
                }

                let parts = trimmed.split(separator: ":", maxSplits: 1)
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

                if key == "name" {
                    name = value
                } else if key == "version" {
                    version = Int(value) ?? 1
                } else if key.first?.isUppercase == true {
                    // Type definition (value might be empty — fields on next lines)
                    currentType = key
                }
            } else if currentType != nil && trimmed.contains(":") {
                // Field definition (indented)
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                var fieldName = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let rawType = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "string"

                var isOptional = false
                if fieldName.hasSuffix("?") {
                    fieldName = String(fieldName.dropLast())
                    isOptional = true
                }

                let fieldType = parseFieldType(rawType)
                currentFields.append(FieldDef(name: fieldName, type: fieldType, isOptional: isOptional))
            }
        }

        // Flush last type
        if let typeName = currentType {
            types.append(TypeDef(name: typeName, fields: currentFields))
        }

        return Schema(name: name, version: version, types: types)
    }

    static func parseFieldType(_ raw: String) -> FieldType {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // List: [type] or [-> Entity]
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.hasPrefix("->") {
                let entity = String(inner.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return .listRelationship(entity)
            }
            return .list(parseFieldType(inner))
        }

        // Relationship: -> Entity
        if trimmed.hasPrefix("->") {
            let entity = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return .relationship(entity)
        }

        // Enum: val1 | val2 | val3
        if trimmed.contains("|") {
            let values = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return .enumType(values)
        }

        // Base types
        switch trimmed {
        case "string": return .string
        case "text": return .text
        case "number": return .number
        case "date": return .date
        case "datetime": return .datetime
        case "boolean", "bool": return .boolean
        default: return .string
        }
    }
}

// MARK: - Swift Code Generator

enum SwiftGenerator {

    static func generate(schema: SchemaReader.Schema) -> String {
        var out = """
        // Auto-generated by AppMD Build Plugin
        // Schema: \(schema.name) v\(schema.version)
        // DO NOT EDIT — regenerated on every build from _schema.yaml

        import Foundation
        import AppMDKit
        import GRDB

        """

        for type in schema.types {
            out += generateType(type, schema: schema)
            out += "\n"
        }

        return out
    }

    static func generateType(_ type: SchemaReader.TypeDef, schema: SchemaReader.Schema) -> String {
        let structName = type.name
        var out = ""

        // Generate enum for enum fields
        for field in type.fields {
            if case .enumType(let values) = field.type {
                out += generateEnum(typeName: structName, fieldName: field.name, values: values)
                out += "\n"
            }
        }

        out += """
        // MARK: - \(structName)

        struct \(structName): AppMDModel {
            static let typeName = "\(structName)"

            let _path: String
            var _body: String
            var _source: AppMDDocument?

        """

        // Properties
        for field in type.fields {
            if field.type == .text { continue } // text is stored in _body
            let swiftType = swiftTypeName(field: field, structName: structName, schema: schema)
            let line = "    var \(escaped(field.name)): \(swiftType)\n"
            out += line
        }

        out += "\n"

        // MARK: - init(row:)
        out += "    init(row: Row) {\n"
        out += "        self._path = row[\"_path\"] as? String ?? \"\"\n"
        out += "        self._body = row[\"_body\"] as? String ?? \"\"\n"
        out += "        self._source = nil\n"

        for field in type.fields {
            if field.type == .text { continue }
            out += "        " + generateRowInit(field: field, structName: structName, schema: schema) + "\n"
        }

        out += "    }\n\n"

        // MARK: - toDocument()
        out += "    func toDocument() -> AppMDDocument {\n"
        out += "        var fields: [String: Any] = [:]\n"

        for field in type.fields {
            if field.type == .text { continue }
            out += "        " + generateToDocumentField(field: field) + "\n"
        }

        let hasTextField = type.fields.contains { $0.type == .text }
        if hasTextField {
            out += "        return buildDocument(fields: fields, body: _body)\n"
        } else {
            out += "        return buildDocument(fields: fields)\n"
        }
        out += "    }\n"

        out += "}\n"

        return out
    }

    // MARK: - Type Mapping

    static func swiftTypeName(field: SchemaReader.FieldDef, structName: String, schema: SchemaReader.Schema) -> String {
        let base = swiftBaseType(field.type, structName: structName, schema: schema)
        return field.isOptional ? "\(base)?" : base
    }

    static func swiftBaseType(_ type: SchemaReader.FieldType, structName: String, schema: SchemaReader.Schema) -> String {
        switch type {
        case .string: return "String"
        case .text: return "String"
        case .number: return "Double"
        case .date: return "String"       // Keep as string for v1, date helpers available
        case .datetime: return "String"
        case .boolean: return "Bool"
        case .list(let inner):
            let innerType = swiftBaseType(inner, structName: structName, schema: schema)
            return "[\(innerType)]"
        case .enumType:
            return "String" // Enum values are strings for now
        case .relationship(let entity):
            // Check if entity is a type in this schema
            if schema.types.contains(where: { $0.name == entity }) {
                return "Ref<\(entity)>"
            }
            return "String"
        case .listRelationship(let entity):
            if schema.types.contains(where: { $0.name == entity }) {
                return "[Ref<\(entity)>]"
            }
            return "[String]"
        }
    }

    // MARK: - Row Init Generation

    static func generateRowInit(field: SchemaReader.FieldDef, structName: String, schema: SchemaReader.Schema) -> String {
        let name = escaped(field.name)
        let col = field.name

        switch field.type {
        case .string, .date, .datetime:
            if field.isOptional {
                return "self.\(name) = row[\"\(col)\"] as? String"
            }
            return "self.\(name) = row[\"\(col)\"] as? String ?? \"\""

        case .number:
            if field.isOptional {
                return "self.\(name) = row[\"\(col)\"] as? Double"
            }
            return "self.\(name) = row[\"\(col)\"] as? Double ?? 0.0"

        case .boolean:
            if field.isOptional {
                return "self.\(name) = row[\"\(col)\"] as? Bool"
            }
            return "self.\(name) = row[\"\(col)\"] as? Bool ?? false"

        case .enumType:
            if field.isOptional {
                return "self.\(name) = row[\"\(col)\"] as? String"
            }
            return "self.\(name) = row[\"\(col)\"] as? String ?? \"\""

        case .list(.string):
            return "self.\(name) = AppMDDecode.array(from: row, column: \"\(col)\")"

        case .list(.number):
            return "self.\(name) = AppMDDecode.numberArray(from: row, column: \"\(col)\")"

        case .list:
            return "self.\(name) = AppMDDecode.array(from: row, column: \"\(col)\")"

        case .relationship(let entity):
            if schema.types.contains(where: { $0.name == entity }) {
                return "self.\(name) = Ref<\(entity)>(row[\"\(col)\"] as? String ?? \"\")"
            }
            if field.isOptional {
                return "self.\(name) = row[\"\(col)\"] as? String"
            }
            return "self.\(name) = row[\"\(col)\"] as? String ?? \"\""

        case .listRelationship:
            return "self.\(name) = AppMDDecode.array(from: row, column: \"\(col)\").map { Ref($0) }"

        case .text:
            return "" // handled by _body
        }
    }

    // MARK: - toDocument Field Generation

    static func generateToDocumentField(field: SchemaReader.FieldDef) -> String {
        let name = escaped(field.name)
        let key = field.name

        switch field.type {
        case .relationship:
            if field.isOptional {
                return "if let \(name) { fields[\"\(key)\"] = \(name).wikiLink }"
            }
            return "fields[\"\(key)\"] = \(name).wikiLink"

        case .listRelationship:
            return "fields[\"\(key)\"] = \(name).map { $0.wikiLink }"

        case .list:
            if field.isOptional {
                return "if let \(name), !\(name).isEmpty { fields[\"\(key)\"] = \(name) }"
            }
            return "if !\(name).isEmpty { fields[\"\(key)\"] = \(name) }"

        default:
            if field.isOptional {
                return "if let \(name) { fields[\"\(key)\"] = \(name) }"
            }
            return "fields[\"\(key)\"] = \(name)"
        }
    }

    // MARK: - Enum Generation

    static func generateEnum(typeName: String, fieldName: String, values: [String]) -> String {
        let enumName = "\(typeName)\(fieldName.capitalized)"
        var out = "enum \(enumName): String, CaseIterable, Sendable {\n"
        for value in values {
            let caseName = value.replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "_")
                .lowercased()
            if caseName == value {
                out += "    case \(caseName)\n"
            } else {
                out += "    case \(caseName) = \"\(value)\"\n"
            }
        }
        out += "}\n"
        return out
    }

    // MARK: - Helpers

    /// Escape Swift keywords used as identifiers
    static func escaped(_ name: String) -> String {
        let keywords: Set<String> = [
            "class", "struct", "enum", "protocol", "extension", "func",
            "var", "let", "if", "else", "for", "while", "return", "switch",
            "case", "default", "break", "continue", "import", "type",
            "self", "super", "init", "deinit", "subscript", "operator",
            "in", "where", "as", "is", "try", "throw", "throws", "catch",
            "true", "false", "nil", "guard", "defer", "repeat", "do",
        ]
        if keywords.contains(name) {
            return "`\(name)`"
        }
        return name
    }
}
