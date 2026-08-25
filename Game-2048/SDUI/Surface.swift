import Foundation

/// A named screen region this app is willing to have described by data rather
/// than by code.
///
/// The game itself is never server-driven: rules, board, scoring, and undo are
/// code, and a payload cannot reach them. Surfaces cover *content* — the help
/// sheet, an announcement — the parts you would otherwise ship a build to
/// change.
///
/// Every surface has a hand-written native fallback. A payload that is missing,
/// malformed, or built for a newer app renders nothing and the app shows what
/// it always shipped with.
struct SurfaceID: RawRepresentable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.init(rawValue: value) }

    var description: String { rawValue }

    static let help: SurfaceID = "help"
}

/// Open rather than an enum: a build that has never heard of a type must still
/// parse the payload and skip that node, which a closed enum cannot express.
struct SurfaceNodeType: RawRepresentable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.init(rawValue: value) }

    var description: String { rawValue }

    static let heading: SurfaceNodeType = "heading"
    static let paragraph: SurfaceNodeType = "paragraph"
    static let step: SurfaceNodeType = "step"
    static let bullets: SurfaceNodeType = "bullets"
    static let button: SurfaceNodeType = "button"
    static let divider: SurfaceNodeType = "divider"

    static let all: Set<SurfaceNodeType> = [.heading, .paragraph, .step, .bullets, .button, .divider]
}

/// A small closed union rather than `Any`, which is neither `Sendable`,
/// `Codable`, nor checkable.
enum SurfaceValue: Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case list([SurfaceValue])

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case let .int(value): value
        case let .double(value): Int(value)
        default: nil
        }
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var stringListValue: [String]? {
        guard case let .list(values) = self else { return nil }
        return values.compactMap(\.stringValue)
    }
}

extension SurfaceValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}

extension SurfaceValue: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool before Int: a permissive number path would turn a flag into 1.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SurfaceValue].self) {
            self = .list(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A surface value must be a string, number, boolean, or list."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .list(values): try container.encode(values)
        }
    }
}

/// A named intent the host resolves against a handler map.
///
/// Actions are names, never code: a payload can ask for "newGame" but cannot
/// describe how to start one, which is what stops data becoming execution.
struct SurfaceAction: Hashable, Codable {
    let name: String
    let parameters: [String: SurfaceValue]

    init(name: String, parameters: [String: SurfaceValue] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

struct SurfaceNode: Hashable, Codable, Identifiable {
    let id: String
    let type: SurfaceNodeType
    let properties: [String: SurfaceValue]
    let children: [SurfaceNode]
    let action: SurfaceAction?

    init(
        id: String,
        type: SurfaceNodeType,
        properties: [String: SurfaceValue] = [:],
        children: [SurfaceNode] = [],
        action: SurfaceAction? = nil
    ) {
        self.id = id
        self.type = type
        self.properties = properties
        self.children = children
        self.action = action
    }

    func string(_ key: String) -> String? { properties[key]?.stringValue }

    var flattened: [SurfaceNode] { [self] + children.flatMap(\.flattened) }

    private enum CodingKeys: String, CodingKey { case id, type, properties, children, action }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(SurfaceNodeType.self, forKey: .type)
        properties = try container.decodeIfPresent([String: SurfaceValue].self, forKey: .properties) ?? [:]
        children = try container.decodeIfPresent([SurfaceNode].self, forKey: .children) ?? []
        action = try container.decodeIfPresent(SurfaceAction.self, forKey: .action)
    }
}

struct Surface: Hashable, Codable, Identifiable {
    /// Bumped only for a breaking change to the node contract.
    static let currentSchemaVersion = 1

    let id: SurfaceID
    let schemaVersion: Int
    let minimumAppVersion: String?
    let revision: String?
    let nodes: [SurfaceNode]

    init(
        id: SurfaceID,
        schemaVersion: Int = Surface.currentSchemaVersion,
        minimumAppVersion: String? = nil,
        revision: String? = nil,
        nodes: [SurfaceNode]
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.minimumAppVersion = minimumAppVersion
        self.revision = revision
        self.nodes = nodes
    }

    var flattenedNodes: [SurfaceNode] { nodes.flatMap(\.flattened) }

    var actionNames: Set<String> { Set(flattenedNodes.compactMap(\.action?.name)) }

    private enum CodingKeys: String, CodingKey { case id, schemaVersion, minimumAppVersion, revision, nodes }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SurfaceID.self, forKey: .id)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Surface.currentSchemaVersion
        minimumAppVersion = try container.decodeIfPresent(String.self, forKey: .minimumAppVersion)
        revision = try container.decodeIfPresent(String.self, forKey: .revision)
        nodes = try container.decodeIfPresent([SurfaceNode].self, forKey: .nodes) ?? []
    }
}
