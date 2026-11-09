import AppKit
import SwiftData
import SwiftUI

/// Cesta flotante: al agitar el raton arrastrando archivos aparece una ventanita
/// junto al cursor para soltarlos. Lo que se suelta queda tambien en la bandeja, y
/// desde la cesta se puede volver a arrastrar a cualquier sitio.
@MainActor
final class BasketController {
    private let store: ItemStore
    private let container: ModelContainer
    private let detector = ShakeDetector()
    private var panel: NSPanel?
    private var since = Date.now

    static let size = CGSize(width: 220, height: 168)

    init(store: ItemStore, container: ModelContainer) {
        self.store = store
        self.container = container
        detector.onShake = { [weak self] point in self?.show(at: point) }
        // Si se suelta en otro sitio y la cesta sigue vacia, se va.
        detector.onDragEnded = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated {
                    guard let self, self.panel?.isVisible == true, self.itemCount == 0 else { return }
                    self.hide()
                }
            }
        }
    }

    func start() {
        apply()
    }

    /// Activa o quita el detector segun el ajuste.
    func apply() {
        if UserDefaults.standard.bool(forKey: SettingsKey.basketOnShake) {
            detector.start()
        } else {
            detector.stop()
            hide()
        }
    }

    func show(at point: NSPoint) {
        if panel?.isVisible == true, itemCount > 0 { return }
        since = .now
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: BasketView(since: since, store: store, onClose: { [weak self] in self?.hide() })
            .modelContainer(container))
        let size = Self.size
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let frame = screen.visibleFrame
            origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
            origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppMotion.reduceMotion ? 0 : 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private var itemCount: Int {
        let raw = ItemOrigin.shelf.rawValue
        let since = since
        let descriptor = FetchDescriptor<NotchItem>(predicate: #Predicate { $0.originRaw == raw && $0.createdAt >= since })
        return (try? container.mainContext.fetchCount(descriptor)) ?? 0
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
}

/// Contenido de la cesta: zona de soltar y, cuando hay algo, sus miniaturas.
private struct BasketView: View {
    let store: ItemStore
    let onClose: () -> Void
    @Query private var items: [NotchItem]
    @State private var targeted = false

    init(since: Date, store: ItemStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        let raw = ItemOrigin.shelf.rawValue
        _items = Query(
            filter: #Predicate<NotchItem> { $0.originRaw == raw && $0.createdAt >= since },
            sort: \NotchItem.createdAt, order: .reverse,
            animation: .spring(response: 0.3, dampingFraction: 0.8)
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "basket.fill").foregroundStyle(AppColors.accent)
                Text(items.isEmpty ? String(localized: "Cesta") : String(localized: "Cesta · \(items.count)"))
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.notchText)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppColors.notchText.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(AppColors.notchText.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help(Text("Cerrar la cesta (lo soltado sigue en la bandeja)"))
            }
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: targeted ? "arrow.down" : "tray.and.arrow.down.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.accent)
                        .contentTransition(.symbolEffect(.replace))
                    Text("Suelta aquí")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.notchText.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppColors.accent.opacity(targeted ? 0.22 : 0.1)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppColors.accent.opacity(targeted ? 1 : 0.5), style: StrokeStyle(lineWidth: targeted ? 2 : 1.25, dash: [6, 5])))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            BasketTile(item: item, store: store)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .overlay {
                    if targeted {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppColors.accent, lineWidth: 2)
                    }
                }
            }
        }
        .padding(12)
        .background(shape.fill(AppColors.notch))
        .overlay(shape.strokeBorder(AppColors.notchText.opacity(0.14), lineWidth: 1))
        .scaleEffect(targeted && !AppMotion.reduceMotion ? 1.03 : 1)
        .animation(AppMotion.snappy, value: targeted)
        .padding(4)
        .onDrop(of: DropReader.types, isTargeted: $targeted) { providers in
            DropReader.read(providers, into: store)
            return true
        }
    }
}

/// Miniatura que se puede arrastrar fuera de la cesta.
private struct BasketTile: View {
    let item: NotchItem
    let store: ItemStore
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppColors.notchText.opacity(0.08))
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit).padding(4)
                } else {
                    Image(systemName: item.kind == .text ? "text.alignleft" : "doc.fill")
                        .foregroundStyle(AppColors.notchText.opacity(0.7))
                }
            }
            .frame(width: 64, height: 64)
            Text(verbatim: item.fileName ?? item.text ?? "")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppColors.notchText.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .onDrag { store.itemProvider(for: item) }
        .task(id: item.id) {
            guard item.kind != .text, let url = store.fileURL(for: item) else { return }
            thumbnail = await Thumbnails.image(for: url)
        }
    }
}
