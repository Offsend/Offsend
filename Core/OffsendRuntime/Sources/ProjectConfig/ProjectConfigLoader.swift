import Foundation
import Yams

public enum ProjectConfigLoaderError: Error, Equatable, Sendable {
    case unreadable(path: String)
    case invalidYAML(path: String, message: String)
    case unsupportedVersion(Int)
}

public struct ProjectConfigLoader: Sendable {
    public static let filename = ".offsend.yml"

    private let fileManager: FileManager
    private let gitResolver: GitRepositoryResolver

    public init(
        fileManager: FileManager = .default,
        gitResolver: GitRepositoryResolver = GitRepositoryResolver()
    ) {
        self.fileManager = fileManager
        self.gitResolver = gitResolver
    }

    public func load(from directory: URL) throws -> OffsendProjectConfig? {
        let standardized = directory.standardizedFileURL
        let repositoryRoot = (try? gitResolver.repositoryRoot(startingAt: standardized)) ?? standardized
        let configURL = repositoryRoot.appendingPathComponent(Self.filename)

        guard fileManager.fileExists(atPath: configURL.path) else {
            return nil
        }

        let contents: String
        do {
            contents = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            throw ProjectConfigLoaderError.unreadable(path: configURL.path)
        }

        let config: OffsendProjectConfig
        do {
            config = try YAMLDecoder().decode(OffsendProjectConfig.self, from: contents)
        } catch {
            throw ProjectConfigLoaderError.invalidYAML(path: configURL.path, message: error.localizedDescription)
        }

        guard config.version == 1 else {
            throw ProjectConfigLoaderError.unsupportedVersion(config.version)
        }

        return config
    }

    public func configURL(for directory: URL) -> URL? {
        let standardized = directory.standardizedFileURL
        let repositoryRoot = (try? gitResolver.repositoryRoot(startingAt: standardized)) ?? standardized
        let configURL = repositoryRoot.appendingPathComponent(Self.filename)
        return fileManager.fileExists(atPath: configURL.path) ? configURL : nil
    }
}
