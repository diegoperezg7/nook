import AppKit
import Observation
import SwiftUI

/// Lanzador (⌥Espacio): apps, archivos, cuentas y conversiones desde un panel.
@MainActor
final class LauncherController {
    private var panel: RingPanel?
    private let model = LauncherModel()
    private var resignObserver: NSObjectProtocol?

    static let size = CGSize(width: 600, height: 440)

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        model.reset()
        model.reindexAppsIfNeeded()
        let panel = self.panel ?? RingPanel()
        self.panel = panel
        panel.onCancel = { [weak self] in self?.hide() }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - Self.size.width / 2, y: frame.maxY - frame.height * 0.22 - Self.size.height)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: false)
        // La vista nace ya con su tamaño: si se crea a cero, el editor de texto del
        // campo se coloca mal y el cursor queda separado de lo escrito.
        let hosting = NSHostingView(rootView: LauncherView(model: model) { [weak self] in self?.hide() })
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hosting
        panel.makeKeyAndOrderFront(nil)
        // Al pulsar fuera (otra ventana pasa a ser la activa) se cierra.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
    }
}

struct LauncherResult: Identifiable, Equatable {
    enum Action: Equatable {
        case open(URL)
        case copy(String)
    }

    let id: String
    let title: String
    let subtitle: String
    let icon: NSImage?
    let symbol: String
    let action: Action

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.title == rhs.title }
}

@Observable
@MainActor
final class LauncherModel {
    var query = "" {
        didSet { search() }
    }
    private(set) var results: [LauncherResult] = []
    var selection = 0

    @ObservationIgnored private var apps: [(name: String, url: URL)] = []
    @ObservationIgnored private var indexedAt: Date?
    @ObservationIgnored private var files: [LauncherResult] = []
    @ObservationIgnored private var metadata: NSMetadataQuery?
    @ObservationIgnored private var fileObserver: NSObjectProtocol?

    func reset() {
        query = ""
        results = []
        selection = 0
    }

    /// Apps de las carpetas habituales (cada 10 minutos como mucho).
    func reindexAppsIfNeeded() {
        if let indexedAt, Date.now.timeIntervalSince(indexedAt) < 600 { return }
        indexedAt = .now
        Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", home + "/Applications"]
            var found: [(String, URL)] = []
            for folder in folders {
                let url = URL(fileURLWithPath: folder)
                for item in (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] where item.pathExtension == "app" {
                    found.append((item.deletingPathExtension().lastPathComponent, item))
                }
            }
            let unique = Dictionary(found.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first }).map { ($0.key, $0.value) }
            await MainActor.run { [unique] in
                self.apps = unique.map { (name: $0.0, url: $0.1) }
                self.search()
            }
        }
    }

    func run(_ result: LauncherResult) {
        switch result.action {
        case let .open(url): NSWorkspace.shared.open(url)
        case let .copy(text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    func move(_ step: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + step + results.count) % results.count
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { results = []; stopFiles(); return }
        var list: [LauncherResult] = []
        if let value = QuickMath.evaluate(text) {
            let formatted = QuickMath.format(value)
            list.append(LauncherResult(id: "calc", title: "= " + formatted, subtitle: String(localized: "Intro para copiar"),
                                       icon: nil, symbol: "equal.circle.fill", action: .copy(formatted)))
        }
        if let converted = QuickMath.convert(text) {
            list.append(LauncherResult(id: "unit", title: converted, subtitle: String(localized: "Intro para copiar"),
                                       icon: nil, symbol: "arrow.left.arrow.right.circle.fill", action: .copy(converted)))
        }
        list += Self.rank(apps, text).prefix(6).map { app in
            LauncherResult(id: app.url.path, title: app.name, subtitle: String(localized: "App"),
                           icon: NSWorkspace.shared.icon(forFile: app.url.path), symbol: "app", action: .open(app.url))
        }
        list += files.filter { file in !list.contains { $0.id == file.id } }
        var web = URLComponents(string: "https://www.google.com/search")
        web?.queryItems = [URLQueryItem(name: "q", value: text)]
        if let url = web?.url {
            list.append(LauncherResult(id: "web", title: String(localized: "Buscar «\(text)» en la web"), subtitle: "Google",
                                       icon: nil, symbol: "magnifyingglass.circle.fill", action: .open(url)))
        }
        results = list
        selection = min(selection, max(results.count - 1, 0))
        searchFiles(text)
    }

    /// Empieza por > empieza alguna palabra > contiene; a igualdad, el nombre corto.
    static func rank(_ apps: [(name: String, url: URL)], _ query: String) -> [(name: String, url: URL)] {
        let q = query.lowercased()
        func score(_ name: String) -> Int {
            let lower = name.lowercased()
            if lower.hasPrefix(q) { return 3 }
            if lower.split(whereSeparator: { $0 == " " || $0 == "-" }).contains(where: { $0.hasPrefix(q) }) { return 2 }
            let initials = String(lower.split(separator: " ").compactMap(\.first))
            if initials.hasPrefix(q) || lower.contains(q) { return 1 }
            return 0
        }
        struct Scored { let app: (name: String, url: URL); let score: Int }
        let scored: [Scored] = apps.map { Scored(app: $0, score: score($0.name)) }.filter { $0.score > 0 }
        let sorted = scored.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.app.name.count < rhs.app.name.count
        }
        return sorted.map(\.app)
    }

    // MARK: - Archivos (Spotlight)

    private func searchFiles(_ text: String) {
        stopFiles()
        guard text.count >= 2, QuickMath.evaluate(text) == nil else { files = []; return }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@ AND NOT (%K == 'com.apple.application-bundle')",
                                      NSMetadataItemDisplayNameKey, text, NSMetadataItemContentTypeKey)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        fileObserver = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.gathered(query, for: text) }
        }
        metadata = query
        query.start()
    }

    private func gathered(_ query: NSMetadataQuery, for text: String) {
        query.stop()
        guard text == self.query.trimmingCharacters(in: .whitespaces) else { return }
        files = (0..<min(query.resultCount, 6)).compactMap { index in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            let url = URL(fileURLWithPath: path)
            let folder = url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            return LauncherResult(id: path, title: url.lastPathComponent, subtitle: folder,
                                  icon: NSWorkspace.shared.icon(forFile: path), symbol: "doc", action: .open(url))
        }
        // Vuelve a componer la lista con los archivos (sin relanzar la busqueda).
        recompose()
    }

    private func recompose() {
        let web = results.last { $0.id == "web" }
        var list = results.filter { $0.id == "calc" || $0.id == "unit" || $0.subtitle == String(localized: "App") }
        list += files.filter { file in !list.contains { $0.id == file.id } }
        if let web { list.append(web) }
        results = list
        selection = min(selection, max(results.count - 1, 0))
    }

    private func stopFiles() {
        metadata?.stop()
        metadata = nil
        if let fileObserver { NotificationCenter.default.removeObserver(fileObserver) }
        fileObserver = nil
    }
}

private struct LauncherView: View {
    @Bindable var model: LauncherModel
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.notchText.opacity(0.6))
                TextField("Buscar apps, archivos o calcular…", text: $model.query, prompt: Text("Buscar apps, archivos o calcular…"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(AppColors.notchText)
                    .focused($focused)
                    .onSubmit(runSelected)
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)

            if !model.results.isEmpty {
                Divider().overlay(AppColors.notchText.opacity(0.1))
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                                LauncherRow(result: result, selected: index == model.selection)
                                    .id(result.id)
                                    .onTapGesture { model.selection = index; runSelected() }
                                    .onHover { if $0 { model.selection = index } }
                            }
                        }
                        .padding(6)
                    }
                    // Alto justo para los resultados (como mucho ocho filas).
                    .frame(height: min(CGFloat(model.results.count) * 46 + 12, 360))
                    .onChange(of: model.selection) { _, index in
                        guard model.results.indices.contains(index) else { return }
                        proxy.scrollTo(model.results[index].id)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppColors.floating))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AppColors.notchText.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .padding(20)
        .frame(width: LauncherController.size.width, height: LauncherController.size.height, alignment: .top)
        .animation(AppMotion.snappy, value: model.results)
        // Tras mostrarse la ventana: antes de ser la activa el foco no se queda.
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func runSelected() {
        guard model.results.indices.contains(model.selection) else { return }
        let result = model.results[model.selection]
        close()
        model.run(result)
    }
}

private struct LauncherRow: View {
    let result: LauncherResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = result.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: result.symbol).resizable().foregroundStyle(selected ? AppColors.onAccent : AppColors.accent)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: result.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? AppColors.onAccent : AppColors.notchText)
                Text(verbatim: result.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? AppColors.onAccent.opacity(0.8) : AppColors.notchText.opacity(0.55))
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "return").font(.system(size: 11, weight: .bold)).foregroundStyle(AppColors.onAccent.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? AppColors.accent : .clear))
        .contentShape(Rectangle())
    }
}
