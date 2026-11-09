import AppKit
import AudioToolbox
import CoreAudio
import CoreMediaIO
import IOKit.ps
import Network
import Observation

/// Lo que sale del notch cerrado:
/// - Avisos breves (`current`): volumen, dispositivo de audio, bateria, descargas,
///   Bloq Mayus, red y fin del temporizador. Se van solos a los pocos segundos.
/// - Actividades que duran (`ambient`): reunion a punto de empezar, temporizador,
///   microfono o camara en uso y "mantener despierto". Se ven mientras duran,
///   salvo cuando hay un aviso breve encima.
@Observable
@MainActor
final class SystemHUD {
    enum Kind: Equatable {
        case volume(level: Double, muted: Bool)
        case audioDevice(name: String, icon: String)
        case battery(level: Int, charging: Bool)
        case download(name: String, done: Bool)
        case capsLock(on: Bool)
        case network(online: Bool, vpn: Bool)
        case timerDone
        case mail(sender: String)
        /// Resultado de una herramienta: "Texto copiado", "En la bandeja"...
        case notice(icon: String, text: String)
        case dictation(text: String)
        /// Bateria de AirPods, teclado o raton (al conectar o cuando queda poca).
        case accessory(name: String, icon: String, level: Int, low: Bool)
        case notification(bundleID: String, title: String, body: String)
        // Actividades que duran.
        case meeting(title: String, start: Date)
        case timer(end: Date, total: TimeInterval)
        case mediaInUse(mic: Bool, camera: Bool)
        case stayAwake(until: Date?)
        case alarm(time: Date)
    }

    private(set) var current: Kind?
    private(set) var micInUse = false
    private(set) var cameraInUse = false
    /// Reloj para las actividades que dependen de la hora (la reunion).
    private(set) var now = Date.now

    @ObservationIgnored var focus: FocusTimer?
    @ObservationIgnored var calendar: CalendarService?
    @ObservationIgnored var dictation: Dictation?
    @ObservationIgnored private var capsLockOn = false
    @ObservationIgnored private var poller: Timer?
    @ObservationIgnored private var path: NWPathMonitor?
    @ObservationIgnored private var lastPath: (online: Bool, vpn: Bool)?

    /// La actividad que dura con mas prioridad: reunion > temporizador >
    /// microfono o camara > mantener despierto.
    var ambient: Kind? {
        if let dictation, dictation.isListening { return .dictation(text: dictation.transcript) }
        if let ringing = focus?.ringing { return .alarm(time: ringing) }
        if defaults.bool(forKey: SettingsKey.hudMeetings), let meeting = calendar?.imminentMeeting(at: now) {
            return .meeting(title: meeting.title, start: meeting.start)
        }
        if let focus, let end = focus.end { return .timer(end: end, total: focus.total) }
        if defaults.bool(forKey: SettingsKey.hudMediaInUse), micInUse || cameraInUse {
            return .mediaInUse(mic: micInUse, camera: cameraInUse)
        }
        if let focus, focus.isAwake { return .stayAwake(until: focus.awakeUntil) }
        return nil
    }
    @ObservationIgnored private var hideWork: DispatchWorkItem?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var volume: VolumeMonitor?
    @ObservationIgnored private var battery: BatteryMonitor?
    @ObservationIgnored private var downloads: DownloadsMonitor?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start() {
        volume = VolumeMonitor { [weak self] event in
            guard let self else { return }
            switch event {
            case let .level(level, muted):
                if self.defaults.bool(forKey: SettingsKey.hudVolume) { self.show(.volume(level: level, muted: muted)) }
            case let .device(name, icon):
                if self.defaults.bool(forKey: SettingsKey.hudDevices) {
                    self.show(.audioDevice(name: name, icon: icon), for: 3)
                    // Despues del nombre, su bateria (si es Bluetooth y la da).
                    self.showBattery(of: name, after: 3)
                }
            }
        }
        battery = BatteryMonitor { [weak self] level, charging in
            guard let self, self.defaults.bool(forKey: SettingsKey.hudBattery) else { return }
            self.show(.battery(level: level, charging: charging), for: 2.5)
        }
        downloads = DownloadsMonitor { [weak self] name, done in
            guard let self, self.defaults.bool(forKey: SettingsKey.hudDownloads) else { return }
            // Mientras descarga se queda (como mucho un minuto, por si se cancela);
            // al terminar, el check dura un poco.
            self.show(.download(name: name, done: done), for: done ? 2.5 : 60)
        }
        focus?.onFinish = { [weak self] in self?.show(.timerDone, for: 4) }
        capsLockOn = Self.capsLockState()
        startPolling()
        startNetwork()
        startAccessoryChecks()
    }

    // MARK: - Bateria de accesorios

    @ObservationIgnored private var accessoryTimer: Timer?
    /// Accesorios ya avisados por poca bateria (hasta que vuelvan a cargarse).
    @ObservationIgnored private var warnedLow: Set<String> = []

    private func showBattery(of name: String, after delay: TimeInterval) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            let devices = await AccessoryBattery.readAll()
            guard let device = devices.first(where: { $0.name == name }), let level = device.lowest,
                  defaults.bool(forKey: SettingsKey.hudDevices) else { return }
            show(.accessory(name: device.name, icon: device.icon, level: level, low: level <= 20), for: 3)
        }
    }

    /// Cada 5 minutos: aviso de poca bateria (20 % o menos), una vez por carga.
    private func startAccessoryChecks() {
        accessoryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.defaults.bool(forKey: SettingsKey.hudDevices) else { return }
                Task {
                    for device in await AccessoryBattery.readAll() {
                        guard let level = device.lowest else { continue }
                        if level > 30 { self.warnedLow.remove(device.name) }
                        if level <= 20, !self.warnedLow.contains(device.name) {
                            self.warnedLow.insert(device.name)
                            self.show(.accessory(name: device.name, icon: device.icon, level: level, low: true), for: 4)
                            break
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sondeo (Bloq Mayus, microfono, camara, reloj)

    /// Un sondeo barato cada 0,3 s: el estado de Bloq Mayus se lee sin permisos
    /// (CGEventSource) y el uso de microfono y camara, con CoreAudio y CoreMediaIO.
    private func startPolling() {
        var ticks = 0
        poller = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                ticks += 1
                let caps = Self.capsLockState()
                if caps != self.capsLockOn {
                    self.capsLockOn = caps
                    if self.defaults.bool(forKey: SettingsKey.hudCapsLock) { self.show(.capsLock(on: caps), for: 1) }
                }
                // Microfono, camara y reloj: cada ~1,5 s basta.
                guard ticks % 5 == 0 else { return }
                let mic = MediaUsage.microphoneInUse()
                let camera = MediaUsage.cameraInUse()
                if mic != self.micInUse { self.micInUse = mic }
                if camera != self.cameraInUse { self.cameraInUse = camera }
                if ticks % 50 == 0 { self.now = .now }
            }
        }
    }

    private static func capsLockState() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    // MARK: - Red

    private func startNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            // Una VPN aparece como interfaz "utun"/"ipsec"/"ppp".
            let vpn = path.availableInterfaces.contains { ["utun", "ipsec", "ppp"].contains(where: $0.name.hasPrefix) }
            DispatchQueue.main.async { self?.networkChanged(online: online, vpn: vpn) }
        }
        monitor.start(queue: DispatchQueue(label: "Nook.network"))
        path = monitor
    }

    private func networkChanged(online: Bool, vpn: Bool) {
        defer { lastPath = (online, vpn) }
        // El primer valor es el estado al arrancar: no se avisa.
        guard let last = lastPath, last.online != online || last.vpn != vpn,
              defaults.bool(forKey: SettingsKey.hudNetwork) else { return }
        show(.network(online: online, vpn: vpn), for: 2.5)
    }

    /// Muestra un aviso; `duration` nil lo deja hasta el siguiente.
    func show(_ kind: Kind, for duration: TimeInterval? = 1.5) {
        current = kind
        hideWork?.cancel()
        guard let duration else { return }
        let work = DispatchWorkItem { [weak self] in self?.current = nil }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

// MARK: - Volumen y dispositivos

/// Volumen de la salida por defecto y cambios de dispositivo (CoreAudio).
@MainActor
final class VolumeMonitor {
    enum Event {
        case level(Double, muted: Bool)
        case device(name: String, icon: String)
    }

    private let onEvent: (Event) -> Void
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var listener: AudioObjectPropertyListenerBlock?
    private var lastLevel: Double?
    private var lastMuted: Bool?

    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static let defaultOutput = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
    )
    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
    )
    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
    )

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
        }
        listener = block
        var output = Self.defaultOutput
        AudioObjectAddPropertyListenerBlock(Self.system, &output, .main, block)
        attach(to: Self.currentDevice(), announce: false)
    }

    private func changed() {
        let current = Self.currentDevice()
        if current != device {
            attach(to: current, announce: true)
            return
        }
        let level = Self.read(Float32.self, device, Self.volumeAddress).map(Double.init)
        let muted = Self.read(UInt32.self, device, Self.muteAddress).map { $0 != 0 } ?? false
        guard let level, level != lastLevel || muted != lastMuted else { return }
        lastLevel = level
        lastMuted = muted
        onEvent(.level(level, muted: muted))
    }

    private func attach(to newDevice: AudioObjectID, announce: Bool) {
        guard let listener else { return }
        var volume = Self.volumeAddress
        var mute = Self.muteAddress
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &volume, .main, listener)
            AudioObjectRemovePropertyListenerBlock(device, &mute, .main, listener)
        }
        device = newDevice
        lastLevel = Self.read(Float32.self, device, Self.volumeAddress).map(Double.init)
        lastMuted = Self.read(UInt32.self, device, Self.muteAddress).map { $0 != 0 }
        AudioObjectAddPropertyListenerBlock(device, &volume, .main, listener)
        AudioObjectAddPropertyListenerBlock(device, &mute, .main, listener)
        // Solo se avisa de los Bluetooth (AirPods, altavoces): los internos no aportan.
        guard announce, let name = Self.name(of: newDevice), Self.isBluetooth(newDevice) else { return }
        let icon = name.localizedCaseInsensitiveContains("AirPods") ? "airpods" : "headphones"
        onEvent(.device(name: name, icon: icon))
    }

    private static func currentDevice() -> AudioObjectID {
        read(AudioObjectID.self, system, defaultOutput) ?? AudioObjectID(kAudioObjectUnknown)
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        let type = read(UInt32.self, device, address)
        return type == kAudioDeviceTransportTypeBluetooth || type == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func read<T>(_ type: T.Type, _ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }
}

// MARK: - Bateria

/// Avisa al enchufar o desenchufar el cargador y al bajar del 20 % y del 10 %.
@MainActor
final class BatteryMonitor {
    private let onChange: (Int, Bool) -> Void
    private var source: CFRunLoopSource?
    private var lastCharging: Bool?
    private var lastLevel: Int?

    init(onChange: @escaping (Int, Bool) -> Void) {
        self.onChange = onChange
        guard let state = Self.state() else { return }
        lastCharging = state.charging
        lastLevel = state.level
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.changed() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func changed() {
        guard let state = Self.state() else { return }
        defer { lastCharging = state.charging; lastLevel = state.level }
        if state.charging != lastCharging {
            onChange(state.level, state.charging)
        } else if !state.charging, let lastLevel, [20, 10].contains(where: { lastLevel > $0 && state.level <= $0 }) {
            onChange(state.level, false)
        }
    }

    /// Nil en Macs sin bateria.
    private static func state() -> (level: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (current * 100 / max, onAC)
        }
        return nil
    }
}

// MARK: - Descargas

/// Vigila la carpeta Descargas: un archivo a medias (.download, .crdownload, .part)
/// es una descarga en curso; uno nuevo y completo, una descarga terminada.
@MainActor
final class DownloadsMonitor {
    private let onChange: (String, Bool) -> Void
    private var watcher: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private let folder: URL
    private static let partial = ["download", "crdownload", "part", "partial"]

    init(onChange: @escaping (String, Bool) -> Void) {
        self.onChange = onChange
        folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
        known = names()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func names() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { !$0.hasPrefix(".") } ?? [])
    }

    private func changed() {
        let now = names()
        let added = now.subtracting(known)
        known = now
        for name in added {
            let ext = (name as NSString).pathExtension.lowercased()
            if Self.partial.contains(ext) {
                onChange(Self.finalName(name), false)
            } else {
                onChange(name, true)
            }
        }
    }

    /// "informe.pdf.crdownload" -> "informe.pdf"; los de Chrome sin nombre aun se quedan igual.
    static func finalName(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }
}

// MARK: - Microfono y camara en uso

/// Si alguna app esta usando el microfono o la camara (como los puntos naranja y
/// verde de macOS). Solo se consulta el estado del dispositivo: no se graba nada.
enum MediaUsage {
    static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }
        address.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        return devices.contains { device in
            var running: UInt32 = 0
            var got: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == noErr && running != 0
        }
    }
}
