import PackagePlugin
import Foundation

@main
struct AppMDPlugin: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        // Find _schema.yaml in the target's source directory
        let schemaFiles = sourceTarget.sourceFiles.filter { $0.path.lastComponent == "_schema.yaml" }

        guard let schemaFile = schemaFiles.first else {
            // No schema found — that's fine, just don't generate anything.
            // Developers might be writing models manually.
            Diagnostics.remark("No _schema.yaml found in \(target.name) — skipping AppMD code generation")
            return []
        }

        let outputPath = context.pluginWorkDirectory.appending("AppMDGenerated.swift")
        let tool = try context.tool(named: "appmd-codegen")

        return [
            .buildCommand(
                displayName: "AppMD: Generate models from \(schemaFile.path.lastComponent)",
                executable: tool.path,
                arguments: [
                    schemaFile.path.string,
                    outputPath.string,
                ],
                inputFiles: [schemaFile.path],
                outputFiles: [outputPath]
            )
        ]
    }
}
