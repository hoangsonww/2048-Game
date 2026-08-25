import Foundation

/// Why a surface cannot be rendered by this build.
enum SurfaceIncompatibility: Hashable, CustomStringConvertible {
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case requiresNewerApp(minimum: String, running: String)
    case empty

    var description: String {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            "Surface schema version \(found) is newer than this build supports (\(supported))."
        case let .requiresNewerApp(minimum, running):
            "Surface requires app version \(minimum); this build is \(running)."
        case .empty:
            "Surface contains no renderable nodes."
        }
    }
}

/// A node that will be skipped. Problems are diagnostics; they never stop the
/// rest of the surface from rendering.
struct SurfaceProblem: Hashable, CustomStringConvertible {
    enum Kind: Hashable {
        case unknownNodeType(SurfaceNodeType)
        case missingRequiredProperty(String)
        case unhandledAction(String)
        case duplicateNodeID(String)
    }

    let nodeID: String
    let kind: Kind

    var description: String {
        switch kind {
        case let .unknownNodeType(type): "\(nodeID): unknown node type '\(type)'."
        case let .missingRequiredProperty(key): "\(nodeID): missing required property '\(key)'."
        case let .unhandledAction(name): "\(nodeID): no handler for action '\(name)'."
        case let .duplicateNodeID(id): "\(nodeID): duplicate node id '\(id)'."
        }
    }
}

enum SurfaceValidator {
    static let requiredProperties: [SurfaceNodeType: [String]] = [
        .heading: ["text"],
        .paragraph: ["text"],
        .step: ["title"],
        .bullets: ["items"],
        .button: ["title"],
    ]

    static func compatibility(
        of surface: Surface,
        appVersion: String,
        supportedSchemaVersion: Int = Surface.currentSchemaVersion
    ) -> SurfaceIncompatibility? {
        if surface.schemaVersion > supportedSchemaVersion {
            return .unsupportedSchemaVersion(found: surface.schemaVersion, supported: supportedSchemaVersion)
        }
        if let minimum = surface.minimumAppVersion, compare(minimum, isNewerThan: appVersion) {
            return .requiresNewerApp(minimum: minimum, running: appVersion)
        }
        if surface.nodes.isEmpty { return .empty }
        return nil
    }

    static func problems(
        in surface: Surface,
        supportedTypes: Set<SurfaceNodeType> = SurfaceNodeType.all,
        handledActions: Set<String> = []
    ) -> [SurfaceProblem] {
        var problems: [SurfaceProblem] = []
        var seen = Set<String>()

        for node in surface.flattenedNodes {
            if !seen.insert(node.id).inserted {
                problems.append(SurfaceProblem(nodeID: node.id, kind: .duplicateNodeID(node.id)))
            }
            guard supportedTypes.contains(node.type) else {
                problems.append(SurfaceProblem(nodeID: node.id, kind: .unknownNodeType(node.type)))
                continue
            }
            for key in requiredProperties[node.type] ?? [] where node.properties[key] == nil {
                problems.append(SurfaceProblem(nodeID: node.id, kind: .missingRequiredProperty(key)))
            }
            if let action = node.action, !handledActions.isEmpty, !handledActions.contains(action.name) {
                problems.append(SurfaceProblem(nodeID: node.id, kind: .unhandledAction(action.name)))
            }
        }
        return problems
    }

    static func renderable(
        _ nodes: [SurfaceNode],
        supportedTypes: Set<SurfaceNodeType> = SurfaceNodeType.all
    ) -> [SurfaceNode] {
        nodes.compactMap { node in
            guard supportedTypes.contains(node.type) else { return nil }
            for key in requiredProperties[node.type] ?? [] where node.properties[key] == nil {
                return nil
            }
            return SurfaceNode(
                id: node.id,
                type: node.type,
                properties: node.properties,
                children: renderable(node.children, supportedTypes: supportedTypes),
                action: node.action
            )
        }
    }

    /// `1.10.0` is newer than `1.9.0`; any lexicographic comparison disagrees.
    static func compare(_ lhs: String, isNewerThan rhs: String) -> Bool {
        let left = components(of: lhs)
        let right = components(of: rhs)
        for index in 0 ..< max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(of version: String) -> [Int] {
        version.split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}

// MARK: - Sources

/// Where a surface description comes from.
///
/// This is the seam the design exists for. The shipped app reads from its own
/// bundle and makes no network call; publishing remotely later means conforming
/// one new type here and changing one line of wiring, leaving the renderer, the
/// validator, and every test untouched.
protocol SurfaceSource: Sendable {
    func surface(_ id: SurfaceID) async throws -> Surface?
}

struct InMemorySurfaceSource: SurfaceSource {
    private let surfaces: [SurfaceID: Surface]

    init(_ surfaces: [Surface]) {
        self.surfaces = Dictionary(surfaces.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    func surface(_ id: SurfaceID) async throws -> Surface? { surfaces[id] }
}

struct BundledSurfaceSource: SurfaceSource {
    private let load: @Sendable (SurfaceID) -> Data?

    init(load: @escaping @Sendable (SurfaceID) -> Data?) { self.load = load }

    init(bundle: Bundle = .main, subdirectory: String? = nil) {
        self.init { id in
            guard let url = bundle.url(forResource: id.rawValue, withExtension: "json", subdirectory: subdirectory)
            else { return nil }
            return try? Data(contentsOf: url)
        }
    }

    func surface(_ id: SurfaceID) async throws -> Surface? {
        guard let data = load(id) else { return nil }
        return try JSONDecoder().decode(Surface.self, from: data)
    }
}

/// Tries each source in order. The ordering is the policy: a future remote
/// source goes first and the bundled default last, so the app always degrades
/// to something that works.
struct FallbackSurfaceSource: SurfaceSource {
    private let sources: [any SurfaceSource]

    init(_ sources: [any SurfaceSource]) { self.sources = sources }

    func surface(_ id: SurfaceID) async throws -> Surface? {
        for source in sources {
            if let surface = try? await source.surface(id) { return surface }
        }
        return nil
    }
}

// MARK: - Resolution

enum SurfaceResolution {
    case render(Surface, problems: [SurfaceProblem])
    case fallback(reason: SurfaceFallbackReason)
}

enum SurfaceFallbackReason: Hashable, CustomStringConvertible {
    case notFound
    case decodingFailed(String)
    case incompatible(SurfaceIncompatibility)
    case noRenderableNodes

    var description: String {
        switch self {
        case .notFound: "No surface was published for this id."
        case let .decodingFailed(message): "Surface could not be decoded: \(message)."
        case let .incompatible(reason): reason.description
        case .noRenderableNodes: "Every node in the surface was skipped."
        }
    }
}

/// Fetches, validates, and decides render-or-fallback in one place, so the
/// fallback rule is applied uniformly instead of re-implemented per screen.
struct SurfaceResolver: Sendable {
    private let source: any SurfaceSource
    private let appVersion: String
    private let supportedTypes: Set<SurfaceNodeType>

    init(
        source: any SurfaceSource,
        appVersion: String = SurfaceResolver.bundleVersion,
        supportedTypes: Set<SurfaceNodeType> = SurfaceNodeType.all
    ) {
        self.source = source
        self.appVersion = appVersion
        self.supportedTypes = supportedTypes
    }

    static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    func resolve(_ id: SurfaceID, handledActions: Set<String> = []) async -> SurfaceResolution {
        let fetched: Surface?
        do {
            fetched = try await source.surface(id)
        } catch {
            return .fallback(reason: .decodingFailed(String(describing: error)))
        }

        guard let surface = fetched else { return .fallback(reason: .notFound) }

        if let incompatibility = SurfaceValidator.compatibility(of: surface, appVersion: appVersion) {
            return .fallback(reason: .incompatible(incompatibility))
        }

        let problems = SurfaceValidator.problems(
            in: surface,
            supportedTypes: supportedTypes,
            handledActions: handledActions
        )
        let nodes = SurfaceValidator.renderable(surface.nodes, supportedTypes: supportedTypes)
        guard !nodes.isEmpty else { return .fallback(reason: .noRenderableNodes) }

        return .render(
            Surface(
                id: surface.id,
                schemaVersion: surface.schemaVersion,
                minimumAppVersion: surface.minimumAppVersion,
                revision: surface.revision,
                nodes: nodes
            ),
            problems: problems
        )
    }
}
