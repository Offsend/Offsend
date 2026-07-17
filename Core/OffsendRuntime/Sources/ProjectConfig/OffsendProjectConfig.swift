import Foundation

public struct OffsendProjectConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var check: OffsendProjectCheckConfig?
    public var ignore: OffsendProjectIgnoreConfig?
    public var hooks: OffsendProjectHooksConfig?
    public var context: OffsendProjectContextConfig?

    public init(
        version: Int = 1,
        check: OffsendProjectCheckConfig? = nil,
        ignore: OffsendProjectIgnoreConfig? = nil,
        hooks: OffsendProjectHooksConfig? = nil,
        context: OffsendProjectContextConfig? = nil
    ) {
        self.version = version
        self.check = check
        self.ignore = ignore
        self.hooks = hooks
        self.context = context
    }
}

public struct OffsendProjectCheckConfig: Codable, Equatable, Sendable {
    public var failOn: String?
    public var policy: Bool?
    public var exclude: [String]?
    public var detectors: OffsendProjectDetectorsConfig?
    public var dictionaries: [OffsendProjectDictionaryEntry]?

    enum CodingKeys: String, CodingKey {
        case failOn = "fail_on"
        case policy
        case exclude
        case detectors
        case dictionaries
    }

    public init(
        failOn: String? = nil,
        policy: Bool? = nil,
        exclude: [String]? = nil,
        detectors: OffsendProjectDetectorsConfig? = nil,
        dictionaries: [OffsendProjectDictionaryEntry]? = nil
    ) {
        self.failOn = failOn
        self.policy = policy
        self.exclude = exclude
        self.detectors = detectors
        self.dictionaries = dictionaries
    }
}

public struct OffsendProjectIgnoreConfig: Codable, Equatable, Sendable {
    /// When `false` (default), AI ignore files are kept out of git via `.git/info/exclude`.
    public var commit: Bool?
    /// Team-mandatory patterns materialized into AI ignore files by `offsend sync`.
    public var patterns: [String]?

    public init(commit: Bool? = nil, patterns: [String]? = nil) {
        self.commit = commit
        self.patterns = patterns
    }

    /// Effective commit flag: absent means do not commit ignore files.
    public var commitsIgnoreFiles: Bool { commit ?? false }
}

public struct OffsendProjectDetectorsConfig: Codable, Equatable, Sendable {
    public var disable: [String]?

    public init(disable: [String]? = nil) {
        self.disable = disable
    }
}

public struct OffsendProjectDictionaryEntry: Codable, Equatable, Sendable {
    public var kind: String
    public var value: String

    public init(kind: String, value: String) {
        self.kind = kind
        self.value = value
    }
}

public struct OffsendProjectHooksConfig: Codable, Equatable, Sendable {
    public var type: String?
    public var failOn: String?
    public var policy: Bool?
    /// When `false` (default), AI editor hook files are kept out of git via `.git/info/exclude`.
    public var publish: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case failOn = "fail_on"
        case policy
        case publish
    }

    public init(
        type: String? = nil,
        failOn: String? = nil,
        policy: Bool? = nil,
        publish: Bool? = nil
    ) {
        self.type = type
        self.failOn = failOn
        self.policy = policy
        self.publish = publish
    }

    /// Effective publish flag: absent means do not publish hooks to the repo.
    public var publishesHooks: Bool { publish ?? false }
}
