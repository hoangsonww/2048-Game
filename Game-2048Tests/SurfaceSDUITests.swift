import XCTest
@testable import Game_2048

/// Server-driven UI means a payload from outside the binary decides what a
/// screen shows, so the interesting cases are all about that payload being
/// wrong: absent, malformed, aimed at a newer build, or asking for something
/// this version cannot draw.
///
/// The invariant every one of these protects: **a surface can never blank a
/// screen or crash it.** Anything unrenderable falls back to the app's own UI,
/// and nothing here can reach the game rules.
final class SurfaceSDUITests: XCTestCase {
    // MARK: - Values

    func testEveryValueCaseRoundTripsThroughJSON() throws {
        let values: [SurfaceValue] = [
            .string("text"), .int(42), .double(1.5), .bool(true),
            .list([.string("a"), .int(1), .bool(false)]),
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(try JSONDecoder().decode(SurfaceValue.self, from: data), value)
        }
    }

    /// A permissive number path would decode `true` as `1`, silently turning a
    /// flag into a count.
    func testABooleanDoesNotDecodeAsANumber() throws {
        let decoded = try JSONDecoder().decode(SurfaceValue.self, from: Data("true".utf8))
        XCTAssertEqual(decoded, .bool(true))
        XCTAssertNil(decoded.intValue)
    }

    func testValueAccessorsAreTypeAware() {
        XCTAssertEqual(SurfaceValue.string("x").stringValue, "x")
        XCTAssertNil(SurfaceValue.string("x").intValue)
        XCTAssertEqual(SurfaceValue.double(3.7).intValue, 3)
        XCTAssertEqual(SurfaceValue.list([.string("a"), .int(2)]).stringListValue, ["a"])
    }

    func testAnObjectValueIsRejected() {
        XCTAssertThrowsError(try JSONDecoder().decode(SurfaceValue.self, from: Data(#"{"a":1}"#.utf8)))
    }

    // MARK: - Decoding

    func testASurfaceDecodesFromPublishedJSON() throws {
        let json = """
        {
          "id": "help", "schemaVersion": 1, "revision": "r1",
          "nodes": [
            { "id": "t", "type": "heading", "properties": { "text": "How to play" } },
            { "id": "b", "type": "bullets", "properties": { "items": ["Swipe", "Merge"] } },
            { "id": "c", "type": "button", "properties": { "title": "Start" },
              "action": { "name": "newGame", "parameters": { "confirm": true } } }
          ]
        }
        """
        let surface = try JSONDecoder().decode(Surface.self, from: Data(json.utf8))

        XCTAssertEqual(surface.id, .help)
        XCTAssertEqual(surface.nodes.count, 3)
        XCTAssertEqual(surface.nodes[1].properties["items"]?.stringListValue, ["Swipe", "Merge"])
        XCTAssertEqual(surface.nodes[2].action?.parameters["confirm"], .bool(true))
        XCTAssertEqual(surface.actionNames, ["newGame"])
    }

    func testAbsentOptionalFieldsDecodeAsEmpty() throws {
        let json = #"{ "id": "help", "nodes": [ { "id": "a", "type": "divider" } ] }"#
        let surface = try JSONDecoder().decode(Surface.self, from: Data(json.utf8))

        XCTAssertEqual(surface.schemaVersion, Surface.currentSchemaVersion)
        XCTAssertNil(surface.minimumAppVersion)
        XCTAssertTrue(surface.nodes[0].properties.isEmpty)
        XCTAssertTrue(surface.nodes[0].children.isEmpty)
    }

    func testAnUnknownNodeTypeParsesRatherThanFailingThePayload() throws {
        let json = #"{ "id": "help", "nodes": [ { "id": "x", "type": "hologram" } ] }"#
        let surface = try JSONDecoder().decode(Surface.self, from: Data(json.utf8))
        XCTAssertEqual(surface.nodes[0].type, SurfaceNodeType("hologram"))
    }

    // MARK: - Compatibility

    func testAPayloadBuiltForANewerContractIsRefusedWhole() {
        let surface = Surface(id: .help, schemaVersion: Surface.currentSchemaVersion + 1, nodes: [Self.heading])
        XCTAssertEqual(
            SurfaceValidator.compatibility(of: surface, appVersion: "1.0.0"),
            .unsupportedSchemaVersion(found: 2, supported: 1)
        )
    }

    func testAPayloadRequiringANewerAppIsRefusedWhole() {
        let surface = Surface(id: .help, minimumAppVersion: "2.0.0", nodes: [Self.heading])
        XCTAssertEqual(
            SurfaceValidator.compatibility(of: surface, appVersion: "1.4.0"),
            .requiresNewerApp(minimum: "2.0.0", running: "1.4.0")
        )
    }

    func testAnEqualOrOlderMinimumVersionIsAccepted() {
        for minimum in ["1.4.0", "1.3.9", "1.0", "0.9.1"] {
            let surface = Surface(id: .help, minimumAppVersion: minimum, nodes: [Self.heading])
            XCTAssertNil(SurfaceValidator.compatibility(of: surface, appVersion: "1.4.0"), "\(minimum) should pass")
        }
    }

    /// `1.10.0` is newer than `1.9.0`; any string comparison disagrees.
    func testVersionComparisonIsComponentWiseNotLexicographic() {
        XCTAssertTrue(SurfaceValidator.compare("1.10.0", isNewerThan: "1.9.0"))
        XCTAssertFalse(SurfaceValidator.compare("1.9.0", isNewerThan: "1.10.0"))
        XCTAssertFalse(SurfaceValidator.compare("1.2.3", isNewerThan: "1.2.3"))
        XCTAssertTrue(SurfaceValidator.compare("2", isNewerThan: "1.9.9"))
    }

    func testAnEmptySurfaceIsNothingToRender() {
        XCTAssertEqual(SurfaceValidator.compatibility(of: Surface(id: .help, nodes: []), appVersion: "1.0.0"), .empty)
    }

    // MARK: - Node validation

    func testAnUnknownNodeIsPrunedAndItsSiblingsSurvive() {
        let surface = Surface(id: .help, nodes: [
            Self.heading,
            SurfaceNode(id: "future", type: "hologram"),
        ])
        XCTAssertEqual(SurfaceValidator.problems(in: surface).count, 1)
        XCTAssertEqual(SurfaceValidator.renderable(surface.nodes).map(\.id), ["title"])
    }

    func testANodeMissingARequiredPropertyIsPruned() {
        let surface = Surface(id: .help, nodes: [SurfaceNode(id: "broken", type: .heading), Self.paragraph])
        XCTAssertTrue(SurfaceValidator.problems(in: surface)
            .contains { $0.nodeID == "broken" && $0.kind == .missingRequiredProperty("text") })
        XCTAssertEqual(SurfaceValidator.renderable(surface.nodes).map(\.id), ["body"])
    }

    func testDuplicateNodeIDsAreReported() {
        let surface = Surface(id: .help, nodes: [Self.heading, Self.heading])
        XCTAssertTrue(SurfaceValidator.problems(in: surface).contains { $0.kind == .duplicateNodeID("title") })
    }

    func testAnActionWithNoHandlerIsReportedButStillRenders() {
        let surface = Surface(id: .help, nodes: [
            SurfaceNode(id: "cta", type: .button, properties: ["title": "Go"], action: SurfaceAction(name: "launch")),
        ])
        XCTAssertTrue(SurfaceValidator.problems(in: surface, handledActions: ["newGame"])
            .contains { $0.kind == .unhandledAction("launch") })
        XCTAssertEqual(SurfaceValidator.renderable(surface.nodes).count, 1, "it renders, disabled")
    }

    // MARK: - Sources

    func testAnInMemorySourceReturnsOnlyWhatItHolds() async throws {
        let source = InMemorySurfaceSource([Self.helpSurface])
        let found = try await source.surface(.help)
        XCTAssertEqual(found?.id, .help)
        let missing = try await source.surface("absent")
        XCTAssertNil(missing)
    }

    func testABundledSourceDecodesJSONAndReportsAMissingFileAsNil() async throws {
        let data = try JSONEncoder().encode(Self.helpSurface)
        let source = BundledSurfaceSource { id in id == .help ? data : nil }
        let found = try await source.surface(.help)
        XCTAssertEqual(found, Self.helpSurface)
        let missing = try await source.surface("absent")
        XCTAssertNil(missing)
    }

    func testAFallbackChainSkipsASourceThatThrows() async throws {
        let broken = BundledSurfaceSource { _ in Data("not json".utf8) }
        let chain = FallbackSurfaceSource([broken, InMemorySurfaceSource([Self.helpSurface])])
        let found = try await chain.surface(.help)
        XCTAssertEqual(found?.id, .help, "a throwing source must not break the chain below it")
    }

    // MARK: - Resolution

    func testAGoodSurfaceResolvesToRender() async {
        let resolver = SurfaceResolver(source: InMemorySurfaceSource([Self.helpSurface]), appVersion: "1.0.0")
        guard case let .render(surface, problems) = await resolver.resolve(.help) else {
            return XCTFail("expected a render")
        }
        XCTAssertEqual(surface.nodes.count, 2)
        XCTAssertTrue(problems.isEmpty)
    }

    func testEveryFailureModeFallsBackRatherThanBlankingTheScreen() async {
        let sources: [(String, any SurfaceSource)] = [
            ("missing", InMemorySurfaceSource([])),
            ("unreadable", BundledSurfaceSource { _ in Data("not json".utf8) }),
            ("too new", InMemorySurfaceSource([Surface(id: .help, schemaVersion: 99, nodes: [Self.heading])])),
            ("all unknown", InMemorySurfaceSource([
                Surface(id: .help, nodes: [SurfaceNode(id: "x", type: "hologram")]),
            ])),
        ]
        for (label, source) in sources {
            let resolver = SurfaceResolver(source: source, appVersion: "1.0.0")
            guard case .fallback = await resolver.resolve(.help) else {
                XCTFail("\(label): expected a fallback"); continue
            }
        }
    }

    func testResolutionPrunesBadNodesAndRendersTheRest() async {
        let mixed = Surface(id: .help, nodes: [
            Self.heading,
            SurfaceNode(id: "future", type: "hologram"),
            SurfaceNode(id: "broken", type: .paragraph),
        ])
        let resolver = SurfaceResolver(source: InMemorySurfaceSource([mixed]), appVersion: "1.0.0")
        guard case let .render(surface, problems) = await resolver.resolve(.help) else {
            return XCTFail("expected a render")
        }
        XCTAssertEqual(surface.nodes.map(\.id), ["title"])
        XCTAssertEqual(problems.count, 2)
    }

    // MARK: - The payload this app actually ships

    /// The bundled help surface is the one payload that reaches real users, so
    /// it is validated like any other input rather than trusted.
    func testTheShippedHelpSurfaceResolvesAndRendersEveryNode() async throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "help", withExtension: "json")
                ?? Bundle.main.url(forResource: "help", withExtension: "json"),
            "help.json must be in the app bundle, or the shipped surface silently never loads"
        )
        let surface = try JSONDecoder().decode(Surface.self, from: Data(contentsOf: url))

        XCTAssertEqual(surface.id, .help)
        XCTAssertNil(SurfaceValidator.compatibility(of: surface, appVersion: "1.0.0"))
        XCTAssertTrue(
            SurfaceValidator.problems(in: surface, handledActions: SurfaceCatalog.handledActions).isEmpty,
            "the shipped payload must have no unknown types, missing properties, or unhandled actions"
        )
        XCTAssertEqual(
            SurfaceValidator.renderable(surface.nodes).count,
            surface.nodes.count,
            "every node in the shipped payload must render"
        )
    }

    // MARK: - Actions

    @MainActor
    func testAnActionDispatchesOnlyToItsRegisteredHandler() {
        var fired: [String] = []
        let handlers = SurfaceActionHandlers([
            "newGame": { fired.append("newGame") },
            "dismiss": { fired.append("dismiss") },
        ])

        XCTAssertTrue(handlers.canHandle(SurfaceAction(name: "newGame")))
        XCTAssertFalse(handlers.canHandle(SurfaceAction(name: "launch")))

        handlers.perform(SurfaceAction(name: "newGame"))
        handlers.perform(SurfaceAction(name: "launch"))
        XCTAssertEqual(fired, ["newGame"], "an unknown action is inert, not a crash")
    }

    // MARK: - Fixtures

    private static let heading = SurfaceNode(id: "title", type: .heading, properties: ["text": "How to play"])
    private static let paragraph = SurfaceNode(id: "body", type: .paragraph, properties: ["text": "Swipe to move."])
    private static let helpSurface = Surface(id: .help, revision: "test-1", nodes: [heading, paragraph])
}

// MARK: - Focused maintainer notes (documentation only)
//
// Surface contract test maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Round-trip every SurfaceValue case through JSON.
//
// 02. Reject object values because the contract intentionally permits only known scalar and list
//     shapes.
//
// 03. Test contract version and minimum app version as separate compatibility gates.
//
// 04. Assert version comparison numerically for multi-digit components.
//
// 05. Cover duplicate identifiers, missing required properties, and unhandled actions.
//
// 06. Verify a bad node can be pruned while valid siblings survive.
//
// 07. Exercise source fallback order with missing, throwing, and successful sources.
//
// 08. Resolve the shipped help surface to guard the production asset contract.
//
// Symbol and scenario index
//
// 01. `final class SurfaceSDUITests: XCTestCase`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `func testEveryValueCaseRoundTripsThroughJSON() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 03. `func testABooleanDoesNotDecodeAsANumber() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 04. `func testValueAccessorsAreTypeAware()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 05. `func testAnObjectValueIsRejected()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 06. `func testASurfaceDecodesFromPublishedJSON() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 07. `func testAbsentOptionalFieldsDecodeAsEmpty() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 08. `func testAnUnknownNodeTypeParsesRatherThanFailingThePayload() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 09. `func testAPayloadBuiltForANewerContractIsRefusedWhole()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 10. `func testAPayloadRequiringANewerAppIsRefusedWhole()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 11. `func testAnEqualOrOlderMinimumVersionIsAccepted()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 12. `func testVersionComparisonIsComponentWiseNotLexicographic()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 13. `func testAnEmptySurfaceIsNothingToRender()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 14. `func testAnUnknownNodeIsPrunedAndItsSiblingsSurvive()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 15. `func testANodeMissingARequiredPropertyIsPruned()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 16. `func testDuplicateNodeIDsAreReported()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 17. `func testAnActionWithNoHandlerIsReportedButStillRenders()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 18. `func testAnInMemorySourceReturnsOnlyWhatItHolds() async throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 19. `func testABundledSourceDecodesJSONAndReportsAMissingFileAsNil() async throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 20. `func testAFallbackChainSkipsASourceThatThrows() async throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 21. `func testAGoodSurfaceResolvesToRender() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 22. `func testEveryFailureModeFallsBackRatherThanBlankingTheScreen() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 23. `func testResolutionPrunesBadNodesAndRendersTheRest() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 24. `func testTheShippedHelpSurfaceResolvesAndRendersEveryNode() async throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 25. `func testAnActionDispatchesOnlyToItsRegisteredHandler()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
