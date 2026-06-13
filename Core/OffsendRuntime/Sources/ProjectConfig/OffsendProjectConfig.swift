import Foundation

public struct OffsendProjectConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var check: OffsendProjectCheckConfig?
    public var hooks: OffsendProjectHooksConfig?

    public init(
        version: Int = 1,
        check: OffsendProjectCheckConfig? = nil,
        hooks: OffsendProjectHooksConfig? = nil
    ) {
        self.version = version
        self.check = check
        self.hooks = hooks
    }
}

public struct OffsendProjectCheckConfig: Codable, Equatable, Sendable {
    public var failOn: String?
    public var policy: Bool?
    public var exclude: [String]?
    public var detectors: OffsendProjectDetectorsConfig?

    enum CodingKeys: String, CodingKey {
        case failOn = "fail_on"
        case policy
        case exclude
        case detectors
    }

    public init(
        failOn: String? = nil,
        policy: Bool? = nil,
        exclude: [String]? = nil,
        detectors: OffsendProjectDetectorsConfig? = nil
    ) {
        self.failOn = failOn
        self.policy = policy
        self.exclude = exclude
        self.detectors = detectors
    }
}

public struct OffsendProjectDetectorsConfig: Codable, Equatable, Sendable {
    public var disable: [String]?

    public init(disable: [String]? = nil) {
        self.disable = disable
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
