import EventKit
import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: ModelContainer?
    private var store: ItemStore?
    private var notch: NotchController?
    private var monitor: ClipboardMonitor?
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var whatsNewWindow: NSWindow?
    private let permissions = PermissionState()
    private var defaultsObserver: NSObjectProtocol?
    private var services: ServiceProvider?
    private var screenshots: ScreenshotLibrary?
    private var agents: AgentMonitor?
    private var hud: SystemHUD?
    private var calendar: CalendarService?
    private var focus: FocusTimer?
    private var shelfExpiryTimer: Timer?
    private let updater = Updater()
    private var mail: MailService?
    private var basket: BasketController?
    private var dictation: Dictation?
    private var ring: ActionRingController?
    private var ringHotKey: HotKey?
    private var battery: BatteryCenter?
    private let windowSnap = WindowSnap()
    private var selection: SelectionActions?
    private let notificationFeed = NotificationFeed()
    private let notificationBanners = NotificationBanners()
    private let launcher = LauncherController()
    private var launcherHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsKey.importFromNook()
        SettingsKey.registerDefaults()
        // Los tests usan la app como host: sin panel ni monitores.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        if DataHome.dataLeftInContainer {
            let alert = NSAlert()
            alert.messageText = String(localized: "Tus datos siguen en la versión anterior")
            alert.informativeText = String(localized: "Instala y abre una vez Nook 0.11 para que copie tu bandeja y tu historial; después vuelve a esta versión. No se ha borrado nada.")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        DataHome.importDefaultsIfNeeded()
        // Antes de abrir el almacen: decide (y si hace falta copia) donde estan los datos.
        let migration = DataHome.prepare()
        NSLog("Visor datos: %@", migration)
        DataHome.exportDefaults()
        let container = Self.makeContainer()
        let store = ItemStore(
            context: container.mainContext,
            itemsDirectory: ItemStore.supportDirectory.appendingPathComponent("Items", isDirectory: true)
        )
        #if !DEBUG
        LegacyImport.run(into: store)
        #endif
        let screenshots = ScreenshotLibrary()
        let agents = AgentMonitor()
        let hud = SystemHUD()
        let calendar = CalendarService()
        let focus = FocusTimer()
        let mail = MailService()
        let battery = BatteryCenter()
        mail.onNew = { [weak hud, weak mail] message in
            guard UserDefaults.standard.bool(forKey: SettingsKey.hudMail),
                  MailService.isImportant(sender: message.sender,
                                          filter: UserDefaults.standard.string(forKey: SettingsKey.mailImportant) ?? "")
            else { return }
            let preview = SystemHUD.Preview(
                symbol: "envelope.fill", title: message.sender, subtitle: message.subject,
                body: message.preview, actionTitle: String(localized: "Abrir correo"),
                extras: [
                    .init(symbol: "envelope.open", title: String(localized: "Marcar como leído")) { mail?.markRead(message) },
                    .init(symbol: "trash", title: String(localized: "Eliminar")) { mail?.trash(message) },
                ]
            ) { mail?.open(message) }
            hud?.show(.mail(sender: message.sender), for: 3, preview: preview)
        }
        agents.onChange = { [weak hud, weak agents] session, event in
            guard UserDefaults.standard.bool(forKey: SettingsKey.hudAgents) else { return }
            let waiting = event == .waiting
            let vscode = session.tool == .claudeVSCode
            var question = ""
            if case let .pending(text?) = session.status { question = text }
            let preview = SystemHUD.Preview(
                symbol: "terminal.fill", appIcon: vscode ? AgentIcons.vscode : nil,
                title: session.project ?? String(localized: "Agente"),
                subtitle: waiting ? String(localized: "Espera tu respuesta") : String(localized: "Ha terminado"),
                body: question, actionTitle: vscode ? String(localized: "Ir a VS Code") : String(localized: "Ir a la terminal")
            ) { agents?.focus(session) }
            hud?.show(.agent(project: session.project, waiting: waiting), for: waiting ? 6 : 4, preview: preview)
        }
        hud.focus = focus
        hud.calendar = calendar
        let notch = NotchController(store: store, container: container, screenshots: screenshots, agents: agents, hud: hud, calendar: calendar, focus: focus, mail: mail, battery: battery)
        let monitor = ClipboardMonitor(store: store)
        let basket = BasketController(store: store, container: container)
        let dictation = Dictation()
        hud.dictation = dictation
        dictation.onFinish = { [weak hud] text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            hud?.show(.notice(icon: "doc.on.clipboard.fill", text: String(localized: "Dictado copiado")), for: 2)
        }
        dictation.onDenied = { [weak hud] in
            hud?.show(.notice(icon: "mic.slash.fill", text: String(localized: "Sin permiso de micrófono")), for: 2.5)
        }
        let ring = ActionRingController(weather: Weather())

        notch.model.onOpenSettings = { [weak self] in self?.showSettings() }
        notch.model.onCheckForUpdates = { [weak self] in
            self?.notch?.model.close()
            self?.updater.checkForUpdates()
        }
        monitor.onAccessChange = { [weak notch] access in notch?.model.clipboardAccess = access }
        agents.onUsageAlert = { [weak hud, weak notch] window, usage in
            guard UserDefaults.standard.bool(forKey: SettingsKey.hudUsage) else { return }
            let percent = window.usedRounded
            // Una linea por ventana: porcentaje y hora a la que se reinicia.
            let lines = usage.windows.map { item in
                let used = item.usedRounded
                guard let time = item.resetLabel() else { return String(localized: "\(item.label): \(used) %") }
                return String(localized: "\(item.label): \(used) %, se reinicia \(time)")
            }
            let preview = SystemHUD.Preview(
                symbol: "gauge.with.dots.needle.67percent", appIcon: AgentIcons.claude,
                title: String(localized: "Consumo de Claude"),
                subtitle: String(localized: "Llevas el \(percent) % de \(window.label)"),
                body: lines.joined(separator: "\n"), actionTitle: String(localized: "Ver agentes")
            ) { notch?.model.open(reason: .hover, tab: .agents) }
            hud?.show(.usage(percent: percent, window: window.label), for: 5, preview: preview)
        }

        self.container = container
        self.store = store
        self.notch = notch
        self.monitor = monitor
        self.screenshots = screenshots
        self.agents = agents
        self.hud = hud
        self.calendar = calendar
        self.focus = focus
        self.mail = mail
        self.basket = basket
        self.dictation = dictation
        self.ring = ring
        self.selection = SelectionActions(store: store)
        notificationFeed.onNotice = { [weak hud, weak self] notice in
            // Con Accesibilidad mandan los avisos de macOS (traen Responder): sin duplicar.
            guard self?.notificationBanners.isRunning != true || !AXAccess.isTrusted else { return }
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notice.bundleID)
            let preview = SystemHUD.Preview(
                symbol: "bell.fill", appIcon: AgentIcons.icon(notice.bundleID),
                title: app.map { FileManager.default.displayName(atPath: $0.path) } ?? notice.title,
                subtitle: notice.title, body: notice.body, actionTitle: String(localized: "Abrir app")
            ) {
                guard let app else { return }
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            }
            hud?.show(.notification(bundleID: notice.bundleID, title: notice.title, body: notice.body), for: 5, preview: preview)
        }
        notificationBanners.onBanner = { [weak hud, weak self] banner in
            guard banner.appName != "Visor" else { return }
            let bundleID = banner.bundleID ?? ""
            let appURL = banner.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            var preview = SystemHUD.Preview(
                symbol: "bell.fill", appIcon: AgentIcons.icon(bundleID),
                title: banner.appName, subtitle: banner.title,
                body: banner.subtitle.isEmpty ? banner.body : banner.subtitle + " · " + banner.body,
                actionTitle: String(localized: "Abrir app")
            ) {
                guard let appURL else { return }
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            }
            if banner.canReply {
                preview.reply = { text, done in
                    guard let self else { return done(false) }
                    self.notificationBanners.reply(to: banner.id, text: text, completion: done)
                }
            }
            #if DEBUG
            NSLog("VISORBANNERS mostrar hud=%d", hud == nil ? 0 : 1)
            #endif
            hud?.show(.notification(bundleID: bundleID, title: banner.title, body: banner.body), for: banner.canReply ? 8 : 5, preview: preview)
        }
        windowSnap.onNeedsPermission = { [weak hud] in
            hud?.show(.notice(icon: "hand.raised.fill", text: String(localized: "Activa Accesibilidad en Ajustes")), for: 2.5)
        }
        self.battery = battery
        ring.actions = makeRingActions()

        notch.start()
        monitor.start()
        hud.start()
        calendar.start()
        mail.start()
        agents.start()
        battery.start()
        basket.start()
        store.trimHistory()
        store.recognizeMissingText()
        // Caducidad de la bandeja (si el usuario la activo): al arrancar y cada hora.
        store.expireShelf(days: UserDefaults.standard.integer(forKey: SettingsKey.shelfExpiryDays))
        shelfExpiryTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak store] _ in
            MainActor.assumeIsolated {
                store?.expireShelf(days: UserDefaults.standard.integer(forKey: SettingsKey.shelfExpiryDays))
            }
        }

        let services = ServiceProvider(store: store)
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        self.services = services
        applySettings()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }

        #if DEBUG
        // `-NookReset YES` borra la bandeja y el historial (limpieza tras pruebas).
        if UserDefaults.standard.bool(forKey: "NookReset") {
            store.clearShelf()
            store.clearHistory()
        }
        // `-NookAddFiles "a.pdf|b.png"` llena la bandeja de desarrollo (capturas del README).
        if let paths = UserDefaults.standard.string(forKey: "NookAddFiles") {
            FileImporter.add(paths.split(separator: "|").map { URL(fileURLWithPath: String($0)) }, to: store)
        }
        notch.applyDebugLaunchArguments()
        // Estado de permisos de esta build (pruebas).
        NSLog("VISORPERMS ax=%d fda=%d calendar=%d", AXAccess.isTrusted ? 1 : 0,
              FileManager.default.isReadableFile(atPath: NotificationFeed.databasePath) ? 1 : 0,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess ? 1 : 0)
        if UserDefaults.standard.bool(forKey: "VisorProbeBiome") {
            DispatchQueue.global().async { NSLog("VISORBIOME\n%@", NotificationFeed.probeBiome()) }
        }
        if UserDefaults.standard.bool(forKey: "VisorProbeBanner") { BannerProbe.start() }
        if let app = UserDefaults.standard.string(forKey: "VisorDumpNotification") {
            DispatchQueue.global().async { NSLog("VISORDUMP\n%@", NotificationFeed.dumpLatest(of: app)) }
        }
        // `-VisorDemoNotice agent|waiting|notification`: aviso de ejemplo con su tarjeta (capturas).
        if let demo = UserDefaults.standard.string(forKey: "VisorDemoNotice") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.showDemoNotice(demo) }
        }
        if UserDefaults.standard.string(forKey: "NookOpen") == "settings" { showSettings(); return }
        if UserDefaults.standard.bool(forKey: "NookWhatsNew") { showWhatsNew(); return }
        #endif
        let firstLaunch = !UserDefaults.standard.bool(forKey: SettingsKey.onboardingDone)
        if WhatsNew.shouldShow(firstLaunch: firstLaunch) {
            showWhatsNew()
        } else if firstLaunch {
            showOnboarding()
        }
    }

    #if DEBUG
    private func showDemoNotice(_ kind: String) {
        let hold = UserDefaults.standard.double(forKey: "VisorDemoHold")
        let duration: TimeInterval = hold > 0 ? hold : 4
        switch kind {
        case "notification":
            let preview = SystemHUD.Preview(
                symbol: "bell.fill", appIcon: AgentIcons.icon("com.apple.MobileSMS"), title: "Mensajes",
                subtitle: "Ana", body: "¿Quedamos a las ocho en el sitio de siempre?", actionTitle: String(localized: "Abrir app")
            ) {}
            hud?.show(.notification(bundleID: "com.apple.MobileSMS", title: "Ana", body: "¿Quedamos a las ocho?"), for: duration, preview: preview)
            if UserDefaults.standard.bool(forKey: "VisorDemoCard") { hud?.activate() }
        default:
            let waiting = kind == "waiting"
            let preview = SystemHUD.Preview(
                symbol: "terminal.fill", title: "visor",
                subtitle: waiting ? String(localized: "Espera tu respuesta") : String(localized: "Ha terminado"),
                actionTitle: String(localized: "Ir a la terminal")
            ) {}
            hud?.show(.agent(project: "visor", waiting: waiting), for: duration, preview: preview)
            if UserDefaults.standard.bool(forKey: "VisorDemoCard") { hud?.activate() }
        }
    }
    #endif

    /// Novedades tras actualizar (una vez por version).
    private func showWhatsNew() {
        if whatsNewWindow == nil {
            let view = WhatsNewView { [weak self] in self?.whatsNewWindow?.close() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            whatsNewWindow = window
        }
        NSApp.activate()
        whatsNewWindow?.makeKeyAndOrderFront(nil)
    }

    private func applySettings() {
        let wantsHotKey = UserDefaults.standard.bool(forKey: SettingsKey.hotKeyEnabled)
        if wantsHotKey, hotKey == nil {
            hotKey = HotKey { [weak self] in
                MainActor.assumeIsolated { self?.notch?.toggleFromHotKey() }
            }
        } else if !wantsHotKey {
            hotKey = nil
        }
        notch?.refreshScreen()
        notch?.setHiddenFromCaptures(UserDefaults.standard.bool(forKey: SettingsKey.hideFromCaptures))
        store?.trimHistory()
        basket?.apply()
        windowSnap.apply()
        selection?.apply()
        notificationFeed.apply()
        if UserDefaults.standard.bool(forKey: SettingsKey.notifications) {
            notificationBanners.start()
        } else {
            notificationBanners.stop()
        }
        let wantsLauncher = UserDefaults.standard.bool(forKey: SettingsKey.launcher)
        if wantsLauncher, launcherHotKey == nil {
            // ⌥Espacio.
            launcherHotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), id: 3) { [weak self] in
                MainActor.assumeIsolated { self?.launcher.toggle() }
            }
        } else if !wantsLauncher {
            launcherHotKey = nil
            launcher.hide()
        }
        let wantsRing = UserDefaults.standard.bool(forKey: SettingsKey.actionRing)
        if wantsRing, ringHotKey == nil {
            // ⌃⌥Espacio.
            ringHotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), id: 2) { [weak self] in
                MainActor.assumeIsolated { self?.ring?.toggle() }
            }
        } else if !wantsRing {
            ringHotKey = nil
            ring?.hide()
        }
    }

    /// Herramientas del anillo, en el sentido de las agujas del reloj desde arriba.
    private func makeRingActions() -> [ActionRingController.Action] {
        [
            .init(id: "text", title: String(localized: "Copiar texto de la pantalla"), icon: "text.viewfinder") { [weak self] in
                self?.copyScreenText()
            },
            .init(id: "dictate", title: String(localized: "Dictar"), icon: "mic.fill") { [weak self] in
                self?.dictation?.toggle()
            },
            .init(id: "grab", title: String(localized: "Captura a la bandeja"), icon: "camera.viewfinder") { [weak self] in
                self?.grabToShelf()
            },
            .init(id: "timer", title: String(localized: "Pomodoro · 25 min"), icon: "timer") { [weak self] in
                self?.focus?.start(minutes: 25)
            },
            .init(id: "basket", title: String(localized: "Cesta"), icon: "basket.fill") { [weak self] in
                self?.basket?.show(at: NSEvent.mouseLocation)
            },
            .init(id: "clipboard", title: String(localized: "Historial del portapapeles"), icon: "list.clipboard.fill") { [weak self] in
                self?.notch?.toggleFromHotKey()
            },
        ]
    }

    private func copyScreenText() {
        Task {
            guard let url = await ScreenGrab.region() else { return }
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let text = (try? await Task.detached { try FileActions.recognizeText(in: url) }.value) ?? ""
            if text.isEmpty {
                hud?.show(.notice(icon: "text.viewfinder", text: String(localized: "No hay texto")), for: 2)
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                hud?.show(.notice(icon: "doc.on.clipboard.fill", text: String(localized: "Texto copiado")), for: 2)
            }
        }
    }

    private func grabToShelf() {
        Task {
            guard let url = await ScreenGrab.region() else { return }
            do {
                try store?.addGeneratedFile(url)
                hud?.show(.notice(icon: "tray.and.arrow.down.fill", text: String(localized: "En la bandeja")), for: 2)
            } catch {
                hud?.show(.notice(icon: "exclamationmark.triangle.fill", text: String(localized: "No se pudo guardar")), for: 2)
            }
        }
    }

    private func showSettings() {
        guard let calendar, let mail else { return }
        notch?.model.close()
        if settingsWindow == nil {
            let view = SettingsView(calendar: calendar, mail: mail, permissions: permissions) { [weak self] in
                self?.showOnboarding()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = String(localized: "Ajustes de Visor")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Introduccion del primer arranque (y "Ver de nuevo" en Ajustes).
    private func showOnboarding() {
        guard let calendar, let mail, let screenshots else { return }
        notch?.model.close()
        settingsWindow?.orderOut(nil)
        if onboardingWindow == nil {
            let view = OnboardingView(calendar: calendar, mail: mail, screenshots: screenshots, permissions: permissions) { [weak self] in
                UserDefaults.standard.set(true, forKey: SettingsKey.onboardingDone)
                self?.onboardingWindow?.close()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private static func makeContainer() -> ModelContainer {
        let directory = ItemStore.supportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Nook.store"))
        if let container = try? ModelContainer(for: NotchItem.self, configurations: configuration) {
            return container
        }
        // Si el almacen esta dañado, la app sigue funcionando en memoria.
        let memory = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: NotchItem.self, configurations: memory)
    }
}

#if DEBUG
/// `-VisorProbeBanner YES`: cada medio segundo mira las ventanas del Centro de
/// notificaciones y, si aparece un banner nuevo, registra su arbol de Accesibilidad
/// (roles, acciones y textos enmascarados).
@MainActor
enum BannerProbe {
    private static var timer: Timer?
    private static var lastSignature = ""

    static func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { check() }
        }
    }

    /// `-VisorProbeReply <texto>`: en el primer aviso de WhatsApp con "Responder",
    /// pulsa Responder, escribe el texto y lo envia (una sola vez), registrando cada paso.
    private static var replied = false

    private static func tryReply(in windows: [AXUIElement]) {
        guard !replied, let text = UserDefaults.standard.string(forKey: "VisorProbeReply") else { return }
        var queue = windows.map { ($0, 0) }
        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            var actions: CFArray?
            AXUIElementCopyActionNames(element, &actions)
            let names = actions as? [String] ?? []
            var description: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
            let label = (description as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\u{200E}\u{200F} "))
            if label.hasPrefix("WhatsApp"), let reply = names.first(where: { $0.contains("Responder") || $0.contains("Reply") }) {
                replied = true
                let result = AXUIElementPerformAction(element, reply as CFString)
                NSLog("VISORREPLY pulsar Responder: %d", result.rawValue)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { fill(text) }
                return
            }
            guard depth < 12 else { continue }
            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            queue += (children as? [AXUIElement] ?? []).map { ($0, depth + 1) }
        }
    }

    private static func fill(_ text: String) {
        guard let center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return }
        let app = AXUIElementCreateApplication(center.processIdentifier)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        var lines: [String] = []
        for window in windows as? [AXUIElement] ?? [] { dump(window, depth: 0, into: &lines) }
        NSLog("VISORREPLY tras Responder:\n%@", lines.joined(separator: "\n"))
        var field: AXUIElement?, send: AXUIElement?
        var queue = (windows as? [AXUIElement] ?? []).map { ($0, 0) }
        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            var role: CFTypeRef?, title: CFTypeRef?, description: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
            let roleName = role as? String ?? ""
            if field == nil, roleName == kAXTextAreaRole as String || roleName == kAXTextFieldRole as String { field = element }
            let name = ((title as? String ?? "") + " " + (description as? String ?? "")).lowercased()
            if send == nil, roleName == kAXButtonRole as String, name.contains("enviar") || name.contains("send") || name.contains("responder") || name.contains("reply") { send = element }
            guard depth < 14 else { continue }
            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            queue += (children as? [AXUIElement] ?? []).map { ($0, depth + 1) }
        }
        guard let field else { NSLog("VISORREPLY sin campo de texto"); return }
        AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let set = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString)
        NSLog("VISORREPLY escribir: %d", set.rawValue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let send {
                NSLog("VISORREPLY pulsar enviar: %d", AXUIElementPerformAction(send, kAXPressAction as CFString).rawValue)
            } else {
                NSLog("VISORREPLY sin boton enviar; confirmar: %d", AXUIElementPerformAction(field, kAXConfirmAction as CFString).rawValue)
            }
        }
    }

    private static func check() {
        guard let center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return }
        let app = AXUIElementCreateApplication(center.processIdentifier)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        let list = windows as? [AXUIElement] ?? []
        tryReply(in: list)
        var lines: [String] = []
        for window in list { dump(window, depth: 0, into: &lines) }
        let signature = lines.joined(separator: "\n")
        guard signature != lastSignature else { return }
        lastSignature = signature
        NSLog("VISORBANNER ventanas=%d\n%@", list.count, signature)
    }

    private static func dump(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth < 14, lines.count < 200 else { return }
        func attr(_ name: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value as? String
        }
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        let names = (actions as? [String] ?? []).map { $0.replacingOccurrences(of: "\n", with: " ") }
        let texts = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute, kAXSubroleAttribute]
            .compactMap { key in attr(key).map { "\(key.replacingOccurrences(of: "AX", with: ""))=\(key == kAXSubroleAttribute || key == kAXIdentifierAttribute ? $0 : NotificationFeed.mask($0))" } }
        lines.append(String(repeating: "  ", count: depth) + (attr(kAXRoleAttribute) ?? "?") + " " + texts.joined(separator: " ") + (names.isEmpty ? "" : " acciones=\(names)"))
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        for child in children as? [AXUIElement] ?? [] { dump(child, depth: depth + 1, into: &lines) }
    }
}
#endif
