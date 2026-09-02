package com.sonnguyenhoang.game2048.sdui

import org.json.JSONArray
import org.json.JSONObject

/**
 * A named screen region this app is willing to have described by data rather
 * than by code.
 *
 * The game itself is never server-driven: rules, board, scoring, and undo are
 * code, and a payload cannot reach them. Surfaces cover *content* — the help
 * sheet, an announcement — the parts you would otherwise ship a build to change.
 *
 * Every surface has a hand-written native fallback. A payload that is missing,
 * malformed, or built for a newer app renders nothing and the player sees what
 * the app always shipped with.
 */
@JvmInline
value class SurfaceId(val raw: String) {
    override fun toString(): String = raw

    companion object {
        val HELP = SurfaceId("help")
    }
}

/**
 * Open rather than an enum: a build that has never heard of a type must still
 * parse the payload and skip that node, which a sealed type cannot express.
 */
@JvmInline
value class SurfaceNodeType(val raw: String) {
    override fun toString(): String = raw

    companion object {
        val HEADING = SurfaceNodeType("heading")
        val PARAGRAPH = SurfaceNodeType("paragraph")
        val STEP = SurfaceNodeType("step")
        val BULLETS = SurfaceNodeType("bullets")
        val BUTTON = SurfaceNodeType("button")
        val DIVIDER = SurfaceNodeType("divider")

        val ALL: Set<SurfaceNodeType> = setOf(HEADING, PARAGRAPH, STEP, BULLETS, BUTTON, DIVIDER)
    }
}

/**
 * A small closed union rather than `Any`, which cannot be checked or compared.
 */
sealed interface SurfaceValue {
    data class Text(val value: String) : SurfaceValue
    data class Number(val value: Double) : SurfaceValue
    data class Flag(val value: Boolean) : SurfaceValue
    data class Items(val values: List<SurfaceValue>) : SurfaceValue

    val stringValue: String?
        get() = (this as? Text)?.value

    val intValue: Int?
        get() = (this as? Number)?.value?.toInt()

    val boolValue: Boolean?
        get() = (this as? Flag)?.value

    val stringListValue: List<String>?
        get() = (this as? Items)?.values?.mapNotNull { it.stringValue }

    companion object {
        /**
         * Booleans are checked before numbers: `org.json` will happily read
         * `true` as `1`, which would silently turn a flag into a count.
         */
        fun from(value: Any?): SurfaceValue? = when (value) {
            is Boolean -> Flag(value)
            is Int -> Number(value.toDouble())
            is Long -> Number(value.toDouble())
            is Double -> Number(value)
            is String -> Text(value)
            is JSONArray -> Items((0 until value.length()).mapNotNull { from(value.opt(it)) })
            else -> null
        }
    }
}

/**
 * A named intent the host resolves against a handler map.
 *
 * Actions are names, never code: a payload can ask for "newGame" but cannot
 * describe how to start one, which is what stops data becoming execution.
 */
data class SurfaceAction(
    val name: String,
    val parameters: Map<String, SurfaceValue> = emptyMap()
)

data class SurfaceNode(
    val id: String,
    val type: SurfaceNodeType,
    val properties: Map<String, SurfaceValue> = emptyMap(),
    val children: List<SurfaceNode> = emptyList(),
    val action: SurfaceAction? = null
) {
    fun string(key: String): String? = properties[key]?.stringValue

    val flattened: List<SurfaceNode>
        get() = listOf(this) + children.flatMap { it.flattened }
}

data class Surface(
    val id: SurfaceId,
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
    val minimumAppVersion: String? = null,
    val revision: String? = null,
    val nodes: List<SurfaceNode> = emptyList()
) {
    val flattenedNodes: List<SurfaceNode>
        get() = nodes.flatMap { it.flattened }

    val actionNames: Set<String>
        get() = flattenedNodes.mapNotNull { it.action?.name }.toSet()

    companion object {
        /** Bumped only for a breaking change to the node contract. */
        const val CURRENT_SCHEMA_VERSION = 1
    }
}

/** Thrown when a payload is not a surface at all. */
class SurfaceDecodingException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * Decodes the same JSON contract the Apple clients read, using `org.json` so
 * the parser is the platform's own and the app takes on no new dependency.
 */
object SurfaceDecoder {
    fun decode(json: String): Surface = try {
        decode(JSONObject(json))
    } catch (error: org.json.JSONException) {
        throw SurfaceDecodingException("Surface JSON could not be parsed.", error)
    }

    fun decode(root: JSONObject): Surface {
        val id = root.optString("id").takeIf { it.isNotEmpty() }
            ?: throw SurfaceDecodingException("A surface needs an id.")
        return Surface(
            id = SurfaceId(id),
            schemaVersion = root.optInt("schemaVersion", Surface.CURRENT_SCHEMA_VERSION),
            minimumAppVersion = root.optString("minimumAppVersion").takeIf { it.isNotEmpty() },
            revision = root.optString("revision").takeIf { it.isNotEmpty() },
            nodes = decodeNodes(root.optJSONArray("nodes"))
        )
    }

    private fun decodeNodes(array: JSONArray?): List<SurfaceNode> {
        if (array == null) return emptyList()
        return (0 until array.length()).mapNotNull { index ->
            array.optJSONObject(index)?.let(::decodeNode)
        }
    }

    private fun decodeNode(node: JSONObject): SurfaceNode? {
        val id = node.optString("id").takeIf { it.isNotEmpty() } ?: return null
        val type = node.optString("type").takeIf { it.isNotEmpty() } ?: return null
        return SurfaceNode(
            id = id,
            type = SurfaceNodeType(type),
            properties = decodeProperties(node.optJSONObject("properties")),
            children = decodeNodes(node.optJSONArray("children")),
            action = node.optJSONObject("action")?.let(::decodeAction)
        )
    }

    private fun decodeAction(action: JSONObject): SurfaceAction? {
        val name = action.optString("name").takeIf { it.isNotEmpty() } ?: return null
        return SurfaceAction(name, decodeProperties(action.optJSONObject("parameters")))
    }

    private fun decodeProperties(properties: JSONObject?): Map<String, SurfaceValue> {
        if (properties == null) return emptyMap()
        return properties.keys().asSequence().mapNotNull { key ->
            SurfaceValue.from(properties.opt(key))?.let { key to it }
        }.toMap()
    }
}
