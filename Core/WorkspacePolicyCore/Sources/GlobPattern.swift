import Foundation

public struct GlobPattern: Equatable {
    private let regex: NSRegularExpression

    public init(_ pattern: String) {
        regex = try! NSRegularExpression(pattern: "^\(Self.regexPattern(from: pattern))$")
    }

    public func matches(_ value: String) -> Bool {
        regex.firstMatch(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        ) != nil
    }

    private static func regexPattern(from glob: String) -> String {
        var regex = ""
        var index = glob.startIndex
        while index < glob.endIndex {
            let character = glob[index]
            if character == "*" {
                let nextIndex = glob.index(after: index)
                if nextIndex < glob.endIndex, glob[nextIndex] == "*" {
                    regex += ".*"
                    index = glob.index(after: nextIndex)
                } else {
                    regex += #"[^/]*"#
                    index = nextIndex
                }
            } else if character == "?" {
                regex += #"[^/]"#
                index = glob.index(after: index)
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(character))
                index = glob.index(after: index)
            }
        }
        return regex
    }
}
