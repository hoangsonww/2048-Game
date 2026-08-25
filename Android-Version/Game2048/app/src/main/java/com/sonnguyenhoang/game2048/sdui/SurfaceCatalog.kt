package com.sonnguyenhoang.game2048.sdui

import android.content.Context

/**
 * The app's single entry point for server-driven content.
 *
 * One place decides where surfaces come from, which keeps the policy
 * reviewable. Today that is `assets/surfaces/` and nothing else: **the app
 * declares no INTERNET permission and makes no network request.**
 *
 * Publishing remotely later is a change to [source] alone — put a remote source
 * ahead of the bundled one in the fallback chain and every screen, renderer,
 * validator, and test keeps working. That step is deliberately not taken here
 * because it would mean shipping a network permission and a privacy disclosure
 * the game does not currently need.
 */
class SurfaceCatalog(
    source: SurfaceSource,
    appVersion: String
) {
    private val resolver = SurfaceResolver(source, appVersion)
    private val cache = mutableMapOf<SurfaceId, SurfaceResolution>()

    fun resolve(id: SurfaceId): SurfaceResolution =
        cache.getOrPut(id) { resolver.resolve(id, HANDLED_ACTIONS) }

    fun invalidate() = cache.clear()

    companion object {
        /**
         * Actions this app knows how to perform. A surface naming anything else
         * still renders; the control is disabled and the problem reported.
         */
        val HANDLED_ACTIONS: Set<String> = setOf("newGame", "dismiss")

        /** Reads surfaces from `assets/surfaces/<id>.json`. */
        fun assetSource(context: Context): SurfaceSource = BundledSurfaceSource { id ->
            runCatching {
                context.assets.open("surfaces/${id.raw}.json").bufferedReader().use { it.readText() }
            }.getOrNull()
        }

        fun forApp(context: Context, appVersion: String): SurfaceCatalog =
            SurfaceCatalog(FallbackSurfaceSource(listOf(assetSource(context))), appVersion)
    }
}
