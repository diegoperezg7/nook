import SwiftUI

/// Lo nuevo de esta version. Se enseña una vez al actualizar (no en la primera
/// instalacion, que ya tiene la introduccion). Al sacar version se cambian las notas.
enum WhatsNew {
    struct Note: Identifiable {
        let icon: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        var id: String { icon }
    }

    static let notes: [Note] = [
        Note(icon: "music.note", title: "Música en el notch",
             detail: "Mientras suena Spotify o Música, su logo en el notch abre un reproductor con carátula, progreso y controles."),
        Note(icon: "phone.fill", title: "Llamadas",
             detail: "Un solo botón verde con micro, cámara y colgar, y a la vista si estás silenciado."),
        Note(icon: "camera.viewfinder", title: "Capturas en su carpeta",
             detail: "Las capturas van a Imágenes/Capturas de pantalla, fuera del Escritorio, y se ven en el notch."),
        Note(icon: "calendar", title: "Calendario al día",
             detail: "Al cambiar de día, el calendario marca hoy y la reunión deja de avisar en cuanto entras."),
        Note(icon: "airpods", title: "AirPods",
             detail: "Batería de cada auricular y del estuche, también justo al conectarlos."),
    ]

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Ultima version que el usuario ya ha visto (o instalado por primera vez).
    static let seenKey = "whatsNewSeenVersion"

    /// true si hay que enseñarlas; marca la version como vista.
    static func shouldShow(defaults: UserDefaults = .standard, firstLaunch: Bool) -> Bool {
        let seen = defaults.string(forKey: seenKey)
        defaults.set(version, forKey: seenKey)
        return !firstLaunch && seen != version && !notes.isEmpty
    }
}

struct WhatsNewView: View {
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: AppIcon.image)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Novedades de Visor \(WhatsNew.version)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.top, 34)
            .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(WhatsNew.notes) { note in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: note.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(note.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 36)

            Spacer(minLength: 24)

            Button(action: done) {
                Text("Continuar").frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 28)
        }
        .frame(width: 440, height: 440)
        .background(AppColors.panel)
    }
}
