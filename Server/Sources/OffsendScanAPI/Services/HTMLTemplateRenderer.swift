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
        let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "mustache" else { continue }
            let name = fileURL.deletingPathExtension().lastPathComponent
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            try library.register(contents, named: name)
            loadedCount += 1
        }
        guard loadedCount > 0 else {
            throw LoadError.missingResources
        }
        return HTMLTemplateRenderer(library: library)
    }

    func landingPage(siteURL: String) throws -> String {
        var context = pageContext()
        for (key, value) in PageMetadata.landingContext(siteURL: siteURL) {
            context[key] = value
        }
        return try render(named: "landing", context: context)
    }

    func pollingPage(jobID: String) throws -> String {
        try render(named: "polling", context: pageContext(["jobID": jobID], noindex: true))
    }

    func pollingPreviewPage() throws -> String {
        try render(named: "polling", context: pageContext(noindex: true, debug: true))
    }

    func report(
        jobID: String,
        repoURL: String,
        reportJSON: String,
        generatedAt: Date,
        reportTTL: Duration = .seconds(172_800)
    ) throws -> String {
        var context = ReportHTMLRenderer.makeContext(
            jobID: jobID,
            repoURL: repoURL,
            reportJSON: reportJSON,
            generatedAt: generatedAt,
            reportTTL: reportTTL
        )
        context.navScanActive = true
        return try render(named: "report", context: context)
    }

    private func pageContext(_ values: [String: String] = [:], noindex: Bool = false, debug: Bool = false) -> [String: Any] {
        var context: [String: Any] = ["navScanActive": true]
        if noindex {
            context["noindex"] = true
        }
        if debug {
            context["debug"] = true
        }
        for (key, value) in values where !value.isEmpty {
            context[key] = value
        }
        return context
    }

    private func render(named template: String, context: Any) throws -> String {
        guard let html = library.render(context, withTemplate: template) else {
            throw LoadError.templateNotFound(template)
        }
        return html
    }
}
