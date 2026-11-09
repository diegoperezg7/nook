import AppKit
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
    private var nowPlaying: NowPlaying?
    private var agents: AgentMonitor?

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
        let nowPlaying = NowPlaying()
        let agents = AgentMonitor()
        let notch = NotchController(store: store, container: container, screenshots: screenshots, nowPlaying: nowPlaying, agents: agents)
        let monitor = ClipboardMonitor(store: store)

        notch.model.onOpenSettings = { [weak self] in self?.showSettings() }
        monitor.onAccessChange = { [weak notch] access in notch?.model.clipboardAccess = access }

        self.container = container
        self.store = store
        self.notch = notch
        self.monitor = monitor
        self.screenshots = screenshots
        self.nowPlaying = nowPlaying
        self.agents = agents

        notch.start()
        monitor.start()
        nowPlaying.start()
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
    }

    private func showSettings() {
        notch?.model.close()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
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
