import AppKit
import CoreAudio
import Observation

/// Volumen por app (macOS 14.2+): para cada app con volumen distinto del 100 % se
/// crea un "tap" de Core Audio que silencia su sonido original y lo vuelve a sacar
/// por los altavoces con la ganancia elegida. Al volver al 100 % se quita el tap y
/// la app suena como siempre. La primera vez macOS pide permiso para captar audio.
@Observable
@MainActor
final class AppVolume {
    struct App: Identifiable, Equatable {
        let id: String
        let name: String
        let pid: pid_t
        let process: AudioObjectID
        var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
    }

    /// Apps que estan sonando ahora (o que tienen un volumen propio).
    private(set) var apps: [App] = []
    /// Volumen por bundle ID (0...1). Lo que no esta, al 100 %.
    private(set) var volumes: [String: Float] = [:]
    private(set) var failed = false

    @ObservationIgnored private var taps: [String: ProcessTap] = [:]

    func refresh() {
        let processes = Self.processes()
        apps = processes
            .filter { $0.isRunningOutput || volumes[$0.bundleID] != nil }
            .filter { $0.pid != ProcessInfo.processInfo.processIdentifier }
            .compactMap { process -> App? in
                guard let running = NSRunningApplication(processIdentifier: process.pid) ?? Self.appOwning(process.bundleID) else { return nil }
                return App(id: process.bundleID, name: running.localizedName ?? process.bundleID, pid: running.processIdentifier, process: process.id)
            }
            .reduce(into: [App]()) { list, app in if !list.contains(where: { $0.id == app.id }) { list.append(app) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func volume(of app: App) -> Float { volumes[app.id] ?? 1 }

    func setVolume(_ value: Float, for app: App) {
        let value = min(max(value, 0), 1)
        if value >= 0.995 {
            volumes[app.id] = nil
            taps[app.id]?.stop()
            taps[app.id] = nil
            return
        }
        volumes[app.id] = value
        if let tap = taps[app.id] {
            tap.gain = value
        } else {
            do {
                let tap = try ProcessTap(process: app.process, gain: value)
                taps[app.id] = tap
                failed = false
            } catch {
                volumes[app.id] = nil
                failed = true
            }
        }
    }

    /// Deja todo como estaba (al salir de la app).
    func resetAll() {
        taps.values.forEach { $0.stop() }
        taps = [:]
        volumes = [:]
    }

    // MARK: - Procesos de audio

    private struct AudioProcess {
        let id: AudioObjectID
        let pid: pid_t
        let bundleID: String
        let isRunningOutput: Bool
    }

    private static func processes() -> [AudioProcess] {
        let ids: [AudioObjectID] = CoreAudioProperty.array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        return ids.compactMap { id in
            guard let pid: pid_t = CoreAudioProperty.value(id, kAudioProcessPropertyPID),
                  let bundle = CoreAudioProperty.string(id, kAudioProcessPropertyBundleID), !bundle.isEmpty else { return nil }
            let running: UInt32 = CoreAudioProperty.value(id, kAudioProcessPropertyIsRunningOutput) ?? 0
            return AudioProcess(id: id, pid: pid, bundleID: bundle, isRunningOutput: running != 0)
        }
    }

    /// Procesos auxiliares (p. ej. "com.google.Chrome.helper") se agrupan en su app.
    private static func appOwning(_ bundleID: String) -> NSRunningApplication? {
        let parts = bundleID.split(separator: ".")
        for length in stride(from: parts.count - 1, through: 2, by: -1) {
            let candidate = parts.prefix(length).joined(separator: ".")
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate).first { return app }
        }
        return nil
    }
}

/// Tap de un proceso + dispositivo agregado privado que lo reproduce con ganancia.
final class ProcessTap {
    enum Failure: Error { case tap(OSStatus), aggregate(OSStatus), proc(OSStatus) }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let gainBox = GainBox()
    private let queue = DispatchQueue(label: "com.diegoperez.nook.tap", qos: .userInteractive)

    var gain: Float {
        get { gainBox.value }
        set { gainBox.value = newValue }
    }

    init(process: AudioObjectID, gain: Float) throws {
        gainBox.value = gain
        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw Failure.tap(status) }

        let outputID: AudioObjectID = CoreAudioProperty.value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        guard let outputUID = CoreAudioProperty.string(outputID, kAudioDevicePropertyDeviceUID) else {
            stop(); throw Failure.aggregate(-1)
        }
        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Nook",
            kAudioAggregateDeviceUIDKey: "com.diegoperez.nook.tap.\(description.uuid.uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregateID)
        guard status == noErr else { stop(); throw Failure.aggregate(status) }

        let box = gainBox
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, output, _ in
            let gain = box.value
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputs = UnsafeMutableAudioBufferListPointer(output)
            for index in 0..<outputs.count {
                guard let out = outputs[index].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let outCount = Int(outputs[index].mDataByteSize) / MemoryLayout<Float>.size
                guard index < inputs.count, let source = inputs[index].mData?.assumingMemoryBound(to: Float.self) else {
                    out.update(repeating: 0, count: outCount)
                    continue
                }
                let count = min(outCount, Int(inputs[index].mDataByteSize) / MemoryLayout<Float>.size)
                for sample in 0..<count { out[sample] = source[sample] * gain }
                if count < outCount { (out + count).update(repeating: 0, count: outCount - count) }
            }
        }
        guard status == noErr, let procID else { stop(); throw Failure.proc(status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { stop(); throw Failure.proc(status) }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit { stop() }
}

/// Ganancia compartida con el hilo de audio (un Float se lee y escribe de una vez).
private final class GainBox: @unchecked Sendable {
    var value: Float = 1
}

/// Lectura de propiedades de Core Audio.
enum CoreAudioProperty {
    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    static func array<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [T] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() else { return nil }
        return string as String
    }
}
