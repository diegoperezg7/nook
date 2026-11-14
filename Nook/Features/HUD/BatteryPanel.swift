import SwiftUI

/// Aro de bateria con un simbolo dentro (AirPods, portatil...).
struct BatteryRing: View {
    let symbol: String
    let level: Int
    var charging = false
    var size: CGFloat = 30
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(AppColors.textPrimary.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(2, min(level, 100))) / 100)
                .stroke(Self.color(level, charging), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(AppMotion.snappy, value: level)
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary.opacity(0.9))
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
    }

    static func color(_ level: Int, _ charging: Bool) -> Color {
        if charging { return AppColors.success }
        return level <= 10 ? AppColors.danger : level <= 20 ? AppColors.warning : AppColors.success
    }
}

/// Seccion de la bateria: cada auricular y el estuche con su porcentaje.
struct BatteryPanel: View {
    let battery: BatteryCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(battery.headphones) { device in
                row(symbol: device.icon, name: device.name, parts: device.levels.map { ($0.part, $0.level) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Al abrirlo, la lectura de ahora (la anterior puede ser de hace 2 min).
        .onAppear { battery.refresh(force: true) }
    }

    private func row(symbol: String, name: String, parts: [(String, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
            HStack(spacing: 14) {
                ForEach(parts, id: \.0) { part, level in
                    HStack(spacing: 7) {
                        BatteryRing(symbol: AccessoryBattery.partSymbol(part, model: symbol), level: level, size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "\(level) %")
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(AppColors.textPrimary)
                            if !part.isEmpty {
                                Text(Self.partName(part)).font(.system(size: 10))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private static func partName(_ part: String) -> LocalizedStringKey {
        switch part {
        case "L": return "Izquierdo"
        case "R": return "Derecho"
        default: return "Estuche"
        }
    }
}
