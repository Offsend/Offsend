import Foundation

enum CLIOutput {
    static func writeStdout(_ text: String) {
        guard !text.isEmpty else { return }
        if text.hasSuffix("\n") {
            print(text, terminator: "")
        } else {
            print(text)
        }
    }
}
