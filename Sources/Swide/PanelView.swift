import AppKit
import SwiftUI
import SwideCore

enum Layout {
    static let width: CGFloat = 960
    static let height: CGFloat = 572
    static let cornerRadius: CGFloat = 26
    static let padding: CGFloat = 14
    static let tileRowHeight: CGFloat = 58
    static let thumbnailHeight: CGFloat = 176
    static let cardSpacing: CGFloat = 10
    static var maxCardWidth: CGFloat { (width - padding * 2 - cardSpacing * 2) / 3 }
    /// Coordinate space of the whole panel, for hit-testing a press-drag-release.
    static let space = "panel"
}

struct PanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchBar(model: model)
            SectionHeader(
                title: model.query.isEmpty ? "Projets récents" : "Résultats",
                trailing: model.query.isEmpty
                    ? "\(model.projects.count) projets dans \(model.config.searchRoot) · tape pour chercher"
                    : "\(model.hits.count) projet\(model.hits.count > 1 ? "s" : "")")
            TileGrid(model: model)
                .frame(height: Layout.tileRowHeight * 2 + 4, alignment: .top)
            SectionHeader(title: "Ouverts dans \(model.ide.displayName)", trailing: "du plus récent au plus ancien")
            WindowRow(model: model)
                .frame(maxHeight: .infinity, alignment: .top)
            BottomBar(model: model)
        }
        .padding(Layout.padding)
        .frame(width: Layout.width, height: Layout.height)
        .coordinateSpace(.named(Layout.space))
    }
}

// MARK: Search

struct SearchBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                SearchField(model: model)
                    .frame(height: 28)
                IDEPicker(model: model)
                CapacityGauge(count: model.windows.count, max: model.config.maxWindows, ide: model.ide)
                Button { model.showMenu?() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Menu Swide : IDE, extension, permissions…")
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 12)
            Divider().opacity(0.5)
        }
    }
}

struct SearchField: NSViewRepresentable {
    @Bindable var model: AppModel

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.placeholderString = "Ouvrir un projet…"
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        model.searchField = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.query { field.stringValue = model.query }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: AppModel
        init(model: AppModel) { self.model = model }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            MainActor.assumeIsolated { model.query = field.stringValue }
        }
    }
}

/// Cursor / VS Code, among the installed ones.
struct IDEPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        let installed = IDE.allCases.filter { $0.isInstalled || $0 == model.ide }
        if installed.count > 1 {
            Picker("IDE", selection: Binding(get: { model.ide }, set: { model.setIDE($0) })) {
                ForEach(installed, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("IDE dans lequel ouvrir les projets")
        }
    }
}

struct CapacityGauge: View {
    let count: Int
    let max: Int
    let ide: IDE

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<Swift.max(count, max), id: \.self) { i in
                    Capsule()
                        .fill(i >= count ? Color.primary.opacity(0.18) : i >= max ? Color.orange : Color.primary.opacity(0.75))
                        .frame(width: 14, height: 5)
                }
            }
            Text("\(count)/\(max)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(count > max ? Color.orange : Color.secondary)
        }
        .help("Fenêtres \(ide.displayName) ouvertes / maximum")
    }
}

struct SectionHeader: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
            Spacer()
            Text(trailing).font(.system(size: 11.5))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

// MARK: Projects

struct TileGrid: View {
    @Bindable var model: AppModel

    var body: some View {
        let hits = model.hits
        let open = model.openPaths
        if hits.isEmpty {
            Text(model.query.isEmpty ? "Aucun projet récent." : "Aucun projet ne correspond à « \(model.query) ».")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 18)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: AppModel.columns), spacing: 4) {
                ForEach(hits) { hit in
                    let item = Selection.project(hit.project.path)
                    TileView(
                        hit: hit, isOpen: open.contains(hit.project.path),
                        lastActive: model.lastActive(hit.project.path),
                        selected: model.selection == item)
                    .overlay(alignment: .bottom) {
                        if model.pendingOpen == item {
                            AutoOpenBar(duration: model.config.autoOpenDelay).padding(.horizontal, 14).padding(.bottom, 3)
                        }
                    }
                    .modifier(PointerTarget(model: model, item: item))
                }
            }
        }
    }
}

struct TileView: View {
    let hit: ProjectHit
    let isOpen: Bool
    let lastActive: Date?
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Monogram(name: hit.project.name, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(highlighted)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 5) {
                    if isOpen {
                        Text("● ouvert").foregroundStyle(.green)
                        Text("·")
                    }
                    Text(hit.project.group)
                    if let ago = lastActive.map(RelativeTime.format) {
                        Text("·")
                        Text(ago)
                    } else if !hit.project.isRecent {
                        Text("·")
                        Text("jamais ouvert")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: Layout.tileRowHeight)
        .background(SelectionBackground(selected: selected, radius: 14))
        .contentShape(Rectangle())
    }

    private var highlighted: AttributedString {
        var text = AttributedString()
        let matched = Set(hit.indices)
        for (i, ch) in hit.project.name.enumerated() {
            var part = AttributedString(String(ch))
            if matched.contains(i) { part.foregroundColor = .accentColor }
            text += part
        }
        return text
    }
}

struct Monogram: View {
    let name: String
    let size: CGFloat

    var body: some View {
        let hue = stableHue(name)
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(hue: hue, saturation: 0.55, brightness: 0.78),
                         Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Text(monogram(name))
                    .font(.system(size: size * 0.37, weight: .bold))
                    .foregroundStyle(.white))
            .frame(width: size, height: size)
    }
}

struct SelectionBackground: View {
    let selected: Bool
    let radius: CGFloat
    var resting: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.primary.opacity(selected ? 0.11 : resting))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(selected ? 0.2 : resting > 0 ? 0.06 : 0), lineWidth: 1))
    }
}

/// Hover selects; press, drag and release opens whatever is under the pointer on release.
struct PointerTarget: ViewModifier {
    let model: AppModel
    let item: Selection

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Layout.space)) } action: { model.itemFrames[item] = $0 }
            .onHover { inside in if inside { model.hover(item) } }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Layout.space))
                    .onChanged { model.pointerDragged(to: $0.location) }
                    .onEnded { model.pointerReleased(at: $0.location) })
    }
}

/// Fills up while a keyboard selection waits to open by itself.
struct AutoOpenBar: View {
    let duration: Double
    @State private var progress = 0.0

    var body: some View {
        GeometryReader { g in
            Capsule()
                .fill(Color.accentColor)
                .frame(width: g.size.width * progress, height: 2)
        }
        .frame(height: 2)
        .onAppear { withAnimation(.linear(duration: duration)) { progress = 1 } }
    }
}

// MARK: Open windows

struct WindowRow: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.windows.isEmpty {
            Text(Integrations.bridgeInstalled(in: model.ide)
                 ? "Aucune fenêtre \(model.ide.displayName) ouverte."
                 : "Installe l'extension \(model.ide.displayName) depuis le menu ⚙︎ (en haut à droite) pour voir tes fenêtres ouvertes.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 18)
        } else {
            let doomed = model.doomedWindowID
            HStack(alignment: .top, spacing: Layout.cardSpacing) {
                ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                    let item = Selection.window(window.id)
                    WindowCard(
                        window: window, index: index,
                        isFront: index == 0 && window.focused,
                        thumbnail: model.thumbnails[window.path],
                        selected: model.selection == item,
                        doomed: doomed == window.id,
                        onPin: { model.togglePin(window) },
                        onClose: { model.close(window) })
                    .overlay(alignment: .bottom) {
                        if model.pendingOpen == item {
                            AutoOpenBar(duration: model.config.autoOpenDelay).padding(.horizontal, 18).padding(.bottom, 4)
                        }
                    }
                    .frame(maxWidth: Layout.maxCardWidth)
                    .modifier(PointerTarget(model: model, item: item))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .animation(.snappy(duration: 0.2), value: model.windows.map(\.id))
        }
    }
}

struct WindowCard: View {
    let window: OpenWindow
    let index: Int
    let isFront: Bool
    let thumbnail: NSImage?
    let selected: Bool
    let doomed: Bool
    let onPin: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
                .overlay(alignment: .topLeading) {
                    if doomed {
                        Text("Sera fermé")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color(red: 0.16, green: 0.09, blue: 0.02))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange))
                            .padding(8)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.45)))
                        .padding(8)
                }
                .overlay(alignment: .bottomTrailing) {
                    if hovering || selected {
                        HStack(spacing: 6) {
                            CardButton(symbol: window.pinned ? "pin.slash" : "pin", help: "Épingler (⌘P)", action: onPin)
                            CardButton(symbol: "xmark", help: "Fermer la fenêtre (⌘⌫)", action: onClose)
                        }
                        .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(window.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if window.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 4)
                    StatusLabel(state: window.claude)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(SelectionBackground(selected: selected, radius: 18, resting: 0.04))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: doomed)
    }

    private var subtitle: String {
        if isFront { return "au premier plan" }
        return window.lastUsed.map(RelativeTime.format) ?? "—"
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                let hue = stableHue(window.name)
                LinearGradient(
                    colors: [Color(hue: hue, saturation: 0.55, brightness: 0.5),
                             Color(hue: hue, saturation: 0.45, brightness: 0.2)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(monogram(window.name))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.thumbnailHeight)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .saturation(doomed ? 0 : 1)
        .opacity(doomed ? 0.4 : 1)
    }
}

struct CardButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct StatusLabel: View {
    let state: ClaudeState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .phaseAnimator(state == .working ? [1.0, 0.35] : [1.0]) { dot, phase in
                    dot.opacity(phase)
                } animation: { _ in .easeInOut(duration: 0.8) }
            Text(label)
        }
        .font(.system(size: 12))
        .foregroundStyle(state == .idle ? Color.secondary : color)
        .lineLimit(1)
        .fixedSize()
    }

    private var label: String {
        switch state {
        case .working: "Claude travaille"
        case .waiting: "Attend ta réponse"
        case .idle: "Inactif"
        }
    }

    private var color: Color {
        switch state {
        case .working: .mint
        case .waiting: .orange
        case .idle: .gray
        }
    }
}

// MARK: Bottom bar

struct BottomBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            Group {
                if let project = model.confirmProject {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Les \(model.windows.count) fenêtres sont protégées (épinglées ou Claude au travail).")
                        Text("↵ ouvrir \(project.name) quand même").fontWeight(.semibold)
                        Text("· esc annuler")
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                } else {
                    HStack(spacing: 16) {
                        KeyHint(keys: ["↑", "↓", "←", "→"], label: "naviguer")
                        KeyHint(keys: ["↵"], label: "ouvrir")
                        KeyHint(keys: ["⌘", "↵"], label: "sans fermer")
                        KeyHint(keys: ["⌘", "1–3"], label: "fenêtre")
                        KeyHint(keys: ["⌘", "⌫"], label: "fermer")
                        KeyHint(keys: ["⌘", "P"], label: "épingler")
                        KeyHint(keys: ["esc"], label: "quitter")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 10)
        }
    }
}

struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
            }
            Text(label)
                .font(.system(size: 12))
                .padding(.leading, 3)
        }
        .foregroundStyle(.secondary)
    }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f
    }()

    static func format(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "à l'instant" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
