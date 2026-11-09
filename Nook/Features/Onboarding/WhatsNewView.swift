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
        Note(icon: "envelope.open.fill", title: "Acciones rápidas en el correo",
             detail: "Pasa el ratón por un correo para marcarlo como leído o mandarlo a la papelera, sin abrirlo. Si te equivocas, puedes deshacerlo."),
        Note(icon: "moon.fill", title: "Correo más cómodo de leer",
             detail: "Los correos escritos a mano se ven en oscuro, a juego con el notch."),
        Note(icon: "drop.fill", title: "Icono nuevo",
             detail: "Una gota de cristal que cuelga del notch."),
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
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Novedades de Nook \(WhatsNew.version)")
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
