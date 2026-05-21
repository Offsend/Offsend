import Foundation

enum IgnoreFileParser {
    static let defaultHeader = "# Offsend AI privacy defaults"

    static func normalizedPattern(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        return trimmed
    }

    static func patterns(in contents: String) -> Set<String> {
        Set(contents.components(separatedBy: .newlines).compactMap(normalizedPattern))
    }

    static func patternLines(in contents: String) -> [String] {
        contents.components(separatedBy: .newlines).compactMap(normalizedPattern)
    }
}
