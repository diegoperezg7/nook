import AppKit
import SwiftUI

/// Vista previa grande de una tarjeta (se abre con el ojo o con doble clic). Sirve
/// para distinguir dos cosas parecidas, por ejemplo dos PDF. La imagen se puede
/// arrastrar fuera tal cual, y hay botones para copiar, abrir y mostrar en Finder.
struct ItemPeek: View {
    let item: NotchItem
    let store: ItemStore
    var onCopy: () -> Void
    var onDragStart: () -> Void

    @State private var image: NSImage?
    @State private var copied = false

    private static let previewSize = CGSize(width: 340, height: 240)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
                .frame(width: Self.previewSize.width, height: Self.previewSize.height)
                .background(AppColors.previewWell)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AppColors.cardBorder))
                .onDrag {
                    onDragStart()
                    return store.itemProvider(for: item)
                }
                .help(Text("Arrastra para usarlo en otra app"))

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: details)
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.textSecondary)
            }

            HStack(spacing: 8) {
                PeekButton(title: copied ? "Copiado" : "Copiar", icon: copied ? "checkmark" : "doc.on.doc", prominent: true) {
                    onCopy()
                    withAnimation(AppMotion.snappy) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(AppMotion.snappy) { copied = false }
                    }
                }
                if let url = fileURL {
                    PeekButton(title: "Abrir", icon: "eye") { QuickLookPresenter.shared.show(url) }
                    PeekButton(title: "Finder", icon: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
        .padding(16)
        .task(id: item.id) {
            guard let url = fileURL else { return }
            let loaded = await Thumbnails.image(for: url, size: Self.previewSize)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if item.kind == .text {
            ScrollView {
                Text(verbatim: item.text ?? "")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(10)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var fileURL: URL? { item.kind == .text ? nil : store.fileURL(for: item) }

    private var title: String {
        switch item.kind {
        case .text: return String(localized: "Texto")
        case .image: return item.fileName ?? String(localized: "Imagen")
        case .file: return item.fileName ?? String(localized: "Archivo")
        }
    }

    /// Tipo y tamaño (archivos) o longitud (texto), y cuando se guardo.
    private var details: String {
        let age = AgeText.format(item.createdAt, now: .now)
        if item.kind == .text {
            let count = (item.text ?? "").count
            return String(localized: "\(count) caracteres") + " · " + age
        }
        var parts: [String] = []
        if let url = fileURL {
            if let type = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription {
                parts.append(type)
            }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
        }
        parts.append(age)
        return parts.joined(separator: " · ")
    }
}

/// Boton de cristal de la vista previa; el principal, tintado de azul.
private struct PeekButton: View {
    let title: LocalizedStringKey
    let icon: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppTypography.bodyStrong)
                .foregroundStyle(prominent ? AppColors.onAccent : AppColors.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .liquidGlass(in: Capsule(), tint: prominent ? AppColors.accent : nil, interactive: true)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Antiguedad de un elemento: segundos solo durante el primer minuto ("hace 20 s");
/// despues minutos, horas o dias, sin un contador corriendo.
struct AgeText: View {
    let date: Date

    var body: some View {
        let young = Date.now.timeIntervalSince(date) < 60
        TimelineView(.periodic(from: .now, by: young ? 1 : 30)) { context in
            Text(verbatim: Self.format(date, now: context.date))
        }
    }

    static func format(_ date: Date, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        // "ahora" para lo recien copiado; el formateador diria "dentro de 0 s".
        if now.timeIntervalSince(date) < 1 {
            return formatter.localizedString(fromTimeInterval: 0)
        }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
