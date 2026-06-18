import ArgumentParser
import Foundation
import OffsendRuntime

struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scan files for sensitive data before sharing or committing."
    )

    @Argument(help: "File or directory paths to scan. Directories are scanned recursively.")
    var paths: [String] = []

    @Flag(name: .long, help: "Scan only staged files in the current git repository.")
    var staged = false

    @Flag(name: .long, help: "Also run workspace policy checks on the repository root.")
    var policy = false

    @Option(name: .long, help: "Exit with failure when findings reach this level (block, warn, none).")
    var failOn: String?

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    @Flag(name: .long, help: "Only print findings and errors.")
    var quiet = false

    @Flag(name: .long, help: "List every finding and skipped file individually instead of a summary.")
    var verbose = false

    @Option(name: .long, help: "Working directory used for relative paths.")
    var workingDirectory: String?

    mutating func run() async throws {
        let outputFormat = CLIParse.outputFormat(format)
        let validatedFailOn = CLIParse.failPolicy(failOn)

        if staged, !paths.isEmpty {
            CLIError.exit(.error, message: "--staged cannot be combined with explicit paths.")
        }

        let context: OffsendRuntimeContext
        do {
            context = try OffsendRuntimeContext.load()
        } catch {
            CLIError.exit(.error, message: "Failed to load Offsend settings: \(error.localizedDescription)")
        }

        let workingURL = URL(
            fileURLWithPath: workingDirectory ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        let projectConfig = CLIParse.projectConfig(from: workingURL)
        let resolved = OptionsResolver.resolveCheckOptions(
            overrides: CLICheckOverrides(
                policySpecified: policy,
                policyValue: policy,
                failOn: validatedFailOn
            ),
            projectConfig: projectConfig,
            staged: staged
        )

        let gitResolver = GitRepositoryResolver()
        var fileURLs: [URL] = []
        var policyDirectoryURL: URL?
        // Relative paths and exclude patterns are computed against this root.
        var scanRoot = workingURL
        var stagedExportRoot: URL?
        defer {
            if let stagedExportRoot {
                try? FileManager.default.removeItem(at: stagedExportRoot)
            }
        }

        if staged {
            let repositoryRoot = resolveRepositoryRoot(startingAt: workingURL, gitResolver: gitResolver)
            // Scan the index content (not the working tree) so that partially
            // staged changes are checked exactly as they would be committed.
            let exportRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("offsend-staged-\(UUID().uuidString)", isDirectory: true)
            stagedExportRoot = exportRoot
            do {
                fileURLs = try gitResolver.exportStagedFiles(in: repositoryRoot, to: exportRoot)
            } catch let error as GitRepositoryError {
                CLIError.exit(for: error)
            } catch {
                CLIError.exit(.error, message: "Failed to read staged files: \(error.localizedDescription)")
            }
            scanRoot = exportRoot
            if resolved.policy {
                policyDirectoryURL = repositoryRoot
            }
        } else if !paths.isEmpty {
            var directoryURLs: [URL] = []
            for path in paths {
                let url = URL(fileURLWithPath: path, relativeTo: workingURL).standardizedFileURL
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    CLIError.exit(.error, message: "Path not found: \(url.path)")
                }
                if isDirectory.boolValue {
                    directoryURLs.append(url)
                    fileURLs.append(contentsOf: collectFiles(in: url))
                } else {
                    fileURLs.append(url)
                }
            }
            if resolved.policy {
                if directoryURLs.count > 1 {
                    CLIError.exit(.error, message: "--policy supports a single directory; got \(directoryURLs.count).")
                }
                policyDirectoryURL = directoryURLs.first
                    ?? resolveRepositoryRoot(startingAt: workingURL, gitResolver: gitResolver)
            }
        } else if resolved.policy {
            policyDirectoryURL = resolveRepositoryRoot(startingAt: workingURL, gitResolver: gitResolver)
        } else {
            CLIError.exit(.error, message: "Provide file paths, --staged, or --policy.")
        }

        let service = OffsendCheckService(context: context)
        let request = OffsendCheckRequest(
            fileURLs: fileURLs,
            policyDirectoryURL: policyDirectoryURL,
            failPolicy: resolved.failPolicy,
            workingDirectory: scanRoot,
            excludePatterns: resolved.excludePatterns,
            disabledDetectors: resolved.disabledDetectors,
            customDictionaries: resolved.customDictionaries
        )
        let report = await CLISpinner(message: "Scanning...").runWhile {
            await service.run(request)
        }

        let useColor = outputFormat == .text
            && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            && isatty(STDOUT_FILENO) != 0
        let output = CheckReporter().render(report, format: outputFormat, quiet: quiet, verbose: verbose, useColor: useColor)
        if !output.isEmpty {
            print(output)
        }

        if report.shouldFail {
            throw ExitCode(OffsendExitCode.findings.rawValue)
        }
    }

    private func collectFiles(in directory: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                if url.lastPathComponent == ".git" {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values?.isRegularFile == true {
                files.append(url.standardizedFileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func resolveRepositoryRoot(
        startingAt path: URL,
        gitResolver: GitRepositoryResolver
    ) -> URL {
        do {
            return try gitResolver.repositoryRoot(startingAt: path)
        } catch let error as GitRepositoryError {
            CLIError.exit(for: error)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }
    }
}
