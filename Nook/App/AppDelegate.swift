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
    private var defaultsObserver: NSObjectProtocol?
    private var services: ServiceProvider?
    private var screenshots: ScreenshotLibrary?
    private var agents: AgentMonitor?
    private var hud: SystemHUD?
    private var calendar: CalendarService?
    private var focus: FocusTimer?
    private var mail: MailService?
    private var basket: BasketController?
    private var dictation: Dictation?
    private var ring: ActionRingController?
    private var ringHotKey: HotKey?
    private var appVolume: AppVolume?

    func applicationWillTerminate(_ notification: Notification) {
        // Quita los taps: cada app vuelve a sonar a su volumen normal.
        appVolume?.resetAll()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsKey.registerDefaults()
        // Los tests usan la app como host: sin panel ni monitores.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

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
        let appVolume = AppVolume()
        mail.onNew = { [weak hud] message in
            guard UserDefaults.standard.bool(forKey: SettingsKey.hudMail) else { return }
            hud?.show(.mail(sender: message.sender), for: 3)
        }
        hud.focus = focus
        hud.calendar = calendar
        let notch = NotchController(store: store, container: container, screenshots: screenshots, agents: agents, hud: hud, calendar: calendar, focus: focus, mail: mail, appVolume: appVolume)
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
        monitor.onAccessChange = { [weak notch] access in notch?.model.clipboardAccess = access }

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
        self.appVolume = appVolume
        ring.actions = makeRingActions()

        notch.start()
        monitor.start()
        hud.start()
        calendar.start()
        mail.start()
        basket.start()
        store.trimHistory()
        store.recognizeMissingText()

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
        notch.applyDebugLaunchArguments()
        #endif
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
        guard let calendar else { return }
        notch?.model.close()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(calendar: calendar)))
            window.title = String(localized: "Ajustes de Nook")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
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
