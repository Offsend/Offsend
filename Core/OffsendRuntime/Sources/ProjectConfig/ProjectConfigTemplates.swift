import Foundation
import WorkspacePolicyCore

/// Built-in exclude presets used by `offsend init --template`.
public enum ProjectConfigTemplateID: String, CaseIterable, Sendable {
    case common
    case node
    case python
    case go
    case rust
    case ruby
    case java
    case android
    case swift
    case tuist

    public var summary: String {
        switch self {
        case .common:
            "Lockfiles, OS junk, dist/build/coverage, minified/maps, linter caches"
        case .node:
            "node_modules, lockfiles, bundler/Storybook caches, Next/Nuxt/Turbo/Vercel"
        case .python:
            "venvs, __pycache__, mypy/pytest/ruff caches, egg-info, Jupyter checkpoints"
        case .go:
            "vendor/, go.sum"
        case .rust:
            "target/"
        case .ruby:
            "vendor/bundle, .bundle"
        case .java:
            ".gradle, Maven/IDEA out and target, class/jar"
        case .android:
            "NDK/CXX build dirs, APK/AAB/DEX/class/jar artifacts"
        case .swift:
            "DerivedData, SPM .build/Package.resolved, Pods, Carthage, archives"
        case .tuist:
            "Derived/, Tuist build and dependencies"
        }
    }

    public var excludePatterns: [String] {
        switch self {
        case .common:
            [
                "*.lock",
                ".DS_Store",
                "Thumbs.db",
                "Desktop.ini",
                "**/dist/**",
                "**/build/**",
                "**/coverage/**",
                "*.map",
                "*.min.js",
                "*.min.css",
                ".eslintcache",
                ".stylelintcache",
            ]
        case .node:
            [
                "**/node_modules/**",
                "**/.next/**",
                "**/.nuxt/**",
                "**/.output/**",
                "**/.turbo/**",
                "**/.vercel/**",
                "**/bower_components/**",
                "**/.yarn/cache/**",
                "**/.yarn/unplugged/**",
                "**/.pnpm-store/**",
                "**/.svelte-kit/**",
                "**/.parcel-cache/**",
                "**/.vite/**",
                "**/storybook-static/**",
                "package-lock.json",
                "npm-shrinkwrap.json",
                "pnpm-lock.yaml",
                "bun.lock",
                "bun.lockb",
                "install-state.gz",
                "*.tsbuildinfo",
            ]
        case .python:
            [
                "**/.venv/**",
                "**/venv/**",
                "**/__pycache__/**",
                "**/.mypy_cache/**",
                "**/.pytest_cache/**",
                "**/.ruff_cache/**",
                "**/*.egg-info/**",
                "**/.tox/**",
                "**/.eggs/**",
                "**/.nox/**",
                "**/htmlcov/**",
                "**/.ipynb_checkpoints/**",
                "*.pyc",
                "*.pyo",
            ]
        case .go:
            [
                "**/vendor/**",
                "go.sum",
            ]
        case .rust:
            [
                "**/target/**",
            ]
        case .ruby:
            [
                "**/vendor/bundle/**",
                "**/.bundle/**",
            ]
        case .java:
            [
                "**/.gradle/**",
                "**/out/**",
                "**/.idea/**",
                "**/target/**",
                "*.class",
                "*.jar",
            ]
        case .android:
            [
                "**/.cxx/**",
                "**/.externalNativeBuild/**",
                "*.apk",
                "*.aab",
                "*.dex",
                "*.class",
                "*.jar",
            ]
        case .swift:
            [
                "**/DerivedData/**",
                "**/.build/**",
                "**/Pods/**",
                "**/Carthage/Build/**",
                "**/xcuserdata/**",
                "*.xcuserstate",
                "*.xcarchive/**",
                "Package.resolved",
                "*.ipa",
                "**/*.dSYM/**",
            ]
        case .tuist:
            [
                "**/Derived/**",
                "**/Tuist/.build/**",
                "**/Tuist/Dependencies/**",
                "**/.tuist-bin/**",
            ]
        }
    }
}

public enum ProjectConfigTemplateError: Error, LocalizedError, Equatable {
    case unknownTemplate(String)

    public var errorDescription: String? {
        switch self {
        case .unknownTemplate(let id):
            let known = ProjectConfigTemplateID.allCases.map(\.rawValue).joined(separator: ", ")
            return "Unknown template '\(id)'. Known templates: \(known)."
        }
    }
}

public enum ProjectConfigTemplates {
    /// Optional patterns kept as YAML comments in starter configs (not active excludes).
    /// Broad dirs like tmp/temp/.cache can hide secrets — users may uncomment deliberately.
    public static let commentedOptionalExcludePatterns: [String] = [
        "**/.cache/**",
        "**/tmp/**",
        "**/temp/**",
    ]

    /// Aliases accepted by `--template` (resolved case-insensitively).
    public static let aliases: [String: ProjectConfigTemplateID] = [
        "js": .node,
        "ts": .node,
        "javascript": .node,
        "typescript": .node,
        "ios": .swift,
    ]

    public static func listTemplatesText() -> String {
        var lines = ["Available exclude templates (`common` is always included):", ""]
        let aliasByID: [ProjectConfigTemplateID: [String]] = Dictionary(
            grouping: aliases.keys.sorted(),
            by: { aliases[$0]! }
        ).mapValues { $0.sorted() }

        for id in ProjectConfigTemplateID.allCases {
            var line = "  \(id.rawValue)  — \(id.summary)"
            if let names = aliasByID[id], !names.isEmpty {
                line += " (aliases: \(names.joined(separator: ", ")))"
            }
            lines.append(line)
        }
        lines.append("")
        lines.append("Examples:")
        lines.append("  offsend init --template node")
        lines.append("  offsend init --template js,swift")
        lines.append("  offsend init --template python --merge-exclude")
        return lines.joined(separator: "\n")
    }

    /// Parses repeated `--template` values and CSV fragments (`node,swift`).
    /// Case-insensitive; supports aliases. Always includes `common` first.
    public static func resolve(rawValues: [String]) throws -> [ProjectConfigTemplateID] {
        var resolved: [ProjectConfigTemplateID] = [.common]
        var seen: Set<ProjectConfigTemplateID> = [.common]

        for raw in rawValues {
            let parts = raw.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            for part in parts where !part.isEmpty {
                let id = try parseTemplateID(part)
                if seen.insert(id).inserted {
                    resolved.append(id)
                }
            }
        }

        return resolved
    }

    public static func parseTemplateID(_ raw: String) throws -> ProjectConfigTemplateID {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let id = ProjectConfigTemplateID(rawValue: key) {
            return id
        }
        if let id = aliases[key] {
            return id
        }
        throw ProjectConfigTemplateError.unknownTemplate(raw)
    }

    /// Union of exclude patterns for the given templates, preserving order and deduping.
    /// Inserts `common` if missing.
    public static func excludePatterns(for ids: [ProjectConfigTemplateID]) -> [String] {
        var orderedIDs = ids
        if !orderedIDs.contains(.common) {
            orderedIDs.insert(.common, at: 0)
        }

        var patterns: [String] = []
        var seen = Set<String>()
        for id in orderedIDs {
            for pattern in id.excludePatterns where seen.insert(pattern).inserted {
                patterns.append(pattern)
            }
        }
        return patterns
    }

    /// Merges `additional` into `existing`, preserving existing order and appending new patterns.
    public static func mergeExcludeLists(existing: [String], additional: [String]) -> (merged: [String], added: [String]) {
        var merged = existing
        var seen = Set(existing)
        var added: [String] = []
        for pattern in additional where seen.insert(pattern).inserted {
            merged.append(pattern)
            added.append(pattern)
        }
        return (merged, added)
    }

    /// Updates the `check.exclude` list in an existing YAML document, preserving surrounding content
    /// when an `exclude:` block is already present.
    public static func mergingExclude(intoYAML yaml: String, patterns: [String]) throws -> (yaml: String, added: [String]) {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var existing: [String] = []
        var excludeLineIndex: Int?
        var listStart: Int?
        var listEnd: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("exclude:") {
                excludeLineIndex = index
                let inline = trimmed.dropFirst("exclude:".count).trimmingCharacters(in: .whitespaces)
                if inline == "[]" {
                    listStart = index + 1
                    listEnd = index
                } else if inline.hasPrefix("-") {
                    // Unusual inline form; treat as no list block.
                    listStart = index + 1
                    listEnd = index
                } else {
                    listStart = index + 1
                    var end = index
                    for j in (index + 1)..<lines.count {
                        let item = lines[j].trimmingCharacters(in: .whitespaces)
                        if item.hasPrefix("-") {
                            existing.append(parseYAMLListItem(item))
                            end = j
                        } else if item.isEmpty || item.hasPrefix("#") {
                            continue
                        } else {
                            break
                        }
                    }
                    listEnd = end
                }
                break
            }
        }

        let merge = mergeExcludeLists(existing: existing, additional: patterns)
        let excludeBlock = renderExcludeBlock(patterns: merge.merged)

        guard let excludeLineIndex, let listStart, let listEnd else {
            // No exclude key — insert under check: if possible, else append.
            if let checkIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "check:"
                || $0.trimmingCharacters(in: .whitespaces).hasPrefix("check:") }) {
                var newLines = lines
                let insertion = excludeBlock.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                newLines.insert(contentsOf: insertion, at: checkIndex + 1)
                return (newLines.joined(separator: "\n"), merge.added)
            }
            var newLines = lines
            if newLines.last == "" {
                newLines.removeLast()
            }
            newLines.append("check:")
            newLines.append(contentsOf: excludeBlock.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
            newLines.append("")
            return (newLines.joined(separator: "\n"), merge.added)
        }

        var newLines = Array(lines.prefix(excludeLineIndex))
        newLines.append(contentsOf: excludeBlock.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        if listEnd + 1 < lines.count {
            newLines.append(contentsOf: lines[(listEnd + 1)...])
        }
        // When exclude: [] with no following items, listEnd == excludeLineIndex and listStart == exclude+1;
        // we already dropped the old exclude line via prefix(excludeLineIndex).
        _ = listStart
        let result = newLines.joined(separator: "\n")
        return (result.hasSuffix("\n") ? result : result + "\n", merge.added)
    }

    private static func parseYAMLListItem(_ trimmed: String) -> String {
        var value = trimmed
        if value.hasPrefix("-") {
            value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func renderExcludeBlock(patterns: [String]) -> String {
        if patterns.isEmpty {
            return "  exclude: []"
        }
        let items = patterns.map { "    - \"\($0)\"" }.joined(separator: "\n")
        return "  exclude:\n\(items)"
    }

    /// Full starter `.offsend.yml` contents for `offsend init`.
    public static func renderYAML(
        templates: [ProjectConfigTemplateID],
        ignoreCommit: Bool = false,
        hooksPublish: Bool = false
    ) -> String {
        let ids = templates.contains(.common) ? templates : [.common] + templates
        let labels = ids.map(\.rawValue).joined(separator: ", ")
        let generatedBy: String = {
            let extras = ids.filter { $0 != .common }.map(\.rawValue)
            if extras.isEmpty {
                return "offsend init"
            }
            return "offsend init --template \(extras.joined(separator: ","))"
        }()
        let patterns = excludePatterns(for: ids)
        let excludeLines = patterns.map { "    - \"\($0)\"" }.joined(separator: "\n")
        let optionalCommentLines = ([
            "    # Optional — uncomment only if these dirs never hold secrets:",
        ] + commentedOptionalExcludePatterns.map { "    # - \"\($0)\"" })
            .joined(separator: "\n")
        let ignoreSection = ProjectConfigIgnoreMutator.renderIgnoreSection(
            commit: ignoreCommit,
            patterns: AIWorkspacePrivacyIgnoreTemplate.defaultPatterns
        )
        let hooksPublishLine = "  publish: \(hooksPublish ? "true" : "false")"

        return """
        version: 1

        check:
          fail_on: block
          policy: false
          # Generated by: \(generatedBy)
          # templates: \(labels)
          exclude:
        \(excludeLines)
        \(optionalCommentLines)
          detectors:
            # All detector IDs you can list under `disable:`:
            #   email, phone, money, url, ipAddress, internalDomain, contractId,
            #   invoiceId, orderId, apiKeyGeneric, openAIAPIKey, awsAccessKeyId,
            #   githubToken, slackToken, stripeKey, jwt, privateKey, sshPrivateKey,
            #   databaseURLWithPassword, bearerToken, highEntropyString, creditCardLike,
            #   iban, customClient, customCompany, customProject, customSensitiveTerm,
            #   customInternalDomain, personName, streetAddress, governmentId
            # Default keeps only secret/credential detectors active.
            disable:
              - email
              - phone
              - money
              - url
              - ipAddress
              - internalDomain
              - contractId
              - invoiceId
              - orderId
              - creditCardLike
              - iban
              - personName
              - streetAddress
              - governmentId
          # Custom dictionaries are matched in addition to the built-in detectors.
          # kind: client | company | project | sensitiveTerm | internalDomain | regex
          # For every kind except `regex`, `value` is matched literally (with word boundaries).
          # For `regex`, `value` is used as a regular expression pattern verbatim.
          dictionaries: []

        \(ignoreSection)

        hooks:
          type: pre-commit
          fail_on: block
          policy: false
        \(hooksPublishLine)

        """
    }

    /// Parses a yes/no prompt answer. Empty input uses `defaultYes`.
    public static func parseYesNo(_ raw: String, defaultYes: Bool) -> Bool? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return defaultYes }
        switch trimmed {
        case "y", "yes", "true", "1":
            return true
        case "n", "no", "false", "0":
            return false
        default:
            return nil
        }
    }
}
