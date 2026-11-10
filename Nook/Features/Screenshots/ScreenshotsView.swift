import AppKit
import SwiftUI

/// Capturas de pantalla: las de la carpeta de capturas, la mas reciente primero.
/// Un clic selecciona; arriba se copian o se mandan a la Papelera las elegidas.
struct ScreenshotsView: View {
    let model: NotchViewModel
    let store: ItemStore
    @Bindable var library: ScreenshotLibrary

    @State private var copiedCount: Int?

    var body: some View {
        VStack(spacing: 0) {
            if library.folder == nil {
                setup
            } else {
                toolbar
                    .padding(.horizontal, NotchContentView.margin)
                    .frame(height: NotchMetrics.searchRowHeight - 10)
                    .padding(.bottom, 10)
                if library.shots.isEmpty {
                    empty
                } else {
                    strip
                }
            }
        }
        .onAppear { library.reload() }
    }

    // MARK: - Barra

    private var toolbar: some View {
        let selected = library.selectedShots
        let allSelected = !library.shots.isEmpty && selected.count == library.shots.count
        return HStack(spacing: 8) {
            Group {
                if let copiedCount {
                    Label(copiedCount == 1 ? String(localized: "1 copiada") : String(localized: "\(copiedCount) copiadas"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.accent)
                } else if selected.isEmpty {
                    Text(library.shots.count == 1 ? String(localized: "1 captura") : String(localized: "\(library.shots.count) capturas"))
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Text(selected.count == 1 ? String(localized: "1 seleccionada") : String(localized: "\(selected.count) seleccionadas"))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .font(AppTypography.bodyStrong)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity, alignment: .leading)

            if !library.shots.isEmpty {
                ToolbarButton(
                    title: allSelected ? "Quitar selección" : "Seleccionar todo",
                    icon: allSelected ? "circle.dashed" : "checkmark.circle"
                ) {
                    withAnimation(AppMotion.snappy) {
                        allSelected ? library.clearSelection() : library.selectAll()
                    }
                }
            }
            ToolbarButton(title: "Copiar", icon: "doc.on.doc", prominent: true, disabled: selected.isEmpty) {
                copy(selected.map(\.url))
            }
            ToolbarButton(title: "A la Papelera", icon: "trash", disabled: selected.isEmpty) {
                withAnimation(AppMotion.snappy) { library.trash(selected.map(\.url)) }
            }
        }
        .animation(AppMotion.snappy, value: selected.count)
    }

    private func copy(_ urls: [URL]) {
        store.copyFiles(urls)
        withAnimation(AppMotion.snappy) { copiedCount = urls.count }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(AppMotion.snappy) { copiedCount = nil }
        }
        model.didCopy()
    }

    // MARK: - Tira

    private var strip: some View {
        Carousel(data: library.shots) { _, shot in
            ScreenshotCard(
                shot: shot,
                selected: library.selection.contains(shot.url),
                onToggle: { withAnimation(AppMotion.snappy) { library.toggle(shot) } },
                onCopy: { copy([shot.url]) },
                onTrash: { withAnimation(AppMotion.snappy) { library.trash([shot.url]) } },
                onDragStart: model.beginDragOut
            )
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
        .frame(height: NotchMetrics.cardRowHeight)
    }

    // MARK: - Estados vacios

    private var setup: some View {
        Placeholder(
            icon: "camera.viewfinder",
            title: "Tus capturas de pantalla, a mano",
            subtitle: "Elige la carpeta donde se guardan (normalmente el Escritorio)",
            action: ("Elegir carpeta…", {
                // El notch esta por encima de todo: se cierra para no tapar el dialogo.
                model.close()
                library.chooseFolder()
            })
        )
        .padding(.top, NotchMetrics.searchRowHeight)
    }

    private var empty: some View {
        Placeholder(
            icon: "camera.viewfinder",
            title: "Aún no hay capturas",
            subtitle: "Haz una con ⇧⌘4 y aparecerá aquí",
            action: nil
        )
    }
}

/// Recuadro de los estados vacios, con la misma forma que la zona de soltar.
private struct Placeholder: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let action: (LocalizedStringKey, () -> Void)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        shape
            .fill(AppColors.accentWell)
            .overlay(shape.strokeBorder(AppColors.accentBorder, style: StrokeStyle(lineWidth: 1.25, dash: [6, 5])))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColors.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(AppColors.accent))
                        .shadow(color: AppColors.accent.opacity(0.45), radius: 6, y: 2)
                    VStack(spacing: 3) {
                        Text(title)
                            .font(AppTypography.title)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(subtitle)
                            .font(AppTypography.subtitle)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    if let action {
                        Button(action: action.1) {
                            Text(action.0)
                                .font(AppTypography.bodyStrong)
                                .foregroundStyle(AppColors.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .frame(height: NotchMetrics.cardRowHeight)
            .padding(.horizontal, NotchContentView.margin)
    }
}

/// Boton de cristal de la barra de capturas; el principal, en azul.
private struct ToolbarButton: View {
    let title: LocalizedStringKey
    let icon: String
    var prominent = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppTypography.bodyStrong)
                .foregroundStyle(prominent && !disabled ? AppColors.onAccent : AppColors.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .modifier(ToolbarSurface(prominent: prominent && !disabled, interactive: !disabled))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

/// El principal, capsula azul solida: un cristal tintado sobre el panel de cristal
/// pierde el color. Los demas, de cristal.
private struct ToolbarSurface: ViewModifier {
    let prominent: Bool
    let interactive: Bool

    func body(content: Content) -> some View {
        if prominent {
            content
                .background(Capsule().fill(AppColors.accent))
                .shadow(color: AppColors.accent.opacity(0.4), radius: 5, y: 1)
        } else {
            content.liquidGlass(in: Capsule(), interactive: interactive)
        }
    }
}

/// Tarjeta de una captura: la imagen y cuando se hizo. Un clic la selecciona, doble
/// clic la abre con Vista Rapida y se puede arrastrar a cualquier app.
private struct ScreenshotCard: View {
    let shot: ScreenshotLibrary.Shot
    let selected: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onTrash: () -> Void
    let onDragStart: () -> Void

    @State private var hovering = false
    @State private var thumbnail: NSImage?

    @Environment(SystemHUD.self) private var hud

    static let size = CGSize(width: 168, height: 120)
    private static let corner: CGFloat = 14

    /// OCR local (Vision) de la captura al portapapeles.
    private func copyText(_ url: URL) {
        Task {
            let text = try? await Task.detached(priority: .userInitiated) { try FileActions.recognizeText(in: url) }.value
            guard let text, !text.isEmpty else {
                return hud.show(.notice(icon: "text.viewfinder", text: String(localized: "No hay texto en la imagen")), for: 2)
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            hud.show(.notice(icon: "doc.on.clipboard.fill", text: String(localized: "Texto copiado")), for: 2)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                AppColors.previewWell
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .frame(width: Self.size.width - 12, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            AgeText(date: shot.date)
                .font(AppTypography.cardCaption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 3)
        }
        .padding(6)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .liquidGlass(in: shape)
        .overlay {
            if selected || hovering {
                shape.strokeBorder(AppColors.accent, lineWidth: selected ? 2 : 1.5)
            }
        }
        .overlay(alignment: .topLeading) { checkmark }
        .shadow(color: .black.opacity(hovering ? 0.22 : 0), radius: 8, y: 4)
        .scaleEffect(hovering && !AppMotion.reduceMotion ? 1.04 : 1)
        .contentShape(shape)
        .onHover { inside in withAnimation(AppMotion.snappy) { hovering = inside } }
        // Doble clic simultaneo: si fuera antes, el clic simple esperaria a descartarlo.
        .onTapGesture(perform: onToggle)
        .simultaneousGesture(TapGesture(count: 2).onEnded { QuickLookPresenter.shared.show(shot.url) })
        .onDrag {
            onDragStart()
            let provider = NSItemProvider(object: shot.url as NSURL)
            provider.suggestedName = shot.url.lastPathComponent
            return provider
        }
        .contextMenu {
            Button("Copiar", systemImage: "doc.on.doc", action: onCopy)
            Button("Vista previa", systemImage: "eye") { QuickLookPresenter.shared.show(shot.url) }
            Button("Copiar texto de la imagen", systemImage: "text.viewfinder") { copyText(shot.url) }
            Button("Mostrar en Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([shot.url])
            }
            Divider()
            Button("A la Papelera", systemImage: "trash", role: .destructive, action: onTrash)
        }
        // Fuera de los gestos de la tarjeta: dentro, el clic seleccionaba la captura.
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onTrash) {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 22, height: 22)
                        .liquidGlass(in: Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .help(Text("A la Papelera"))
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                // Sigue la esquina de la tarjeta, que crece un 4 % con el raton encima.
                .offset(x: AppMotion.reduceMotion ? 0 : Self.size.width * 0.02, y: AppMotion.reduceMotion ? 0 : -Self.size.height * 0.02)
                .onHover { if $0 { hovering = true } }
            }
        }
        .help(Text(verbatim: shot.url.lastPathComponent))
        .task(id: shot.url) {
            let image = await Thumbnails.image(for: shot.url, size: CGSize(width: 320, height: 200))
            withAnimation(.easeOut(duration: 0.2)) { thumbnail = image }
        }
    }

    @ViewBuilder
    private var checkmark: some View {
        if selected || hovering {
            Image(systemName: selected ? "checkmark" : "circle")
                .font(.system(size: selected ? 9 : 18, weight: .bold))
                .foregroundStyle(selected ? AppColors.onAccent : AppColors.textPrimary.opacity(0.8))
                .frame(width: 20, height: 20)
                .background { if selected { Circle().fill(AppColors.accent) } }
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .padding(10)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }
}
