import Foundation

public struct OffsendProjectConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var check: OffsendProjectCheckConfig?
    public var hooks: OffsendProjectHooksConfig?
    public var context: OffsendProjectContextConfig?

    public init(
        version: Int = 1,
        check: OffsendProjectCheckConfig? = nil,
        hooks: OffsendProjectHooksConfig? = nil,
        context: OffsendProjectContextConfig? = nil
    ) {
        self.version = version
        self.check = check
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

    enum CodingKeys: String, CodingKey {
        case type
        case failOn = "fail_on"
        case policy
    }

    public init(
        type: String? = nil,
        failOn: String? = nil,
        policy: Bool? = nil
    ) {
        self.type = type
        self.failOn = failOn
        self.policy = policy
    }
}
