import Foundation

/// The app's single entry point for server-driven content.
///
/// One place decides where surfaces come from, which is what keeps the policy
/// reviewable. Today that is the app bundle and nothing else: **the game makes
/// no network request of any kind.**
///
/// Publishing remotely later is a change to `source` alone — put a remote
/// source ahead of the bundled one in the fallback chain and every screen,
/// renderer, validator, and test keeps working unchanged. That step is
/// deliberately not taken here because it would mean shipping a network
/// permission and a privacy policy the game does not currently need.
actor SurfaceCatalog {
    static let shared = SurfaceCatalog()

    private let resolver: SurfaceResolver
    private var cache: [SurfaceID: SurfaceResolution] = [:]

    init(source: (any SurfaceSource)? = nil, appVersion: String = SurfaceResolver.bundleVersion) {
        // The order is the policy. A remote source would slot in ahead of the
        // bundled one; the bundled default stays last so there is always a
        // floor below every other source.
        let resolved = source ?? FallbackSurfaceSource([
            BundledSurfaceSource(bundle: .main, subdirectory: "Surfaces"),
            BundledSurfaceSource(bundle: .main),
        ])
        resolver = SurfaceResolver(source: resolved, appVersion: appVersion)
    }

    /// Actions this app knows how to perform. A surface naming anything else
    /// still renders; the control is simply disabled and the problem reported.
    static let handledActions: Set<String> = ["newGame", "dismiss"]

    func resolve(_ id: SurfaceID) async -> SurfaceResolution {
        if let cached = cache[id] { return cached }
        let resolution = await resolver.resolve(id, handledActions: Self.handledActions)
        cache[id] = resolution
        return resolution
    }

    func invalidate() { cache.removeAll() }
}

// MARK: - Focused maintainer notes (documentation only)
//
// Surface catalog maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Cache only resolved content, never executable behavior or arbitrary code.
//
// 02. Keep invalidation explicit so tests and future refresh actions can force a clean lookup.
//
// 03. Resolve each surface against the running app version before returning it to presentation.
//
// 04. Treat source failure as a fallback condition rather than a blank-screen condition.
//
// 05. Keep actor isolation around cache mutation and asynchronous source access.
//
// 06. Do not let remote availability gate core game play or the native fallback.
//
// Symbol and scenario index
//
// 01. `actor SurfaceCatalog`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `init(source: (any SurfaceSource)? = nil, appVersion: String = SurfaceResolver.bundleVersion)`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 03. `func resolve(_ id: SurfaceID) async -> SurfaceResolution`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 04. `func invalidate() { cache.removeAll() }`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
