package com.sonnguyenhoang.game2048.sdui

/** Why a surface cannot be rendered by this build. */
sealed interface SurfaceIncompatibility {
    data class UnsupportedSchemaVersion(val found: Int, val supported: Int) : SurfaceIncompatibility
    data class RequiresNewerApp(val minimum: String, val running: String) : SurfaceIncompatibility
    data object Empty : SurfaceIncompatibility
}

/**
 * A node that will be skipped. Problems are diagnostics; they never stop the
 * rest of the surface from rendering.
 */
data class SurfaceProblem(val nodeId: String, val kind: Kind) {
    sealed interface Kind {
        data class UnknownNodeType(val type: SurfaceNodeType) : Kind
        data class MissingRequiredProperty(val key: String) : Kind
        data class UnhandledAction(val name: String) : Kind
        data class DuplicateNodeId(val id: String) : Kind
    }
}

object SurfaceValidator {
    val requiredProperties: Map<SurfaceNodeType, List<String>> = mapOf(
        SurfaceNodeType.HEADING to listOf("text"),
        SurfaceNodeType.PARAGRAPH to listOf("text"),
        SurfaceNodeType.STEP to listOf("title"),
        SurfaceNodeType.BULLETS to listOf("items"),
        SurfaceNodeType.BUTTON to listOf("title")
    )

    fun compatibility(
        surface: Surface,
        appVersion: String,
        supportedSchemaVersion: Int = Surface.CURRENT_SCHEMA_VERSION
    ): SurfaceIncompatibility? {
        if (surface.schemaVersion > supportedSchemaVersion) {
            return SurfaceIncompatibility.UnsupportedSchemaVersion(surface.schemaVersion, supportedSchemaVersion)
        }
        val minimum = surface.minimumAppVersion
        if (minimum != null && isNewer(minimum, than = appVersion)) {
            return SurfaceIncompatibility.RequiresNewerApp(minimum, appVersion)
        }
        if (surface.nodes.isEmpty()) return SurfaceIncompatibility.Empty
        return null
    }

    fun problems(
        surface: Surface,
        supportedTypes: Set<SurfaceNodeType> = SurfaceNodeType.ALL,
        handledActions: Set<String> = emptySet()
    ): List<SurfaceProblem> {
        val problems = mutableListOf<SurfaceProblem>()
        val seen = mutableSetOf<String>()

        for (node in surface.flattenedNodes) {
            if (!seen.add(node.id)) {
                problems += SurfaceProblem(node.id, SurfaceProblem.Kind.DuplicateNodeId(node.id))
            }
            if (node.type !in supportedTypes) {
                problems += SurfaceProblem(node.id, SurfaceProblem.Kind.UnknownNodeType(node.type))
                continue
            }
            requiredProperties[node.type].orEmpty()
                .filter { node.properties[it] == null }
                .forEach { problems += SurfaceProblem(node.id, SurfaceProblem.Kind.MissingRequiredProperty(it)) }

            val action = node.action
            if (action != null && handledActions.isNotEmpty() && action.name !in handledActions) {
                problems += SurfaceProblem(node.id, SurfaceProblem.Kind.UnhandledAction(action.name))
            }
        }
        return problems
    }

    /**
     * The nodes that survive, with unrenderable ones pruned. A parent whose
     * children are all dropped still renders if it is itself valid: an empty
     * container is harmless, a crash is not.
     */
    fun renderable(
        nodes: List<SurfaceNode>,
        supportedTypes: Set<SurfaceNodeType> = SurfaceNodeType.ALL
    ): List<SurfaceNode> = nodes.mapNotNull { node ->
        if (node.type !in supportedTypes) return@mapNotNull null
        val missing = requiredProperties[node.type].orEmpty().any { node.properties[it] == null }
        if (missing) return@mapNotNull null
        node.copy(children = renderable(node.children, supportedTypes))
    }

    /** `1.10.0` is newer than `1.9.0`; any lexicographic comparison disagrees. */
    fun isNewer(version: String, than: String): Boolean {
        val left = components(version)
        val right = components(than)
        for (index in 0 until maxOf(left.size, right.size)) {
            val a = left.getOrElse(index) { 0 }
            val b = right.getOrElse(index) { 0 }
            if (a != b) return a > b
        }
        return false
    }

    private fun components(version: String): List<Int> =
        version.split(".").map { part -> part.takeWhile(Char::isDigit).toIntOrNull() ?: 0 }
}

// MARK: - Sources

/**
 * Where a surface description comes from.
 *
 * This is the seam the design exists for. The shipped app reads from its own
 * assets and makes no network call — the app has no INTERNET permission.
 * Publishing remotely later means one new implementation here and one line of
 * wiring, leaving the renderer, the validator, and every test untouched.
 */
fun interface SurfaceSource {
    fun surface(id: SurfaceId): Surface?
}

class InMemorySurfaceSource(surfaces: List<Surface>) : SurfaceSource {
    private val byId = surfaces.associateBy { it.id }
    override fun surface(id: SurfaceId): Surface? = byId[id]
}

/** Decodes a surface from JSON supplied by a loader, typically app assets. */
class BundledSurfaceSource(private val load: (SurfaceId) -> String?) : SurfaceSource {
    override fun surface(id: SurfaceId): Surface? {
        val json = load(id) ?: return null
        return SurfaceDecoder.decode(json)
    }
}

/**
 * Tries each source in order. The ordering is the policy: a future remote
 * source goes first and the bundled default last, so the app always degrades to
 * something that works.
 */
class FallbackSurfaceSource(private val sources: List<SurfaceSource>) : SurfaceSource {
    override fun surface(id: SurfaceId): Surface? {
        for (source in sources) {
            val found = runCatching { source.surface(id) }.getOrNull()
            if (found != null) return found
        }
        return null
    }
}

// MARK: - Resolution

sealed interface SurfaceResolution {
    data class Render(val surface: Surface, val problems: List<SurfaceProblem>) : SurfaceResolution
    data class Fallback(val reason: SurfaceFallbackReason) : SurfaceResolution
}

sealed interface SurfaceFallbackReason {
    data object NotFound : SurfaceFallbackReason
    data class DecodingFailed(val message: String) : SurfaceFallbackReason
    data class Incompatible(val reason: SurfaceIncompatibility) : SurfaceFallbackReason
    data object NoRenderableNodes : SurfaceFallbackReason
}

/**
 * Fetches, validates, and decides render-or-fallback in one place, so the
 * fallback rule is applied uniformly instead of re-implemented per screen.
 */
class SurfaceResolver(
    private val source: SurfaceSource,
    private val appVersion: String,
    private val supportedTypes: Set<SurfaceNodeType> = SurfaceNodeType.ALL
) {
    fun resolve(id: SurfaceId, handledActions: Set<String> = emptySet()): SurfaceResolution {
        val surface = try {
            source.surface(id)
        } catch (error: SurfaceDecodingException) {
            return SurfaceResolution.Fallback(
                SurfaceFallbackReason.DecodingFailed(error.message ?: "unreadable")
            )
        } ?: return SurfaceResolution.Fallback(SurfaceFallbackReason.NotFound)

        SurfaceValidator.compatibility(surface, appVersion)?.let {
            return SurfaceResolution.Fallback(SurfaceFallbackReason.Incompatible(it))
        }

        val problems = SurfaceValidator.problems(surface, supportedTypes, handledActions)
        val nodes = SurfaceValidator.renderable(surface.nodes, supportedTypes)
        if (nodes.isEmpty()) return SurfaceResolution.Fallback(SurfaceFallbackReason.NoRenderableNodes)

        return SurfaceResolution.Render(surface.copy(nodes = nodes), problems)
    }
}
