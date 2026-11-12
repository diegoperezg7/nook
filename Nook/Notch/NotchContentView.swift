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
    @Environment(BatteryCenter.self) private var battery
    @Environment(SystemHUD.self) private var hud
    @State private var showBattery = false
    @State private var showMirror = false
    @State private var showClock = false
    @State private var showCall = false
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
        // Al abrir: por si acabas de conectar los AirPods.
        .onAppear { battery.refresh() }
        #if DEBUG
        // `-VisorOpenClock YES`: abre el reloj al abrir el panel (capturas).
        .task {
            guard UserDefaults.standard.bool(forKey: "VisorOpenClock") else { return }
            try? await Task.sleep(for: .seconds(0.8))
            model.isPreviewing = true
            showClock = true
        }
        // `-VisorOpenBattery YES`: igual con la bateria de los auriculares.
        .task {
            guard UserDefaults.standard.bool(forKey: "VisorOpenBattery") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            battery.refresh()
            model.isPreviewing = true
            showBattery = true
        }
        // `-VisorOpenCall YES` (con `-VisorDemoCall <app>`): abre el desplegable de la
        // llamada; `-VisorDemoMuted YES` lo enseña con el micro silenciado.
        .task {
            guard UserDefaults.standard.bool(forKey: "VisorOpenCall") else { return }
            CallState.shared.micMuted = UserDefaults.standard.bool(forKey: "VisorDemoMuted")
            try? await Task.sleep(for: .seconds(1.5))
            model.isPreviewing = true
            showCall = true
        }
        #endif
        // La forma abierta tiene orejas concavas arriba: su cuerpo visible es mas
        // estrecho que la ventana. Sin esto los margenes se quedaban en 2 pt.
        .padding(.horizontal, NotchMetrics.openEar)
    }

    private var header: some View {
        HStack(spacing: 0) {
            tabs.frame(maxWidth: .infinity, alignment: .leading)
            // Hueco del notch fisico: ahi no se ve nada.
            Color.clear.frame(width: model.metrics.hasNotch ? model.metrics.notchWidth : 0)
            let call = MeetingControls.current(micInUse: hud.micInUse)
            // Como mucho cuatro botones por lado con separacion 8: un quinto entraria
            // bajo la camara en los portatiles. En llamada, un solo boton (que despliega
            // micro, camara y colgar) en lugar de agentes, reloj y espejo.
            HStack(spacing: NotchMetrics.headerButtonSpacing) {
                if let call {
                    callButton(call)
                } else {
                    agentsButton
                    timerMenu
                    mirrorButton
                }
                batteryButton
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
                .keyboardShortcut("1", modifiers: .command)
            tabButton(.clipboard, title: "Portapapeles", icon: "list.clipboard.fill")
                .keyboardShortcut("2", modifiers: .command)
            tabButton(.screenshots, title: "Capturas", icon: "camera.viewfinder", logo: AgentIcons.screenshot)
                .keyboardShortcut("3", modifiers: .command)
            tabButton(.calendar, title: "Calendario", icon: "calendar", logo: AgentIcons.calendar)
                .keyboardShortcut("4", modifiers: .command)
            if mail.isEnabled {
                tabButton(.mail, title: "Bandeja de entrada", icon: "envelope", logo: AgentIcons.mail(mail.source))
                    .keyboardShortcut("5", modifiers: .command)
                    .overlay(alignment: .topTrailing) { unreadBadge }
            }
        }
        .padding(3)
        .liquidGlass(in: Capsule())
    }

    private func tabButton(_ tab: NotchViewModel.Tab, title: LocalizedStringKey, icon: String, logo: NSImage? = nil) -> some View {
        TabButton(title: title, icon: icon, logo: logo, selected: model.tab == tab, namespace: tabNamespace) {
            withAnimation(AppMotion.snappy) { model.tab = tab }
        }
    }

    /// En llamada: un boton verde; al pulsarlo salen micro, camara y colgar.
    private func callButton(_ call: MeetingControls.Target) -> some View {
        let state = CallState.shared
        return Button {
            model.isPreviewing = true
            showCall = true
        } label: {
            Image(systemName: "phone.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.onAccent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(AppColors.success))
                // Micro silenciado: se ve sin abrir el boton.
                .overlay(alignment: .bottomTrailing) {
                    if state.micMuted {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(AppColors.onAccent)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(AppColors.danger))
                            .offset(x: 3, y: 3)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text("Llamada en \(call.name)"))
        .accessibilityLabel(Text("Llamada en \(call.name)"))
        .popover(isPresented: $showCall, arrowEdge: .bottom) {
            CallPanel(call: call, state: state) { action in run(action, call) }
        }
        .onChange(of: showCall) { _, shown in
            if !shown { model.isPreviewing = false }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func run(_ action: MeetingControls.Action, _ call: MeetingControls.Target) {
        // Micro y camara dejan el panel abierto para ver el cambio; colgar lo cierra.
        if action == .leave {
            showCall = false
            model.close()
        }
        let outcome = MeetingControls.perform(action, on: call)
        switch outcome {
        case .pressed, .shortcut, .systemMute:
            let state = CallState.shared
            if action == .mic { state.micMuted.toggle() }
            if action == .camera { state.cameraOff.toggle() }
            if action == .leave { state.reset() }
        case .needsPermission, .failed:
            break
        }
        switch outcome {
        case .needsPermission:
            hud.show(.notice(icon: "hand.raised.fill", text: String(localized: "Activa Accesibilidad en Ajustes")), for: 2.5)
        case .failed:
            let text = switch action {
            case .mic: String(localized: "No se pudo silenciar en \(call.name)")
            case .camera: String(localized: "No se pudo apagar la cámara en \(call.name)")
            case .leave: String(localized: "No se pudo colgar en \(call.name)")
            }
            hud.show(.notice(icon: "exclamationmark.triangle.fill", text: text), for: 2.5)
        case .systemMute:
            hud.show(.notice(icon: "mic.slash.fill", text: String(localized: "Micro del Mac silenciado")), for: 2)
        case .pressed, .shortcut:
            break
        }
    }

    /// AirPods conectados: su modelo en un aro de bateria; al pulsar, cada pieza con su %.
    /// Espejo: la camara para verte antes de una llamada.
    private var mirrorButton: some View {
        Button {
            model.isPreviewing = true
            showMirror = true
        } label: {
            Image(systemName: "person.crop.square.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                .frame(width: 30, height: 30)
                .liquidGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text("Espejo"))
        .accessibilityLabel(Text("Espejo"))
        .popover(isPresented: $showMirror, arrowEdge: .bottom) { MirrorView() }
        .onChange(of: showMirror) { _, shown in
            if !shown { model.isPreviewing = false }
        }
    }

    @ViewBuilder
    private var batteryButton: some View {
        if let headline = battery.headline {
            Button {
                battery.refresh()
                model.isPreviewing = true
                showBattery = true
            } label: {
                BatteryRing(symbol: headline.symbol, level: headline.level, size: 30, lineWidth: 2.5)
                    .liquidGlass(in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: "\(headline.level) %"))
            .accessibilityLabel(Text("Batería de los auriculares"))
            .popover(isPresented: $showBattery, arrowEdge: .bottom) {
                BatteryPanel(battery: battery)
            }
            .onChange(of: showBattery) { _, shown in
                if !shown { model.isPreviewing = false }
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Agentes de IA: boton redondo junto al temporizador; el correo ocupa su pestaña.
    private var agentsButton: some View {
        Button {
            withAnimation(AppMotion.snappy) { model.tab = model.tab == .agents ? .shelf : .agents }
        } label: {
            CircleIconLabel(icon: "brain", logo: AgentIcons.claude, active: model.tab == .agents)
                .overlay { usageRing }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("6", modifiers: .command)
        .help(usageHelp)
        .accessibilityLabel(Text("Agentes de IA"))
    }

    /// Ventana de 5 h de Claude: la primera del snapshot de consumo.
    private var fiveHour: SubscriptionUsage.Window? { agents.claudeUsage?.windows.first }

    /// Aro con el % usado de las 5 h: naranja desde el 80 %, rojo desde el 95 %.
    @ViewBuilder
    private var usageRing: some View {
        if let window = fiveHour, model.tab != .agents {
            let used = min(max(window.usedPercent, 0), 100) / 100
            Circle()
                .trim(from: 0, to: used)
                .stroke(used >= 0.95 ? AppColors.danger : used >= 0.8 ? AppColors.warning : AppColors.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1)
                .allowsHitTesting(false)
        }
    }

    private var usageHelp: Text {
        guard let window = fiveHour else { return Text("Agentes de IA") }
        let used = window.usedRounded
        guard let time = window.resetLabel() else { return Text("Agentes de IA · \(window.label): \(used) %") }
        return Text("Agentes de IA · \(window.label): \(used) %, se reinicia \(time)")
    }

    /// Numero de correos sin leer sobre la pestaña de correo.
    @ViewBuilder
    private var unreadBadge: some View {
        if mail.unreadCount > 0 {
            Text(verbatim: "\(mail.unreadCount)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(Capsule().fill(AppColors.danger))
                .offset(x: 4, y: -4)
                .allowsHitTesting(false)
                .transition(.scale.combined(with: .opacity))
        }
    }

    /// Temporizador (Pomodoro), alarmas y Mantener despierto. El boton se pone
    /// naranja (como el Reloj de Apple) mientras hay algo en marcha.
    private var timerMenu: some View {
        Button {
            model.isPreviewing = true
            showClock = true
        } label: {
            CircleIconLabel(
                icon: "timer",
                logo: AgentIcons.clock,
                active: focus.isRunning || focus.isPaused || focus.isAwake || !focus.alarms.isEmpty,
                activeColor: focus.isRunning || focus.isPaused || !focus.alarms.isEmpty ? AppColors.clock : AppColors.accent
            )
            .overlay { if focus.isRunning || focus.isPaused { TimerRing(focus: focus, lineWidth: 2).padding(1) } }
        }
        .buttonStyle(.plain)
        .help(Text("Temporizador, alarmas y mantener despierto"))
        .accessibilityLabel(Text("Reloj"))
        .popover(isPresented: $showClock, arrowEdge: .bottom) { ClockPanel(focus: focus) }
        .onChange(of: showClock) { _, shown in
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
                    if let output = try? await Task.detached(operation: { try FileActions.makePDF(from: pages, name: name) }).value {
                        withAnimation(AppMotion.snappy) { try? store.addGeneratedFile(output) }
                    } else {
                        NSSound.beep()
                    }
                }
            }
        }
    }

    /// Cuentagotas de macOS: el color elegido va al portapapeles en HEX.
    private func pickColor() {
        model.close()
        NSColorSampler().show { color in
            guard let color, let hex = FileActions.hex(color) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            hud.show(.notice(icon: "eyedropper.full", text: String(localized: "\(hex) copiado")), for: 2)
        }
    }

    private var menu: some View {
        Menu {
            Button("Ajustes…", systemImage: "gearshape") { model.onOpenSettings?() }
            Button("Buscar actualizaciones…", systemImage: "arrow.down.circle") { model.onCheckForUpdates?() }
            Button("Cuentagotas", systemImage: "eyedropper") { pickColor() }
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
            Button("Salir de Visor", systemImage: "power") { NSApp.terminate(nil) }
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
/// Desplegable del boton de llamada: micro, camara y colgar, con su estado.
private struct CallPanel: View {
    let call: MeetingControls.Target
    let state: CallState
    let perform: (MeetingControls.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: call.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            HStack(spacing: 18) {
                toggle(
                    on: state.micMuted, icon: state.micMuted ? "mic.slash.fill" : "mic.fill",
                    title: state.micMuted ? "Silenciado" : "Micro", action: .mic
                )
                if call.hasCamera {
                    toggle(
                        on: state.cameraOff, icon: state.cameraOff ? "video.slash.fill" : "video.fill",
                        title: state.cameraOff ? "Cámara apagada" : "Cámara", action: .camera
                    )
                }
                button(icon: "phone.down.fill", title: "Colgar", fill: AppColors.danger, tint: AppColors.onAccent, action: .leave)
            }
        }
        .padding(14)
        .presentationBackground(AppColors.panel)
    }

    /// Como en FaceTime: activo (silenciado, camara apagada) en relleno claro.
    private func toggle(on: Bool, icon: String, title: LocalizedStringKey, action: MeetingControls.Action) -> some View {
        button(icon: icon, title: title, fill: on ? AppColors.textPrimary : AppColors.controlTrack,
               tint: on ? AppColors.panel : AppColors.textPrimary, action: action)
    }

    private func button(icon: String, title: LocalizedStringKey, fill: Color, tint: Color, action: MeetingControls.Action) -> some View {
        Button { perform(action) } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(fill))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .animation(AppMotion.snappy, value: icon)
    }
}

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

/// Columna de la rueda del temporizador: los numeros se desplazan con la rueda o el
/// trackpad y encajan en la franja central; un clic en un numero tambien lo elige.
private struct DurationWheel: View {
    @Binding var value: Int?
    let range: Range<Int>
    let unit: String
    static let rowHeight: CGFloat = 30
    private static let visibleRows: CGFloat = 3

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(range, id: \.self) { number in
                        Text(verbatim: "\(number)")
                            .font(.system(size: 20, weight: number == value ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(number == value ? AppColors.textPrimary : AppColors.textSecondary)
                            .frame(width: 40, height: Self.rowHeight, alignment: .trailing)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(AppMotion.snappy) { value = number } }
                            .id(number)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.vertical, Self.rowHeight, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $value, anchor: .center)
            // El valor inicial no se centra solo: se lleva a la franja al aparecer.
            .onAppear { proxy.scrollTo(value ?? 0, anchor: .center) }
            }
            .frame(width: 44, height: Self.rowHeight * Self.visibleRows)
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
            Text(verbatim: unit)
                .font(AppTypography.bodyStrong)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 26, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: unit))
        .accessibilityValue(Text(verbatim: "\(value ?? 0)"))
        .accessibilityAdjustableAction { direction in
            let current = value ?? 0
            switch direction {
            case .increment: value = min(current + 1, range.upperBound - 1)
            case .decrement: value = max(current - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// Lo que queda del temporizador en un aro naranja que se vacia, como el Reloj de Apple.
private struct TimerRing: View {
    let focus: FocusTimer
    var lineWidth: CGFloat = 6

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Circle()
                .trim(from: 0, to: fraction(at: context.date))
                .stroke(AppColors.clock, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction(at: context.date))
        }
        .allowsHitTesting(false)
    }

    private func fraction(at date: Date) -> Double {
        guard focus.total > 0 else { return 0 }
        let left = focus.pausedRemaining ?? focus.end.map { $0.timeIntervalSince(date) } ?? 0
        return min(max(left / focus.total, 0), 1)
    }
}

/// Reloj: temporizador, alarmas y mantener despierto, en paginas como la app Reloj.
private struct ClockPanel: View {
    let focus: FocusTimer
    private enum Page: Hashable { case timer, alarms, awake }
    @State private var page: Page
    @State private var adding = false
    @State private var newAlarm = FocusTimer.nextOccurrence(of: .now.addingTimeInterval(3600))
    /// Duracion elegida en la rueda: la ultima usada o 10 min.
    @State private var hours: Int?
    @State private var minutes: Int?
    @State private var seconds: Int?

    init(focus: FocusTimer) {
        self.focus = focus
        let last = focus.recents.first ?? 600
        _hours = State(initialValue: last / 3600)
        _minutes = State(initialValue: last / 60 % 60)
        _seconds = State(initialValue: last % 60)
        _page = State(initialValue: focus.isRunning || focus.isPaused ? .timer : !focus.alarms.isEmpty ? .alarms : focus.isAwake ? .awake : .timer)
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("", selection: $page) {
                Text("Temporizador").tag(Page.timer)
                Text("Alarmas").tag(Page.alarms)
                Text("Despierto").tag(Page.awake)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch page {
                case .timer: timer
                case .alarms: alarms
                case .awake: awake
                }
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
        .padding(16)
        // Ancho para que las tres pestañas del selector quepan enteras.
        .frame(width: 340)
        .animation(AppMotion.snappy, value: page)
        .animation(AppMotion.snappy, value: focus.isRunning)
        .animation(AppMotion.snappy, value: focus.isPaused)
        .animation(AppMotion.snappy, value: adding)
    }

    // MARK: Temporizador

    @ViewBuilder
    private var timer: some View {
        if focus.isRunning || focus.isPaused {
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(AppColors.clock.opacity(0.18), lineWidth: 6)
                    TimerRing(focus: focus)
                    VStack(spacing: 2) {
                        Group {
                            if let end = focus.end {
                                Text(timerInterval: Date.now...end, countsDown: true)
                            } else {
                                Text(verbatim: Self.clock(focus.pausedRemaining ?? 0))
                            }
                        }
                        .font(.system(size: 30, weight: .light).monospacedDigit())
                        .multilineTextAlignment(.center)
                        if let end = focus.end {
                            Label(end.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                                .font(AppTypography.subtitle)
                                .foregroundStyle(AppColors.textSecondary)
                        } else {
                            Text("En pausa")
                                .font(AppTypography.subtitle)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .frame(width: 150, height: 150)
                HStack(spacing: 10) {
                    pill("Cancelar", color: AppColors.textPrimary.opacity(0.12), text: AppColors.textPrimary) { focus.stop() }
                    if focus.isPaused {
                        pill("Reanudar", color: AppColors.clock, text: .white) { focus.resume() }
                    } else {
                        pill("Pausar", color: AppColors.clock.opacity(0.18), text: AppColors.clock) { focus.pause() }
                    }
                }
            }
        } else {
            // Como el Reloj de Apple: rueda de horas, minutos y segundos, las
            // duraciones recientes y Cancelar / Iniciar.
            VStack(spacing: 14) {
                HStack(spacing: 4) {
                    DurationWheel(value: $hours, range: 0..<24, unit: "h")
                    DurationWheel(value: $minutes, range: 0..<60, unit: "min")
                    DurationWheel(value: $seconds, range: 0..<60, unit: "s")
                }
                .background {
                    // Franja de la seleccion, detras de las tres columnas.
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.textPrimary.opacity(0.08))
                        .frame(height: DurationWheel.rowHeight)
                }
                if !focus.recents.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(focus.recents, id: \.self) { duration in
                            Button { focus.start(seconds: duration) } label: {
                                Text(verbatim: Self.duration(duration))
                                    .font(AppTypography.bodyStrong.monospacedDigit())
                                    .foregroundStyle(AppColors.clock)
                                    .padding(.horizontal, 10)
                                    .frame(height: 26)
                                    .background(Capsule().fill(AppColors.clock.opacity(0.15)))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(Text("Iniciar"))
                        }
                    }
                }
                HStack {
                    // Como en el Reloj: Cancelar solo hace algo con un temporizador en marcha.
                    pill("Cancelar", color: AppColors.textPrimary.opacity(0.12), text: AppColors.textPrimary) {}
                        .disabled(true)
                        .opacity(0.5)
                    Spacer()
                    pill("Iniciar", color: AppColors.clock, text: .white) { focus.start(seconds: wheelSeconds) }
                        .disabled(wheelSeconds == 0)
                        .opacity(wheelSeconds == 0 ? 0.5 : 1)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var wheelSeconds: Int {
        (hours ?? 0) * 3600 + (minutes ?? 0) * 60 + (seconds ?? 0)
    }

    /// "25 min", "1 h 30 min", "45 s".
    static func duration(_ total: Int) -> String {
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        var parts: [String] = []
        if h > 0 { parts.append(String(localized: "\(h) h")) }
        if m > 0 { parts.append(String(localized: "\(m) min")) }
        if s > 0 { parts.append(String(localized: "\(s) s")) }
        return parts.joined(separator: " ")
    }

    // MARK: Alarmas

    private var alarms: some View {
        VStack(spacing: 0) {
            if focus.alarms.isEmpty && !adding {
                Text("Sin alarmas")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.vertical, 8)
            }
            ForEach(focus.alarms, id: \.self) { date in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 28, weight: .light).monospacedDigit())
                        Text(Calendar.current.isDateInToday(date) ? "Hoy" : "Mañana")
                            .font(AppTypography.subtitle)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    Button { focus.removeAlarm(date) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.danger)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColors.danger.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help(Text("Quitar alarma"))
                    .accessibilityLabel(Text("Quitar alarma"))
                }
                .padding(.vertical, 6)
                Divider()
            }
            if adding {
                HStack {
                    DatePicker("", selection: $newAlarm, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                    Spacer()
                    pill("Añadir", color: AppColors.clock, text: .white) {
                        focus.addAlarm(at: newAlarm)
                        adding = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 10)
            } else {
                Button {
                    newAlarm = FocusTimer.nextOccurrence(of: .now.addingTimeInterval(3600))
                    adding = true
                } label: {
                    Label("Nueva alarma", systemImage: "plus")
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(AppColors.clock)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
    }

    // MARK: Mantener despierto

    private var awake: some View {
        VStack(spacing: 12) {
            Image(systemName: focus.isAwake ? "cup.and.saucer.fill" : "moon.zzz.fill")
                .font(.system(size: 26))
                .foregroundStyle(focus.isAwake ? AppColors.accent : AppColors.textSecondary)
            Text(awakeStatus)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            HStack(spacing: 8) {
                ForEach(FocusTimer.awakePresets, id: \.self) { minutes in
                    awakeOption(minutes < 60 ? String(localized: "\(minutes) min") : String(localized: "\(minutes / 60) h")) {
                        focus.stayAwake(minutes: minutes)
                    }
                }
                awakeOption(String(localized: "Siempre")) { focus.stayAwake(minutes: nil) }
            }
            if focus.isAwake {
                pill("Desactivar", color: AppColors.textPrimary.opacity(0.12), text: AppColors.textPrimary) { focus.stopAwake() }
            }
        }
    }

    private var awakeStatus: String {
        guard focus.isAwake else { return String(localized: "El Mac puede dormir con normalidad") }
        guard let until = focus.awakeUntil else { return String(localized: "Despierto hasta que lo desactives") }
        return String(localized: "Despierto hasta las \(until.formatted(date: .omitted, time: .shortened))")
    }

    private func awakeOption(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(AppTypography.bodyStrong)
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(AppColors.accent.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 1:05:09 o 4:09.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func pill(_ title: LocalizedStringKey, color: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.bodyStrong)
                .foregroundStyle(text)
                .padding(.horizontal, 18)
                .frame(height: 30)
                .background(Capsule().fill(color))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
