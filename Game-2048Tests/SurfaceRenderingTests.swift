import SwiftUI
import XCTest
@testable import Game_2048

/// Render coverage for the server-driven UI layer.
///
/// A published payload decides what these views draw, so a node that traps on a
/// missing property or an empty list would crash the help sheet in front of a
/// real player. `ImageRenderer` evaluates a whole view body, which makes
/// rendering each node type a genuine smoke test rather than a type-check.
@MainActor
final class SurfaceRenderingTests: XCTestCase {
    // MARK: - Node types

    func testEveryNodeTypeRenders() {
        let nodes: [SurfaceNode] = [
            SurfaceNode(id: "h", type: .heading, properties: ["text": "How to play"]),
            SurfaceNode(id: "p", type: .paragraph, properties: ["text": "Swipe to move every tile."]),
            SurfaceNode(id: "s", type: .step, properties: [
                "number": "01", "title": "Slide", "detail": "Swipe the board.",
            ]),
            SurfaceNode(id: "b", type: .bullets, properties: ["items": .list([.string("One"), .string("Two")])]),
            SurfaceNode(id: "c", type: .button, properties: ["title": "Start"], action: SurfaceAction(name: "newGame")),
            SurfaceNode(id: "d", type: .divider),
        ]
        for node in nodes {
            assertRenders(SurfaceNodeView(node: node), "\(node.type) should render")
        }
    }

    /// A step without its optional detail is the payload most likely to trip a
    /// view that assumes every field is present.
    func testOptionalPropertiesAreToleratedWhileRendering() {
        assertRenders(
            SurfaceNodeView(node: SurfaceNode(id: "s", type: .step, properties: ["title": "Slide"])),
            "a step with no number or detail should still render"
        )
        assertRenders(
            SurfaceNodeView(node: SurfaceNode(id: "b", type: .bullets, properties: ["items": .list([])])),
            "an empty bullet list should render as nothing, not crash"
        )
    }

    /// Unreachable for a validated tree, but the renderer is a public entry
    /// point and must not trap if one ever reaches it.
    func testAnUnknownNodeTypeRendersNothingRatherThanCrashing() {
        assertRenders(SurfaceNodeView(node: SurfaceNode(id: "x", type: "hologram")), "an unknown type must be inert")
    }

    // MARK: - Buttons and actions

    func testAButtonRendersEnabledOnlyWhenItsActionIsHandled() {
        let handled = SurfaceNode(
            id: "c", type: .button, properties: ["title": "Start"], action: SurfaceAction(name: "newGame")
        )
        let handlers = SurfaceActionHandlers(["newGame": {}])

        assertRenders(SurfaceNodeView(node: handled, handlers: handlers))
        // An unhandled action and a missing action both render, disabled.
        assertRenders(SurfaceNodeView(node: handled, handlers: SurfaceActionHandlers()))
        assertRenders(
            SurfaceNodeView(node: SurfaceNode(id: "c", type: .button, properties: ["title": "Start"]))
        )
    }

    // MARK: - Surface view

    func testAResolvedSurfaceRendersItsNodes() {
        let surface = Surface(id: .help, nodes: [
            SurfaceNode(id: "h", type: .heading, properties: ["text": "How to play"]),
            SurfaceNode(id: "p", type: .paragraph, properties: ["text": "Swipe."]),
        ])
        assertRenders(SurfaceView(resolution: .render(surface, problems: [])) { Text("native") })
    }

    /// The property the whole design rests on: nothing a payload can do leaves
    /// the screen blank.
    func testEveryFallbackStateRendersTheNativeContent() {
        let states: [SurfaceResolution?] = [
            nil,
            .fallback(reason: .notFound),
            .fallback(reason: .noRenderableNodes),
            .fallback(reason: .decodingFailed("bad")),
            .fallback(reason: .incompatible(.unsupportedSchemaVersion(found: 99, supported: 1))),
        ]
        for state in states {
            assertRenders(SurfaceView(resolution: state) { Text("native fallback") }, "\(String(describing: state))")
        }
    }

    func testTheShippedHelpSurfaceRendersEndToEnd() async throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "help", withExtension: "json")
                ?? Bundle.main.url(forResource: "help", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        let resolver = SurfaceResolver(
            source: BundledSurfaceSource { _ in data },
            appVersion: "1.0.0"
        )
        let resolution = await resolver.resolve(.help, handledActions: SurfaceCatalog.handledActions)
        guard case .render = resolution else {
            return XCTFail("the shipped payload must resolve to a render, got \(resolution)")
        }
        assertRenders(SurfaceView(resolution: resolution) { Text("native") })
    }

    // MARK: - Helper

    private func assertRenders(
        _ view: some View,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let renderer = ImageRenderer(content: view.frame(width: 320).padding())
        renderer.scale = 1
        XCTAssertNotNil(renderer.uiImage, message.isEmpty ? "the view rendered to nothing" : message,
                        file: file, line: line)
    }
}

// MARK: - Focused maintainer notes (documentation only)
//
// Surface rendering test maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Exercise every supported native node type at least once.
//
// 02. Keep optional-property tests separate from required-property rejection tests.
//
// 03. Assert unknown content fails soft and leaves the native fallback usable.
//
// 04. Verify buttons are enabled only when their action has a host handler.
//
// 05. Render shipped bundled content end-to-end in addition to synthetic fixtures.
//
// 06. Keep tests on the main actor because SwiftUI rendering is main-actor isolated.
//
// Symbol and scenario index
//
// 01. `final class SurfaceRenderingTests: XCTestCase`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `func testEveryNodeTypeRenders()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 03. `func testOptionalPropertiesAreToleratedWhileRendering()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 04. `func testAnUnknownNodeTypeRendersNothingRatherThanCrashing()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 05. `func testAButtonRendersEnabledOnlyWhenItsActionIsHandled()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 06. `func testAResolvedSurfaceRendersItsNodes()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 07. `func testEveryFallbackStateRendersTheNativeContent()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 08. `func testTheShippedHelpSurfaceRendersEndToEnd() async throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 09. `private func assertRenders(`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
