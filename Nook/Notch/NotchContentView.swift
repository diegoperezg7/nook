import AppKit
import SwiftUI

/// Contenido del panel abierto: control segmentado (bandeja / historial) a un lado del
/// notch, menu de opciones al otro y, debajo, la seccion elegida.
struct NotchContentView: View {
    @Bindable var model: NotchViewModel
    let store: ItemStore
    @Environment(ScreenshotLibrary.self) private var screenshots
    @Environment(AgentMonitor.self) private var agents
    @Environment(CalendarService.self) private var calendarService
    @Environment(FocusTimer.self) private var focus
    @Environment(MailService.self) private var mail
    @State private var showAlarm = false
    @State private var alarmTime = Date.now.addingTimeInterval(3600)
    @Namespace private var tabNamespace

    /// Margen interior entre el borde visible del panel y su contenido.
    static let margin = NotchMetrics.sideMargin

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch model.tab {
                case .shelf:
                    ShelfView(model: model, store: store)
                case .clipboard:
                    ClipboardView(model: model, store: store)
                case .screenshots:
                    ScreenshotsView(model: model, store: store, library: screenshots)
                case .calendar:
                    CalendarView(calendar: calendarService)
                case .mail:
                    MailView(mail: mail)
                case .agents:
                    AgentsView(monitor: agents)
                }
            }
            .padding(.top, NotchMetrics.topSpacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // La forma abierta tiene orejas concavas arriba: su cuerpo visible es mas
        // estrecho que la ventana. Sin esto los margenes se quedaban en 2 pt.
        .padding(.horizontal, NotchMetrics.openEar)
    }

    private var header: some View {
        HStack(spacing: 0) {
            tabs.frame(maxWidth: .infinity, alignment: .leading)
            // Hueco del notch fisico: ahi no se ve nada.
            Color.clear.frame(width: model.metrics.hasNotch ? model.metrics.notchWidth : 0)
            HStack(spacing: 8) {
                if model.tab == .shelf {
                    Button { chooseFiles() } label: {
                        CircleIconLabel(icon: "plus")
                    }
                    .buttonStyle(.plain)
                    .help(Text("Añadir archivos…"))
                    .accessibilityLabel(Text("Añadir archivos…"))
                    .transition(.scale.combined(with: .opacity))
                }
                if mail.isEnabled { mailButton }
                timerMenu
                menu
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(AppMotion.snappy, value: model.tab)
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, 4)
        .frame(height: model.metrics.headerHeight)
    }

    /// Pestañas: dos capsulas de cristal; la activa, tintada con el acento.
    /// Pestañas juntas en una sola capsula de cristal (control segmentado); la activa
    /// lleva una pildora azul que se desliza. Asi caben todas en el lado del notch.
    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton(.shelf, title: "Bandeja", icon: "tray.full.fill")
            tabButton(.clipboard, title: "Portapapeles", icon: "list.clipboard.fill")
            tabButton(.screenshots, title: "Capturas", icon: "camera.viewfinder", logo: AgentIcons.screenshot)
            tabButton(.calendar, title: "Calendario", icon: "calendar", logo: AgentIcons.calendar)
            tabButton(.agents, title: "Agentes de IA", icon: "brain", logo: AgentIcons.claude)
        }
        .padding(3)
        .liquidGlass(in: Capsule())
    }

    private func tabButton(_ tab: NotchViewModel.Tab, title: LocalizedStringKey, icon: String, logo: NSImage? = nil) -> some View {
        TabButton(title: title, icon: icon, logo: logo, selected: model.tab == tab, namespace: tabNamespace) {
            withAnimation(AppMotion.snappy) { model.tab = tab }
        }
    }

    /// Bandeja de entrada: no cabe como pestaña junto al notch, asi que va aqui,
    /// con el numero de correos sin leer.
    private var mailButton: some View {
        Button {
            withAnimation(AppMotion.snappy) { model.tab = model.tab == .mail ? .shelf : .mail }
        } label: {
            CircleIconLabel(icon: "envelope", logo: AgentIcons.mail(mail.source), active: model.tab == .mail)
                .overlay(alignment: .topTrailing) {
                    if !mail.messages.isEmpty {
                        Text(verbatim: mail.messages.count > 40 ? "40+" : "\(mail.messages.count)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Capsule().fill(AppColors.danger))
                            .offset(x: 3, y: -2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(Text("Bandeja de entrada"))
        .accessibilityLabel(Text("Bandeja de entrada"))
    }

    /// Temporizador (Pomodoro), alarmas y Mantener despierto. El boton se pone
    /// naranja (como el Reloj de Apple) mientras hay algo en marcha.
    private var timerMenu: some View {
        Menu {
            Section("Temporizador") {
                if focus.isRunning {
                    Button("Detener temporizador", systemImage: "stop.fill") { focus.stop() }
                }
                ForEach(FocusTimer.timerPresets, id: \.self) { minutes in
                    Button(minutes == 25 ? String(localized: "Pomodoro · 25 min") : String(localized: "\(minutes) min")) {
                        focus.start(minutes: minutes)
                    }
                }
            }
            Section("Alarmas") {
                ForEach(focus.alarms, id: \.self) { date in
                    Button {
                        focus.removeAlarm(date)
                    } label: {
                        Label(String(localized: "Quitar alarma de las \(date.formatted(date: .omitted, time: .shortened))"), systemImage: "alarm")
                    }
                }
                Button("Nueva alarma…", systemImage: "plus") {
                    alarmTime = FocusTimer.nextOccurrence(of: .now.addingTimeInterval(3600))
                    model.isPreviewing = true
                    showAlarm = true
                }
            }
            Section("Mantener despierto") {
                if focus.isAwake {
                    Button("Dejar de mantener despierto", systemImage: "moon.zzz") { focus.stopAwake() }
                }
                ForEach(FocusTimer.awakePresets, id: \.self) { minutes in
                    Button(minutes < 60 ? String(localized: "\(minutes) min") : String(localized: "\(minutes / 60) h")) {
                        focus.stayAwake(minutes: minutes)
                    }
                }
                Button("Hasta que lo pare") { focus.stayAwake(minutes: nil) }
            }
        } label: {
            CircleIconLabel(
                icon: focus.isRunning ? "timer" : !focus.alarms.isEmpty ? "alarm.fill" : focus.isAwake ? "cup.and.saucer.fill" : "timer",
                logo: AgentIcons.clock,
                active: focus.isRunning || focus.isAwake || !focus.alarms.isEmpty,
                activeColor: focus.isRunning || !focus.alarms.isEmpty ? AppColors.clock : AppColors.accent
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Temporizador, alarmas y mantener despierto"))
        .popover(isPresented: $showAlarm, arrowEdge: .bottom) {
            AlarmPicker(time: $alarmTime) {
                focus.addAlarm(at: alarmTime)
                showAlarm = false
            }
        }
        .onChange(of: showAlarm) { _, shown in
            if !shown { model.isPreviewing = false }
        }
    }

    /// Acciones con todo lo de la bandeja: enviar y crear un PDF.
    @ViewBuilder
    private var shelfActions: some View {
        let files = store.shelfFileURLs()
        let pages = files.filter { FileActions.isPDF($0) || FileActions.isImage($0) }
        if !files.isEmpty {
            Divider()
            Button("Enviar todo por AirDrop", systemImage: "dot.radiowaves.left.and.right") {
                model.close()
                QuickShare.send(files, via: .sendViaAirDrop)
            }
            Button("Enviar todo por correo", systemImage: "envelope") {
                model.close()
                QuickShare.send(files, via: .composeEmail)
            }
        }
        if pages.count >= 2 {
            Button(String(localized: "Unir en un PDF (\(pages.count))"), systemImage: "doc.on.doc") {
                Task {
                    let name = String(localized: "Documentos unidos")
                    if let output = try? await Task.detached { try FileActions.makePDF(from: pages, name: name) }.value {
                        withAnimation(AppMotion.snappy) { try? store.addGeneratedFile(output) }
                    } else {
                        NSSound.beep()
                    }
                }
            }
        }
    }

    private var menu: some View {
        Menu {
            Button("Ajustes…", systemImage: "gearshape") { model.onOpenSettings?() }
            Divider()
            switch model.tab {
            case .shelf:
                Button("Añadir archivos…", systemImage: "plus") { chooseFiles() }
                shelfActions
                Divider()
                Button("Vaciar bandeja…", systemImage: "trash", role: .destructive) { confirmClearShelf() }
            case .clipboard:
                Button("Borrar historial…", systemImage: "trash", role: .destructive) { confirmClearHistory() }
            case .agents, .calendar, .mail:
                EmptyView()
            case .screenshots:
                Button("Cambiar carpeta de capturas…", systemImage: "folder.badge.gearshape") {
                    model.close()
                    screenshots.chooseFolder()
                }
                if screenshots.folder != nil {
                    Button("Mostrar la carpeta en Finder", systemImage: "folder") { screenshots.showFolderInFinder() }
                }
            }
            Divider()
            Button("Salir de Nook", systemImage: "power") { NSApp.terminate(nil) }
        } label: {
            CircleIconLabel(icon: "ellipsis")
        }
        // Estilo boton + plain: respeta la etiqueta propia (el borderless la recorta).
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Más opciones"))
    }

    /// El notch esta por encima de todo: se cierra para no tapar el dialogo.
    private func chooseFiles() {
        model.close()
        FileImporter.chooseFiles(into: store)
    }

    // MARK: - Borrar con confirmacion

    /// Borrar es lo unico que pierde datos: siempre se pregunta antes.
    private func confirmClearShelf() {
        guard confirm(
            title: String(localized: "¿Vaciar la bandeja?"),
            message: String(localized: "Se borrarán todos los elementos de la bandeja. No se puede deshacer."),
            action: String(localized: "Vaciar")
        ) else { return }
        store.clearShelf()
    }

    private func confirmClearHistory() {
        guard confirm(
            title: String(localized: "¿Borrar el historial?"),
            message: String(localized: "Se borrarán todos los elementos del historial salvo los fijados. No se puede deshacer."),
            action: String(localized: "Borrar")
        ) else { return }
        store.clearHistory()
    }

    private func confirm(title: String, message: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        let destructive = alert.addButton(withTitle: action)
        destructive.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancelar"))
        // El notch esta por encima de todo: se cierra para no tapar la alerta.
        model.close()
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Segmento del control de pestañas. La activa, sobre una pildora azul solida (un
/// cristal tintado sobre el panel pierde el color) que se desliza entre segmentos.
private struct TabButton: View {
    let title: LocalizedStringKey
    let icon: String
    /// Logo oficial de una app (Spotify, Claude...) en lugar del simbolo.
    var logo: NSImage?
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .frame(width: 17, height: 17)
                        .scaleEffect(hovering && !selected ? 1.08 : 1)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? AppColors.onAccent : (hovering ? AppColors.accent : AppColors.textPrimary.opacity(0.85)))
                }
            }
                .frame(width: 30, height: 24)
                .background {
                    if selected {
                        Capsule()
                            .fill(AppColors.accent)
                            .shadow(color: AppColors.accent.opacity(0.4), radius: 4, y: 1)
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    } else if hovering {
                        Capsule().fill(AppColors.notchText.opacity(0.08))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppMotion.snappy, value: hovering)
        .animation(AppMotion.snappy, value: selected)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}

/// Boton redondo de cristal de la cabecera: el icono se tiñe de azul al pasar.
private struct CircleIconLabel: View {
    let icon: String
    /// Icono oficial de una app (Reloj, Mail...) en lugar del simbolo.
    var logo: NSImage?
    /// Algo en marcha (temporizador...): icono en color fijo.
    var active = false
    var activeColor = AppColors.accent
    @State private var hovering = false

    var body: some View {
        Group {
            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .scaleEffect(hovering && !AppMotion.reduceMotion ? 1.08 : 1)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(active ? activeColor : hovering ? AppColors.accent : AppColors.textPrimary.opacity(0.85))
            }
        }
            .frame(width: 30, height: 30)
            .liquidGlass(in: Circle(), interactive: true)
            // Con logo, lo que esta en marcha se marca con un aro de color.
            .overlay { if logo != nil, active { Circle().strokeBorder(activeColor, lineWidth: 2) } }
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(AppMotion.snappy, value: hovering)
    }
}

/// Elegir la hora de una alarma, al estilo del Reloj de Apple: la hora grande y
/// el boton naranja.
private struct AlarmPicker: View {
    @Binding var time: Date
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Nueva alarma")
                .font(AppTypography.bodyStrong)
                .foregroundStyle(AppColors.textSecondary)
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
                .font(.system(size: 22, weight: .light).monospacedDigit())
            Text(verbatim: summary)
                .font(AppTypography.subtitle)
                .foregroundStyle(AppColors.textSecondary)
            Button(action: onAdd) {
                Text("Añadir")
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(AppColors.clock))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 200)
    }

    /// "Hoy" o "Mañana", segun si esa hora ya ha pasado.
    private var summary: String {
        let next = FocusTimer.nextOccurrence(of: time)
        return Calendar.current.isDateInToday(next) ? String(localized: "Sonará hoy") : String(localized: "Sonará mañana")
    }
}
