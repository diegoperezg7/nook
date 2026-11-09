import SwiftUI

extension View {
    /// Superficie de Liquid Glass (macOS 26). En macOS 14-15, material translucido con
    /// el mismo tinte. `interactive`: el cristal reacciona al puntero (botones).
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint) }
                }
            }
            .overlay(shape.stroke(AppColors.panelBorder, lineWidth: 0.5))
        }
    }

    @available(macOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}
