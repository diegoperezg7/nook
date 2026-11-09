import AppKit
import AudioToolbox
import CoreAudio
import IOKit.ps
import Observation

/// Avisos breves que salen del notch cerrado: volumen, dispositivo de audio
/// conectado, bateria y descargas. Cada uno se va solo a los pocos segundos.
@Observable
@MainActor
final class SystemHUD {
    enum Kind: Equatable {
        case volume(level: Double, muted: Bool)
        case audioDevice(name: String, icon: String)
        case battery(level: Int, charging: Bool)
        case download(name: String, done: Bool)
    }

    private(set) var current: Kind?
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
                if self.defaults.bool(forKey: SettingsKey.hudDevices) { self.show(.audioDevice(name: name, icon: icon), for: 2.5) }
            }
        }
        battery = BatteryMonitor { [weak self] level, charging in
            guard let self, self.defaults.bool(forKey: SettingsKey.hudBattery) else { return }
            self.show(.battery(level: level, charging: charging), for: 2.5)
        }
        downloads = DownloadsMonitor { [weak self] name, done in
            guard let self, self.defaults.bool(forKey: SettingsKey.hudDownloads) else { return }
            // Mientras descarga se queda; al terminar, el check dura un poco.
            self.show(.download(name: name, done: done), for: done ? 2.5 : nil)
        }
    }

    /// Muestra un aviso; `duration` nil lo deja hasta el siguiente.
    func show(_ kind: Kind, for duration: TimeInterval? = 1.6) {
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
