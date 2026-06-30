import Foundation
import Mustache

struct HTMLTemplateRenderer: Sendable {
    let library: MustacheLibrary

    enum LoadError: Error {
        case missingResources
        case templateNotFound(String)
    }

    static func load() throws -> HTMLTemplateRenderer {
        guard let baseURL = Bundle.module.resourceURL else {
            throw LoadError.missingResources
        }
        var library = MustacheLibrary()
        var loadedCount = 0
        let files = try FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil
        )
        for file in files where file.pathExtension == "mustache" {
            let name = file.deletingPathExtension().lastPathComponent
            let contents = try String(contentsOf: file, encoding: .utf8)
            try library.register(contents, named: name)
            loadedCount += 1
        }
        guard loadedCount > 0 else {
            throw LoadError.missingResources
        }
        return HTMLTemplateRenderer(library: library)
    }

    func landingPage() throws -> String {
        try render(named: "landing", context: [:] as [String: String])
    }

    func pollingPage(jobID: String) throws -> String {
        try render(named: "polling", context: ["jobID": jobID])
    }

    func report(
        jobID: String,
        repoURL: String,
        reportJSON: String,
        generatedAt: Date
    ) throws -> String {
        let context = ReportHTMLRenderer.makeContext(
            jobID: jobID,
            repoURL: repoURL,
            reportJSON: reportJSON,
            generatedAt: generatedAt
        )
        return try render(named: "report", context: context)
    }

    private func render(named template: String, context: Any) throws -> String {
        guard let html = library.render(context, withTemplate: template) else {
            throw LoadError.templateNotFound(template)
        }
        return html
    }
}
