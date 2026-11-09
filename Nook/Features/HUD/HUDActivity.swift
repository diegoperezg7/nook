import SwiftUI

/// Aviso breve a los lados del notch cerrado: icono a la izquierda, valor a la
/// derecha. El notch se ensancha lo justo para cada tipo.
struct HUDActivity: View {
    let kind: SystemHUD.Kind
    let metrics: NotchMetrics

    /// Ancho que crece el notch a cada lado para este aviso.
    static func side(for kind: SystemHUD.Kind) -> CGFloat {
        switch kind {
        case .volume, .battery: return 58
        case .audioDevice, .download: return 112
        }
    }

    var body: some View {
        let side = Self.side(for: kind)
        HStack(spacing: 0) {
            leading
                .frame(width: side - 8, alignment: .leading)
                .padding(.leading, NotchMetrics.closedEar + 12)
            Spacer(minLength: metrics.notchWidth)
            trailing
                .frame(width: side - 8, alignment: .trailing)
                .padding(.trailing, NotchMetrics.closedEar + 12)
        }
        .foregroundStyle(AppColors.notchText)
        .frame(height: metrics.notchHeight)
    }

    @ViewBuilder
    private var leading: some View {
        switch kind {
        case let .volume(level, muted):
            Image(systemName: muted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: level)
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        case let .audioDevice(_, icon):
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
        case let .battery(level, charging):
            Image(systemName: charging ? "battery.100percent.bolt" : Self.batterySymbol(level))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(charging ? AppColors.success : level <= 10 ? AppColors.danger : level <= 20 ? AppColors.warning : AppColors.notchText)
        case let .download(_, done):
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.success)
                    .transition(.scale.combined(with: .opacity))
            } else {
                ProgressView().controlSize(.small).tint(AppColors.accent)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch kind {
        case let .volume(level, muted):
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.notchText.opacity(0.2))
                Capsule().fill(muted ? AppColors.notchText.opacity(0.4) : AppColors.notchText)
                    .frame(width: max(4, 40 * (muted ? 0 : level)))
            }
            .frame(width: 40, height: 5)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: level)
        case let .audioDevice(name, _):
            Text(verbatim: name).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.tail)
        case let .battery(level, _):
            Text(verbatim: "\(level) %").font(.system(size: 12, weight: .semibold).monospacedDigit())
        case let .download(name, _):
            Text(verbatim: name).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.middle)
        }
    }

    private static func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
