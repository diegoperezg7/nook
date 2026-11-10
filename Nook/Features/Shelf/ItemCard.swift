import AppKit
import SwiftUI

/// Tarjeta de un elemento, con vista previa real (Quick Look). Se arrastra fuera tal
/// cual; un clic lo copia y un doble clic abre la vista previa. El resto de acciones,
/// en el menu contextual.
struct ItemCard: View {
    let item: NotchItem
    let store: ItemStore
    let index: Int
    var onCopied: () -> Void = {}
    var onDragStart: () -> Void = {}
    /// Avisa de que la vista previa grande se abre o se cierra.
    var onPreviewChange: (Bool) -> Void = { _ in }

    @State private var hovering = false
    @State private var appeared = false
    @State private var feedback: Feedback?
    @State private var thumbnail: NSImage?
    @State private var showPeek = false

    static let size = CGSize(width: 120, height: 120)
    /// La X sobresale de la esquina; mas el crecimiento de la tarjeta con el zoom.
    private var hoverOffset: CGFloat { 5 + (AppMotion.reduceMotion ? 0 : Self.size.width * 0.045 / 2) }
    private static let previewHeight: CGFloat = 76
    private static let corner: CGFloat = 14

    /// Mensaje breve sobre la tarjeta tras una accion.
    private enum Feedback: Equatable {
        case working, copied, textCopied, noText, saved, done, failed

        var icon: String {
            switch self {
            case .working: return ""
            case .copied, .textCopied, .done: return "checkmark.circle.fill"
            case .noText: return "text.magnifyingglass"
            case .saved: return "tray.and.arrow.down.fill"
            case .failed: return "exclamationmark.triangle.fill"
            }
        }

        var text: LocalizedStringKey {
            switch self {
            case .working: return ""
            case .copied: return "Copiado"
            case .textCopied: return "Texto copiado"
            case .noText: return "Sin texto"
            case .saved: return "Guardado"
            case .done: return "Listo"
            case .failed: return "Error"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            preview
                .frame(width: Self.size.width - 12, height: Self.previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(alignment: .bottomTrailing) { typeBadge }
                .overlay {
                    if hovering {
                        Button { showPeek = true } label: {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(width: 30, height: 30)
                                .liquidGlass(in: Circle(), interactive: true)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(Text("Vista previa"))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    if let source = AppIcons.icon(for: item.sourceBundleID) {
                        Image(nsImage: source)
                            .resizable()
                            .frame(width: 12, height: 12)
                            .help(Text(verbatim: AppIcons.name(for: item.sourceBundleID) ?? ""))
                    }
                    AgeText(date: item.createdAt)
                        .font(AppTypography.cardCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 3)
        }
        .padding(6)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .liquidGlass(in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .overlay {
            if hovering {
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .strokeBorder(AppColors.accent, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .topLeading) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppColors.onAccent)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(AppColors.accent))
                    .offset(x: -5, y: -5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay { if let feedback { badge(feedback) } }
        .shadow(color: .black.opacity(hovering ? 0.22 : 0), radius: 8, y: 4)
        .scaleEffect(hovering && !AppMotion.reduceMotion ? 1.045 : 1)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || AppMotion.reduceMotion ? 0 : 8)
        .contentShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .onHover { inside in withAnimation(AppMotion.snappy) { hovering = inside } }
        .onTapGesture(perform: copy)
        .simultaneousGesture(TapGesture(count: 2).onEnded { showPeek = true })
        .onDrag {
            onDragStart()
            return store.itemProvider(for: item)
        } preview: {
            dragPreview
        }
        .contextMenu { menu }
        // Fuera de los gestos de la tarjeta: dentro, el de arrastrar se queda con el
        // clic y la X no hace nada. Compensa el zoom de la tarjeta al pasar el raton.
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { withAnimation(AppMotion.snappy) { store.delete(item) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.thickMaterial))
                        .overlay(Circle().strokeBorder(AppColors.cardBorder))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: hoverOffset, y: -hoverOffset)
                .help(Text("Eliminar"))
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                .onHover { if $0 { hovering = true } }
            }
        }
        .popover(isPresented: $showPeek, arrowEdge: .bottom) {
            ItemPeek(item: item, store: store, onCopy: copy, onDragStart: onDragStart)
        }
        .onChange(of: showPeek) { _, shown in onPreviewChange(shown) }
        .onAppear {
            withAnimation(AppMotion.stagger(index)) { appeared = true }
        }
        .task(id: item.id) { await loadThumbnail() }
        .help(item.kind == .text ? Text(verbatim: String((item.text ?? "").prefix(400))) : Text(title))
    }

    // MARK: - Menu

    @ViewBuilder
    private var menu: some View {
        Button("Copiar", systemImage: "doc.on.doc", action: copy)
        Button("Vista previa", systemImage: "eye") { showPeek = true }
        share
        Button("Enviar por AirDrop", systemImage: "dot.radiowaves.left.and.right") { QuickShare.send(shareItems, via: .sendViaAirDrop) }
            .disabled(fileURL == nil)
        Button("Enviar por correo", systemImage: "envelope") { QuickShare.send(shareItems, via: .composeEmail) }
        if let url = fileURL {
            Button("Mostrar en Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        if item.origin == .clipboard {
            Button("Guardar en la bandeja", systemImage: "tray.and.arrow.down") {
                withAnimation(AppMotion.snappy) { store.saveToShelf(item) }
                show(.saved)
            }
        }

        if let url = fileURL, FileActions.isImage(url) {
            Divider()
            Button("Copiar texto de la imagen", systemImage: "text.viewfinder") { recognizeText(url) }
        }
        if item.storedPath != nil || item.origin == .clipboard, let url = fileURL {
            if FileActions.isImage(url) {
                Button("Quitar fondo", systemImage: "person.crop.rectangle.badge.plus") { run { try FileActions.removeBackground(url) } }
                Button("Convertir a PDF", systemImage: "doc.richtext") {
                    run { try FileActions.makePDF(from: [url], name: url.deletingPathExtension().lastPathComponent) }
                }
            }
            if FileActions.isVideo(url) {
                Button("Comprimir vídeo", systemImage: "arrow.down.right.and.arrow.up.left") { run { try await FileActions.compressVideo(url) } }
                Button("Convertir a GIF", systemImage: "photo.stack") { run { try await FileActions.videoToGIF(url) } }
            }
        }
        if item.storedPath != nil, let url = fileURL {
            Divider()
            Button("Comprimir en .zip", systemImage: "doc.zipper") { run { try FileActions.zip(url) } }
            if FileActions.isImage(url) {
                Menu("Convertir a", systemImage: "arrow.triangle.2.circlepath") {
                    ForEach(ImageFormat.allCases.filter { $0 != FileActions.format(of: url) }) { format in
                        Button { run { try FileActions.convert(url, to: format) } } label: {
                            Text(verbatim: format.label)
                        }
                    }
                }
            }
        }

        if item.origin == .clipboard {
            Divider()
            Button(item.isPinned ? "Desfijar" : "Fijar", systemImage: item.isPinned ? "pin.slash" : "pin") {
                withAnimation(AppMotion.snappy) { store.togglePin(item) }
            }
        }
        Divider()
        Button("Eliminar", systemImage: "trash", role: .destructive) {
            withAnimation(AppMotion.snappy) { store.delete(item) }
        }
    }

    @ViewBuilder
    private var share: some View {
        if let url = fileURL {
            ShareLink(item: url) { Label("Compartir", systemImage: "square.and.arrow.up") }
        } else if let text = item.text {
            ShareLink(item: text) { Label("Compartir", systemImage: "square.and.arrow.up") }
        }
    }

    // MARK: - Vistas

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            Text(item.text ?? "")
                .font(AppTypography.cardText)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(4)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AppColors.previewWell)
        case .image, .file:
            ZStack {
                AppColors.previewWell
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: isPhoto ? .fill : .fit)
                        .padding(isPhoto ? 0 : 6)
                        .transition(.opacity)
                }
            }
        }
    }

    /// Imagenes a sangre; documentos encajados (su miniatura ya trae la pagina).
    private var isPhoto: Bool {
        guard let url = fileURL else { return false }
        return FileActions.isImage(url)
    }

    /// Extension del archivo (PDF, ZIP...) en una pastilla sobre la vista previa.
    @ViewBuilder
    private var typeBadge: some View {
        if item.kind != .text, let ext = fileURL?.pathExtension, !ext.isEmpty {
            Text(verbatim: ext.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(5)
        }
    }

    private var dragPreview: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit).frame(width: 72, height: 72)
            } else {
                Text(title).font(AppTypography.cardTitle).padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
            }
        }
    }

    private func badge(_ feedback: Feedback) -> some View {
        RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .fill(feedback == .failed || feedback == .noText ? Color.black.opacity(0.25) : AppColors.accent.opacity(0.75))
            )
            .overlay {
                if feedback == .working {
                    ProgressView().controlSize(.small).tint(AppColors.onAccent)
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: feedback.icon).font(.system(size: 18, weight: .semibold))
                        Text(feedback.text).font(AppTypography.bodyStrong).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(AppColors.onAccent)
                    .padding(6)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private var title: String {
        switch item.kind {
        case .text: return String(localized: "Texto")
        case .image: return String(localized: "Imagen")
        case .file: return item.fileName ?? String(localized: "Archivo")
        }
    }

    private var fileURL: URL? { item.kind == .text ? nil : store.fileURL(for: item) }

    // MARK: - Acciones

    private func copy() {
        store.copyToPasteboard(item)
        show(.copied) { onCopied() }
    }

    private func recognizeText(_ url: URL) {
        withAnimation(AppMotion.snappy) { feedback = .working }
        Task {
            let text = try? await Task.detached(priority: .userInitiated) {
                try FileActions.recognizeText(in: url)
            }.value
            guard let text, !text.isEmpty else { return show(.noText) }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            show(.textCopied)
        }
    }

    /// Accion de archivo en segundo plano; el resultado se guarda en la bandeja.
    /// Lo que se manda por AirDrop o correo: el archivo o el texto.
    private var shareItems: [Any] {
        if let url = fileURL { return [url] }
        return item.text.map { [$0] } ?? []
    }

    private func run(_ action: @escaping @Sendable () async throws -> URL) {
        withAnimation(AppMotion.snappy) { feedback = .working }
        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) { try await action() }.value
                try withAnimation(AppMotion.snappy) { try store.addGeneratedFile(output) }
                show(.done)
            } catch {
                show(.failed)
            }
        }
    }

    private func show(_ value: Feedback, then: (() -> Void)? = nil) {
        withAnimation(AppMotion.snappy) { feedback = value }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(AppMotion.snappy) { if feedback == value { feedback = nil } }
            then?()
        }
    }

    private func loadThumbnail() async {
        guard item.kind != .text, let url = store.fileURL(for: item) else { return }
        let image = await Thumbnails.image(for: url)
        withAnimation(.easeOut(duration: 0.2)) { thumbnail = image }
    }
}

/// Icono y nombre de la app de la que se copio algo (con cache).
enum AppIcons {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: bundleID as NSString)
        return icon
    }

    static func name(for bundleID: String?) -> String? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
