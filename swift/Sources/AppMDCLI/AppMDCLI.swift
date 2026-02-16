import ArgumentParser
import Foundation
import AppMDKit

@main
struct AppMD: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appmd",
        abstract: "AppMD — Markdown files as your data layer",
        subcommands: [Init.self, Validate.self, Inspect.self]
    )
}

// MARK: - Init

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scaffold a new AppMD app directory"
    )

    @Argument(help: "Name of the app")
    var name: String

    func run() throws {
        let fm = FileManager.default
        let dir = fm.currentDirectoryPath + "/\(name)"

        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dir + "/.cache", withIntermediateDirectories: true)

        // .gitignore for cache
        try ".cache/\n".write(toFile: dir + "/.gitignore", atomically: true, encoding: .utf8)

        // Template schema
        let schema = """
        name: \(name)
        version: 1

        # Define your types here:
        # Note:
        #   name: string
        #   created: datetime
        #   body: text
        """
        try schema.write(toFile: dir + "/_schema.yaml", atomically: true, encoding: .utf8)

        // Sample file
        let sample = """
        ---
        type: Note
        name: Welcome
        created: \(ISO8601DateFormatter().string(from: Date()))
        ---

        Welcome to **\(name)**! Edit `_schema.yaml` to define your types.
        """
        try fm.createDirectory(atPath: dir + "/notes", withIntermediateDirectories: true)
        try sample.write(toFile: dir + "/notes/welcome.md", atomically: true, encoding: .utf8)

        print("✅ Created AppMD app at ./\(name)/")
        print("")
        print("Add to your Package.swift:")
        print("  .package(path: \"../appmd/swift\")")
        print("  // then add \"AppMDKit\" as a dependency to your target")
    }
}

// MARK: - Validate

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate markdown files against the schema"
    )

    @Argument(help: "Path to the AppMD app directory (default: current directory)")
    var path: String?

    func run() throws {
        let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)
        let schemaURL = root.appendingPathComponent("_schema.yaml")

        guard FileManager.default.fileExists(atPath: schemaURL.path) else {
            print("❌ No _schema.yaml found at \(root.path)")
            throw ExitCode(1)
        }

        let schema = try SchemaParser.parse(at: schemaURL)
        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var totalFiles = 0
        var errorCount = 0

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            totalFiles += 1

            let doc = try FileEngine.parse(fileAt: url)
            let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")

            guard let typeName = doc.type else {
                print("⚠️  \(relativePath): missing 'type' field")
                errorCount += 1
                continue
            }

            guard let typeDef = schema.types[typeName] else {
                print("❌ \(relativePath): unknown type '\(typeName)'")
                errorCount += 1
                continue
            }

            let errors = SchemaValidator.validate(document: doc, against: typeDef)
            for error in errors {
                print("❌ \(relativePath): \(error)")
                errorCount += 1
            }
        }

        print("")
        print("Scanned \(totalFiles) files, \(errorCount) error(s)")

        if errorCount > 0 {
            throw ExitCode(1)
        } else {
            print("✅ All files valid")
        }
    }
}

// MARK: - Inspect

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Dump index stats for an AppMD app"
    )

    @Argument(help: "Path to the AppMD app directory (default: current directory)")
    var path: String?

    func run() throws {
        let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)
        let schemaURL = root.appendingPathComponent("_schema.yaml")

        guard FileManager.default.fileExists(atPath: schemaURL.path) else {
            print("❌ No _schema.yaml found at \(root.path)")
            throw ExitCode(1)
        }

        let schema = try SchemaParser.parse(at: schemaURL)

        // Check if index exists
        let indexPath = root.appendingPathComponent(".cache/index.sqlite").path
        let indexExists = FileManager.default.fileExists(atPath: indexPath)

        print("📦 \(schema.name) (v\(schema.version))")
        print("   Types: \(schema.types.keys.sorted().joined(separator: ", "))")
        print("")

        // Count files per type by scanning disk
        var typeCounts: [String: Int] = [:]
        var orphaned: [String] = []
        var totalFiles = 0

        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "md" else { continue }
                totalFiles += 1
                let doc = FileEngine.parse(content: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
                let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
                if let t = doc.type {
                    if schema.types[t] != nil {
                        typeCounts[t, default: 0] += 1
                    } else {
                        orphaned.append(relativePath)
                    }
                } else {
                    orphaned.append(relativePath)
                }
            }
        }

        print("📊 Files per type:")
        for typeName in schema.types.keys.sorted() {
            print("   \(typeName): \(typeCounts[typeName] ?? 0)")
        }
        print("   Total: \(totalFiles)")

        if !orphaned.isEmpty {
            print("")
            print("⚠️  Orphaned files (\(orphaned.count)):")
            for f in orphaned.prefix(20) {
                print("   \(f)")
            }
            if orphaned.count > 20 {
                print("   ... and \(orphaned.count - 20) more")
            }
        }

        print("")
        if indexExists {
            let attrs = try fm.attributesOfItem(atPath: indexPath)
            let size = attrs[.size] as? Int64 ?? 0
            let modified = attrs[.modificationDate] as? Date
            print("🗄️  Index: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
            if let mod = modified {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                print("   Last modified: \(formatter.string(from: mod))")
            }

            // Check FTS
            print("   FTS: enabled (fts5, porter unicode61)")
        } else {
            print("🗄️  Index: not built (run your app to create it)")
        }
    }
}
