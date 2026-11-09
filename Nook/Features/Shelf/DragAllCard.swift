import AppKit
import SwiftUI

/// Primera tarjeta de la bandeja cuando hay varios archivos: al arrastrarla salen
/// todos a la vez (a un correo, un chat o una carpeta).
struct DragAllCard: View {
    let count: Int
    let urls: () -> [URL]
    let onDragStart: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.accent)
            VStack(spacing: 2) {
                Text("Arrastrar todo")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("\(count) archivos")
                    .font(AppTypography.cardCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(width: ItemCard.size.width, height: ItemCard.size.height)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hovering ? AppColors.accent : AppColors.accentBorder,
                              style: StrokeStyle(lineWidth: hovering ? 1.5 : 1, dash: [5, 4]))
        }
        .scaleEffect(hovering && !AppMotion.reduceMotion ? 1.045 : 1)
        .overlay { MultiDragSource(urls: urls, onDragStart: onDragStart) }
        .onHover { inside in withAnimation(AppMotion.snappy) { hovering = inside } }
        .help(Text("Arrastra para sacar todos los archivos de la bandeja"))
    }
}

/// SwiftUI solo arrastra un elemento por gesto: esta vista empieza una sesion de
/// arrastre de AppKit con un elemento por archivo.
private struct MultiDragSource: NSViewRepresentable {
    let urls: () -> [URL]
    let onDragStart: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.urls = urls
        view.onDragStart = onDragStart
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.urls = urls
        view.onDragStart = onDragStart
    }

    final class DragView: NSView, NSDraggingSource {
        var urls: () -> [URL] = { [] }
        var onDragStart: () -> Void = {}
        private var downEvent: NSEvent?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { downEvent = event }

        override func mouseDragged(with event: NSEvent) {
            guard let down = downEvent else { return }
            downEvent = nil
            let files = urls()
            guard !files.isEmpty else { return }
            let start = convert(down.locationInWindow, from: nil)
            let items = files.enumerated().map { index, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let offset = CGFloat(min(index, 4)) * 6
                item.setDraggingFrame(NSRect(x: start.x - 24 + offset, y: start.y - 24 - offset, width: 48, height: 48), contents: icon)
                return item
            }
            onDragStart()
            beginDraggingSession(with: items, event: down, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }
    }
}
