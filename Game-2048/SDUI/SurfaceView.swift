import SwiftUI

/// Named intents a rendered surface may trigger.
///
/// A surface names an action; the host decides what it means. That indirection
/// is the boundary that keeps a data payload from becoming an execution vector.
struct SurfaceActionHandlers {
    private let handlers: [String: @MainActor () -> Void]

    init(_ handlers: [String: @MainActor () -> Void] = [:]) { self.handlers = handlers }

    var names: Set<String> { Set(handlers.keys) }

    func canHandle(_ action: SurfaceAction) -> Bool { handlers[action.name] != nil }

    @MainActor
    func perform(_ action: SurfaceAction) { handlers[action.name]?() }
}

/// Renders one validated node using the app's own design system.
///
/// The renderer owns every visual decision. A surface supplies content and
/// structure only — never colours, fonts, or spacing — so a published payload
/// cannot make the screen look off-brand or unreadable.
struct SurfaceNodeView: View {
    let node: SurfaceNode
    var handlers = SurfaceActionHandlers()

    private let ink = Color(red: 0.141, green: 0.137, blue: 0.122)
    private let accent = Color(red: 0.914, green: 0.388, blue: 0.271)

    var body: some View {
        switch node.type {
        case .heading:
            Text(node.string("text") ?? "")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph:
            Text(node.string("text") ?? "")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .step:
            // Mirrors the hand-written HelpRow so a described step and a coded
            // one are visually indistinguishable.
            HStack(alignment: .top, spacing: 18) {
                Text(node.string("number") ?? "")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(node.string("title") ?? "").font(.headline)
                    if let detail = node.string("detail") {
                        Text(detail).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }
            }
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Divider() }

        case .bullets:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(accent)
                        Text(item)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .button:
            Button {
                if let action = node.action { handlers.perform(action) }
            } label: {
                Text(node.string("title") ?? "")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            // Shown disabled rather than hidden: a dead control is confusing,
            // a control that silently vanished is worse.
            .disabled(node.action.map { !handlers.canHandle($0) } ?? true)

        case .divider:
            Divider()

        default:
            // Unreachable for a validated tree, and deliberately leaves no
            // trace rather than rendering a placeholder.
            EmptyView()
        }
    }

    private var items: [String] { node.properties["items"]?.stringListValue ?? [] }
}

/// Renders a resolved surface, or the caller's native content when there is
/// nothing valid to render.
///
/// Every call site supplies a fallback. That is what makes the feature
/// additive: delete every published surface and the app is exactly what it
/// shipped as.
struct SurfaceView<Fallback: View>: View {
    let resolution: SurfaceResolution?
    var handlers = SurfaceActionHandlers()
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        switch resolution {
        case let .render(surface, _):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(surface.nodes) { node in
                    SurfaceNodeView(node: node, handlers: handlers)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .fallback, .none:
            fallback()
        }
    }
}
