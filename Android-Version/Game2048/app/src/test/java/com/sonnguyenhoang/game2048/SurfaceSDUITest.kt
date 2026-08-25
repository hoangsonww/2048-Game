package com.sonnguyenhoang.game2048

import com.sonnguyenhoang.game2048.sdui.BundledSurfaceSource
import com.sonnguyenhoang.game2048.sdui.FallbackSurfaceSource
import com.sonnguyenhoang.game2048.sdui.InMemorySurfaceSource
import com.sonnguyenhoang.game2048.sdui.Surface
import com.sonnguyenhoang.game2048.sdui.SurfaceAction
import com.sonnguyenhoang.game2048.sdui.SurfaceCatalog
import com.sonnguyenhoang.game2048.sdui.SurfaceDecoder
import com.sonnguyenhoang.game2048.sdui.SurfaceDecodingException
import com.sonnguyenhoang.game2048.sdui.SurfaceFallbackReason
import com.sonnguyenhoang.game2048.sdui.SurfaceId
import com.sonnguyenhoang.game2048.sdui.SurfaceIncompatibility
import com.sonnguyenhoang.game2048.sdui.SurfaceNode
import com.sonnguyenhoang.game2048.sdui.SurfaceNodeType
import com.sonnguyenhoang.game2048.sdui.SurfaceProblem
import com.sonnguyenhoang.game2048.sdui.SurfaceResolution
import com.sonnguyenhoang.game2048.sdui.SurfaceResolver
import com.sonnguyenhoang.game2048.sdui.SurfaceValidator
import com.sonnguyenhoang.game2048.sdui.SurfaceValue
import org.junit.Assert.*
import org.junit.Test
import java.io.File

/**
 * Server-driven UI means a payload from outside the binary decides what a
 * screen shows, so the interesting cases are all about that payload being
 * wrong: absent, malformed, aimed at a newer build, or asking for something
 * this version cannot draw.
 *
 * The invariant every one of these protects: **a surface can never blank a
 * screen or crash it.** Anything unrenderable falls back to the app's own UI,
 * and nothing here can reach the game rules.
 */
class SurfaceSDUITest {
    // MARK: - Decoding

    @Test
    fun aSurfaceDecodesFromPublishedJson() {
        val surface = SurfaceDecoder.decode(
            """
            {
              "id": "help", "schemaVersion": 1, "revision": "r1",
              "nodes": [
                { "id": "t", "type": "heading", "properties": { "text": "How to play" } },
                { "id": "b", "type": "bullets", "properties": { "items": ["Swipe", "Merge"] } },
                { "id": "c", "type": "button", "properties": { "title": "Start" },
                  "action": { "name": "newGame", "parameters": { "confirm": true } } }
              ]
            }
            """.trimIndent()
        )

        assertEquals(SurfaceId.HELP, surface.id)
        assertEquals(3, surface.nodes.size)
        assertEquals(listOf("Swipe", "Merge"), surface.nodes[1].properties["items"]?.stringListValue)
        assertEquals(SurfaceValue.Flag(true), surface.nodes[2].action?.parameters?.get("confirm"))
        assertEquals(setOf("newGame"), surface.actionNames)
    }

    /** `org.json` reads `true` as `1` unless booleans are checked first. */
    @Test
    fun aBooleanStaysABooleanAndDoesNotBecomeANumber() {
        val value = SurfaceValue.from(true)
        assertEquals(SurfaceValue.Flag(true), value)
        assertNull(value?.intValue)
        assertEquals(true, value?.boolValue)
    }

    @Test
    fun absentOptionalFieldsDecodeAsEmpty() {
        val surface = SurfaceDecoder.decode("""{ "id": "help", "nodes": [ { "id": "a", "type": "divider" } ] }""")

        assertEquals(Surface.CURRENT_SCHEMA_VERSION, surface.schemaVersion)
        assertNull(surface.minimumAppVersion)
        assertTrue(surface.nodes[0].properties.isEmpty())
        assertTrue(surface.nodes[0].children.isEmpty())
        assertNull(surface.nodes[0].action)
    }

    @Test
    fun anUnknownNodeTypeParsesRatherThanFailingThePayload() {
        val surface = SurfaceDecoder.decode("""{ "id": "help", "nodes": [ { "id": "x", "type": "hologram" } ] }""")
        assertEquals(SurfaceNodeType("hologram"), surface.nodes[0].type)
    }

    @Test(expected = SurfaceDecodingException::class)
    fun garbageIsRejectedRatherThanPartiallyDecoded() {
        SurfaceDecoder.decode("not json")
    }

    @Test
    fun aNodeWithoutAnIdOrTypeIsDroppedRatherThanFailingTheSurface() {
        val surface = SurfaceDecoder.decode(
            """{ "id": "help", "nodes": [ { "type": "heading" }, { "id": "ok", "type": "divider" } ] }"""
        )
        assertEquals(listOf("ok"), surface.nodes.map { it.id })
    }

    // MARK: - Compatibility

    @Test
    fun aPayloadBuiltForANewerContractIsRefusedWhole() {
        val surface = Surface(SurfaceId.HELP, schemaVersion = 99, nodes = listOf(heading))
        assertEquals(
            SurfaceIncompatibility.UnsupportedSchemaVersion(99, 1),
            SurfaceValidator.compatibility(surface, "1.0.0")
        )
    }

    @Test
    fun aPayloadRequiringANewerAppIsRefusedWhole() {
        val surface = Surface(SurfaceId.HELP, minimumAppVersion = "2.0.0", nodes = listOf(heading))
        assertEquals(
            SurfaceIncompatibility.RequiresNewerApp("2.0.0", "1.4.0"),
            SurfaceValidator.compatibility(surface, "1.4.0")
        )
    }

    @Test
    fun anEqualOrOlderMinimumVersionIsAccepted() {
        for (minimum in listOf("1.4.0", "1.3.9", "1.0", "0.9.1")) {
            val surface = Surface(SurfaceId.HELP, minimumAppVersion = minimum, nodes = listOf(heading))
            assertNull("$minimum should pass", SurfaceValidator.compatibility(surface, "1.4.0"))
        }
    }

    /** `1.10.0` is newer than `1.9.0`; any lexicographic comparison disagrees. */
    @Test
    fun versionComparisonIsComponentWiseNotLexicographic() {
        assertTrue(SurfaceValidator.isNewer("1.10.0", than = "1.9.0"))
        assertFalse(SurfaceValidator.isNewer("1.9.0", than = "1.10.0"))
        assertFalse(SurfaceValidator.isNewer("1.2.3", than = "1.2.3"))
        assertTrue(SurfaceValidator.isNewer("2", than = "1.9.9"))
    }

    @Test
    fun anEmptySurfaceIsNothingToRender() {
        assertEquals(
            SurfaceIncompatibility.Empty,
            SurfaceValidator.compatibility(Surface(SurfaceId.HELP), "1.0.0")
        )
    }

    // MARK: - Node validation

    @Test
    fun anUnknownNodeIsPrunedAndItsSiblingsSurvive() {
        val surface = Surface(
            SurfaceId.HELP,
            nodes = listOf(heading, SurfaceNode("future", SurfaceNodeType("hologram")))
        )
        assertEquals(1, SurfaceValidator.problems(surface).size)
        assertEquals(listOf("title"), SurfaceValidator.renderable(surface.nodes).map { it.id })
    }

    @Test
    fun aNodeMissingARequiredPropertyIsPruned() {
        val surface = Surface(
            SurfaceId.HELP,
            nodes = listOf(SurfaceNode("broken", SurfaceNodeType.HEADING), paragraph)
        )
        assertTrue(
            SurfaceValidator.problems(surface).any {
                it.nodeId == "broken" && it.kind == SurfaceProblem.Kind.MissingRequiredProperty("text")
            }
        )
        assertEquals(listOf("body"), SurfaceValidator.renderable(surface.nodes).map { it.id })
    }

    @Test
    fun duplicateNodeIdsAreReported() {
        val surface = Surface(SurfaceId.HELP, nodes = listOf(heading, heading))
        assertTrue(
            SurfaceValidator.problems(surface).any { it.kind == SurfaceProblem.Kind.DuplicateNodeId("title") }
        )
    }

    @Test
    fun anActionWithNoHandlerIsReportedButStillRenders() {
        val surface = Surface(
            SurfaceId.HELP,
            nodes = listOf(
                SurfaceNode(
                    "cta",
                    SurfaceNodeType.BUTTON,
                    mapOf("title" to SurfaceValue.Text("Go")),
                    action = SurfaceAction("launch")
                )
            )
        )
        assertTrue(
            SurfaceValidator.problems(surface, handledActions = setOf("newGame"))
                .any { it.kind == SurfaceProblem.Kind.UnhandledAction("launch") }
        )
        assertEquals(1, SurfaceValidator.renderable(surface.nodes).size)
    }

    // MARK: - Sources

    @Test
    fun anInMemorySourceReturnsOnlyWhatItHolds() {
        val source = InMemorySurfaceSource(listOf(helpSurface))
        assertEquals(SurfaceId.HELP, source.surface(SurfaceId.HELP)?.id)
        assertNull(source.surface(SurfaceId("absent")))
    }

    @Test
    fun aFallbackChainSkipsASourceThatThrows() {
        val broken = BundledSurfaceSource { "not json" }
        val chain = FallbackSurfaceSource(listOf(broken, InMemorySurfaceSource(listOf(helpSurface))))
        assertEquals(SurfaceId.HELP, chain.surface(SurfaceId.HELP)?.id)
    }

    @Test
    fun anEmptyChainFindsNothing() {
        assertNull(FallbackSurfaceSource(emptyList()).surface(SurfaceId.HELP))
    }

    // MARK: - Resolution

    @Test
    fun aGoodSurfaceResolvesToRender() {
        val resolver = SurfaceResolver(InMemorySurfaceSource(listOf(helpSurface)), "1.0.0")
        val result = resolver.resolve(SurfaceId.HELP)
        assertTrue(result is SurfaceResolution.Render)
        assertEquals(2, (result as SurfaceResolution.Render).surface.nodes.size)
        assertTrue(result.problems.isEmpty())
    }

    @Test
    fun everyFailureModeFallsBackRatherThanBlankingTheScreen() {
        val cases = mapOf<String, Pair<SurfaceResolver, SurfaceFallbackReason>>(
            "missing" to (
                SurfaceResolver(InMemorySurfaceSource(emptyList()), "1.0.0") to SurfaceFallbackReason.NotFound
                ),
            "too new" to (
                SurfaceResolver(
                    InMemorySurfaceSource(listOf(Surface(SurfaceId.HELP, schemaVersion = 99, nodes = listOf(heading)))),
                    "1.0.0"
                ) to SurfaceFallbackReason.Incompatible(SurfaceIncompatibility.UnsupportedSchemaVersion(99, 1))
                ),
            "all unknown" to (
                SurfaceResolver(
                    InMemorySurfaceSource(
                        listOf(Surface(SurfaceId.HELP, nodes = listOf(SurfaceNode("x", SurfaceNodeType("hologram")))))
                    ),
                    "1.0.0"
                ) to SurfaceFallbackReason.NoRenderableNodes
                )
        )

        for ((label, pair) in cases) {
            val (resolver, expected) = pair
            val result = resolver.resolve(SurfaceId.HELP)
            assertTrue("$label: expected a fallback", result is SurfaceResolution.Fallback)
            assertEquals(label, expected, (result as SurfaceResolution.Fallback).reason)
        }
    }

    @Test
    fun anUnreadablePayloadFallsBackRatherThanThrowing() {
        val resolver = SurfaceResolver(BundledSurfaceSource { "not json" }, "1.0.0")
        val result = resolver.resolve(SurfaceId.HELP)
        assertTrue(result is SurfaceResolution.Fallback)
        assertTrue((result as SurfaceResolution.Fallback).reason is SurfaceFallbackReason.DecodingFailed)
    }

    @Test
    fun resolutionPrunesBadNodesAndRendersTheRest() {
        val mixed = Surface(
            SurfaceId.HELP,
            nodes = listOf(
                heading,
                SurfaceNode("future", SurfaceNodeType("hologram")),
                SurfaceNode("broken", SurfaceNodeType.PARAGRAPH)
            )
        )
        val result = SurfaceResolver(InMemorySurfaceSource(listOf(mixed)), "1.0.0").resolve(SurfaceId.HELP)
        assertTrue(result is SurfaceResolution.Render)
        assertEquals(listOf("title"), (result as SurfaceResolution.Render).surface.nodes.map { it.id })
        assertEquals(2, result.problems.size)
    }

    // MARK: - The payload this app actually ships

    /**
     * The bundled help surface is the one payload that reaches real users, so
     * it is validated like any other input rather than trusted. Read straight
     * off disk because the JVM suite has no `AssetManager`.
     */
    @Test
    fun theShippedHelpSurfaceResolvesAndRendersEveryNode() {
        val asset = File("src/main/assets/surfaces/help.json")
        assertTrue("help.json must ship in assets or the surface silently never loads", asset.exists())

        val surface = SurfaceDecoder.decode(asset.readText())
        assertEquals(SurfaceId.HELP, surface.id)
        assertNull(SurfaceValidator.compatibility(surface, "1.0.0"))
        assertTrue(
            "the shipped payload must have no unknown types, missing properties, or unhandled actions",
            SurfaceValidator.problems(surface, handledActions = SurfaceCatalog.HANDLED_ACTIONS).isEmpty()
        )
        assertEquals(
            "every node in the shipped payload must render",
            surface.nodes.size,
            SurfaceValidator.renderable(surface.nodes).size
        )
    }

    /**
     * Both clients read the same contract, so the two shipped payloads must not
     * drift apart. This is the Android half of that check.
     */
    @Test
    fun theShippedPayloadMatchesTheAppleOne() {
        val android = File("src/main/assets/surfaces/help.json")
        val apple = File("../../../Game-2048/Surfaces/help.json")
        if (!apple.exists()) return // Apple tree absent in some CI layouts.

        assertEquals(
            "the two clients must ship the same surface contract",
            SurfaceDecoder.decode(apple.readText()),
            SurfaceDecoder.decode(android.readText())
        )
    }


    // MARK: - Value union

    /**
     * Each accessor must answer for *every* case, not just its own, or a
     * renderer reading the wrong field gets a silent null instead of a value.
     */
    @Test
    fun everyAccessorIsTypeAwareAcrossEveryCase() {
        val text = SurfaceValue.Text("x")
        val number = SurfaceValue.Number(3.7)
        val flag = SurfaceValue.Flag(true)
        val items = SurfaceValue.Items(listOf(SurfaceValue.Text("a"), SurfaceValue.Number(2.0)))

        assertEquals("x", text.stringValue)
        assertNull(number.stringValue)
        assertNull(flag.stringValue)
        assertNull(items.stringValue)

        assertEquals(3, number.intValue)
        assertNull(text.intValue)
        assertNull(flag.intValue)
        assertNull(items.intValue)

        assertEquals(true, flag.boolValue)
        assertNull(text.boolValue)
        assertNull(number.boolValue)

        assertEquals("non-text elements are skipped, not fatal", listOf("a"), items.stringListValue)
        assertNull(text.stringListValue)
        assertNull(number.stringListValue)
    }

    @Test
    fun everyJsonScalarShapeMapsOntoTheUnion() {
        assertEquals(SurfaceValue.Text("a"), SurfaceValue.from("a"))
        assertEquals(SurfaceValue.Flag(false), SurfaceValue.from(false))
        assertEquals(SurfaceValue.Number(2.0), SurfaceValue.from(2))
        assertEquals(SurfaceValue.Number(2.0), SurfaceValue.from(2L))
        assertEquals(SurfaceValue.Number(2.5), SurfaceValue.from(2.5))
        assertNull("an unsupported shape is dropped rather than guessed at", SurfaceValue.from(Any()))
        assertNull(SurfaceValue.from(null))
    }

    // MARK: - Nested structure

    @Test
    fun childrenDecodeAndFlattenDepthFirst() {
        val surface = SurfaceDecoder.decode(
            """
            {
              "id": "help",
              "nodes": [
                { "id": "root", "type": "divider", "children": [
                    { "id": "a", "type": "divider" },
                    { "id": "b", "type": "divider", "children": [ { "id": "c", "type": "divider" } ] }
                ] }
              ]
            }
            """.trimIndent()
        )
        assertEquals(listOf("root", "a", "b", "c"), surface.flattenedNodes.map { it.id })
    }

    @Test
    fun anActionWithoutANameIsDroppedRatherThanHalfBuilt() {
        val surface = SurfaceDecoder.decode(
            """{ "id": "help", "nodes": [ { "id": "a", "type": "divider", "action": { "parameters": {} } } ] }"""
        )
        assertNull(surface.nodes[0].action)
        assertTrue(surface.actionNames.isEmpty())
    }

    @Test
    fun aPropertyWithAnUnsupportedShapeIsDroppedAndItsSiblingsSurvive() {
        val surface = SurfaceDecoder.decode(
            """
            { "id": "help", "nodes": [ { "id": "a", "type": "heading",
              "properties": { "text": "Title", "nested": { "no": true } } } ] }
            """.trimIndent()
        )
        assertEquals("Title", surface.nodes[0].string("text"))
        assertNull(surface.nodes[0].properties["nested"])
    }

    @Test
    fun stringReturnsNullForAPropertyThatIsNotText() {
        val node = SurfaceNode("a", SurfaceNodeType.HEADING, mapOf("text" to SurfaceValue.Number(1.0)))
        assertNull(node.string("text"))
        assertNull(node.string("absent"))
    }

    // MARK: - Restricted renderers

    /**
     * A renderer that supports fewer types than the vocabulary — an older build,
     * or a compact screen — must prune the rest rather than fail.
     */
    @Test
    fun aRendererSupportingFewerTypesPrunesTheRest() {
        val surface = Surface(SurfaceId.HELP, nodes = listOf(heading, paragraph))
        assertEquals(
            listOf("title"),
            SurfaceValidator.renderable(surface.nodes, setOf(SurfaceNodeType.HEADING)).map { it.id }
        )
        assertTrue(
            SurfaceValidator.problems(surface, supportedTypes = setOf(SurfaceNodeType.HEADING))
                .any { it.kind == SurfaceProblem.Kind.UnknownNodeType(SurfaceNodeType.PARAGRAPH) }
        )
    }

    @Test
    fun pruningReachesIntoChildrenAndAnEmptiedParentSurvives() {
        val group = SurfaceNode(
            "g",
            SurfaceNodeType.DIVIDER,
            children = listOf(heading, SurfaceNode("future", SurfaceNodeType("hologram")))
        )
        val kept = SurfaceValidator.renderable(listOf(group))
        assertEquals(1, kept.size)
        assertEquals(listOf("title"), kept[0].children.map { it.id })

        val emptied = SurfaceValidator.renderable(
            listOf(SurfaceNode("g", SurfaceNodeType.DIVIDER, children = listOf(SurfaceNode("x", SurfaceNodeType("hologram")))))
        )
        assertEquals("an empty container is harmless; dropping it would be a layout surprise", 1, emptied.size)
        assertTrue(emptied[0].children.isEmpty())
    }

    /** With no handler set registered, actions are not policed at all. */
    @Test
    fun anEmptyHandlerSetDoesNotReportAnyAction() {
        val surface = Surface(
            SurfaceId.HELP,
            nodes = listOf(
                SurfaceNode(
                    "cta",
                    SurfaceNodeType.BUTTON,
                    mapOf("title" to SurfaceValue.Text("Go")),
                    action = SurfaceAction("anything")
                )
            )
        )
        assertTrue(SurfaceValidator.problems(surface).none { it.kind is SurfaceProblem.Kind.UnhandledAction })
    }

    // MARK: - Fixtures

    private val heading = SurfaceNode(
        "title",
        SurfaceNodeType.HEADING,
        mapOf("text" to SurfaceValue.Text("How to play"))
    )
    private val paragraph = SurfaceNode(
        "body",
        SurfaceNodeType.PARAGRAPH,
        mapOf("text" to SurfaceValue.Text("Swipe to move."))
    )
    private val helpSurface = Surface(SurfaceId.HELP, revision = "test-1", nodes = listOf(heading, paragraph))
}
