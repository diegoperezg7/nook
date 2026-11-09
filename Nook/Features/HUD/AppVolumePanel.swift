import SwiftUI

/// Lista de apps que suenan con su control de volumen.
struct AppVolumePanel: View {
    let volume: AppVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Volumen por app")
                .font(AppTypography.bodyStrong)
                .foregroundStyle(AppColors.textSecondary)
            if volume.apps.isEmpty {
                Text("Ahora no suena ninguna app")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ForEach(volume.apps) { app in
                    AppVolumeRow(app: app, volume: volume)
                }
            }
            if volume.failed {
                Text("macOS no ha dejado captar el sonido. Revisa el permiso en Ajustes del Sistema > Privacidad > Grabación de audio.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 280)
        // Mientras esta abierto aparecen las apps que empiezan a sonar.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(AppMotion.snappy) { volume.refresh() }
            }
        }
    }
}

private struct AppVolumeRow: View {
    let app: AppVolume.App
    let volume: AppVolume

    var body: some View {
        let value = volume.volume(of: app)
        HStack(spacing: 10) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.fill").resizable().foregroundStyle(AppColors.textSecondary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: app.name)
                    .font(AppTypography.cardTitle.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Button { volume.setVolume(value > 0 ? 0 : 1, for: app) } label: {
                        Image(systemName: value == 0 ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(value == 0 ? AppColors.danger : AppColors.textSecondary)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                    .help(Text(value == 0 ? "Activar sonido" : "Silenciar"))
                    Slider(value: Binding(get: { Double(value) }, set: { volume.setVolume(Float($0), for: app) }), in: 0...1)
                        .controlSize(.small)
                        .tint(AppColors.accent)
                    Text(verbatim: "\(Int((value * 100).rounded())) %")
                        .font(AppTypography.cardCaption.monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}
