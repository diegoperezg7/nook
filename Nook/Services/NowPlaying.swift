import AppKit
import Observation

/// Lo que suena en Musica o en Spotify. Las dos apps avisan de cada cambio con una
/// notificacion distribuida; la caratula, la posicion y los controles van por
/// AppleScript (la primera vez macOS pide permiso para controlar la app).
///
/// Nunca abre esas apps: solo habla con ellas si ya estan abiertas.
@Observable
@MainActor
final class NowPlaying {
    enum Player: String, CaseIterable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var scriptName: String { self == .music ? "Music" : "Spotify" }
        var notification: String {
            self == .music ? "com.apple.Music.playerInfo" : "com.spotify.client.PlaybackStateChanged"
        }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty }
        var icon: NSImage? {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue).map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        /// Segundos; 0 si no se sabe (radio, streaming en directo).
        var duration: TimeInterval
    }

    private(set) var player: Player?
    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var artwork: NSImage?
    /// Posicion conocida y cuando se midio: la actual se calcula sin preguntar a la app.
    private(set) var position: TimeInterval = 0
    private(set) var positionDate = Date.now

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var artworkKey: String?

    func start() {
        let center = DistributedNotificationCenter.default()
        for player in Player.allCases {
            observers.append(center.addObserver(forName: Notification.Name(player.notification), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.handle(info, from: player) }
            })
        }
        // Al cerrar la app que sonaba desaparece el reproductor.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let player = self.player, bundle == player.rawValue else { return }
                self.clear()
            }
        })
        #if DEBUG
        // `-VisorDemoMusic YES`: una cancion de ejemplo sonando (capturas).
        if UserDefaults.standard.bool(forKey: "VisorDemoMusic") {
            player = .spotify
            track = Track(title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming", duration: 243)
            isPlaying = true
            return
        }
        #endif
        // Lo que ya sonaba antes de abrir Visor.
        for player in Player.allCases where player.isRunning {
            refresh(player)
            if isPlaying { break }
        }
    }

    /// Posicion estimada ahora mismo.
    func currentPosition(at date: Date = .now) -> TimeInterval {
        guard isPlaying else { return position }
        let value = position + date.timeIntervalSince(positionDate)
        guard let duration = track?.duration, duration > 0 else { return value }
        return min(value, duration)
    }

    // MARK: - Controles

    func playPause() {
        send("playpause")
        isPlaying.toggle()
        position = currentPosition()
        positionDate = .now
    }

    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        run("tell application \"\(player.scriptName)\" to set player position to \(Int(seconds))", player: player)
        position = seconds
        positionDate = .now
    }

    func openPlayer() {
        guard let player, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func send(_ command: String) {
        guard let player else { return }
        run("tell application \"\(player.scriptName)\" to \(command)", player: player)
    }

    // MARK: - Estado

    private func handle(_ info: [AnyHashable: Any], from player: Player) {
        let state = info["Player State"] as? String
        if state == "Stopped" {
            if self.player == player { clear() }
            return
        }
        // Otra app en pausa no le quita el sitio a la que suena.
        if let current = self.player, current != player, isPlaying, state != "Playing" { return }

        let title = info["Name"] as? String ?? track?.title ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        let millis = (info["Total Time"] as? NSNumber) ?? (info["Duration"] as? NSNumber)
        let newTrack = Track(title: title, artist: artist, album: album, duration: (millis?.doubleValue ?? 0) / 1000)
        // Misma cancion: se sigue desde donde iba (al pausar no se vuelve a 0:00).
        let estimated = self.player == player && track == newTrack ? currentPosition() : 0

        self.player = player
        isPlaying = state == "Playing"
        track = newTrack
        position = (info["Playback Position"] as? NSNumber)?.doubleValue ?? estimated
        positionDate = .now
        if info["Playback Position"] == nil { readPosition() }
        loadArtwork()
    }

    /// Pregunta el estado a una app abierta (al arrancar Visor).
    private func refresh(_ player: Player) {
        let script = """
        tell application "\(player.scriptName)"
            if player state is stopped then return ""
            set t to current track
            set s to character id 31
            return (player state as string) & s & (name of t) & s & (artist of t) & s & (album of t) & s & (duration of t) & s & (player position)
        end tell
        """
        guard let result = run(script, player: player)?.stringValue, !result.isEmpty else { return }
        let parts = result.components(separatedBy: "\u{1F}")
        guard parts.count == 6 else { return }
        self.player = player
        isPlaying = parts[0] == "playing"
        // Musica da la duracion en segundos; Spotify dice segundos en su diccionario
        // pero segun la version devuelve milisegundos.
        let duration = Self.seconds(Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0)
        track = Track(title: parts[1], artist: parts[2], album: parts[3], duration: duration)
        position = Double(parts[5].replacingOccurrences(of: ",", with: ".")) ?? 0
        positionDate = .now
        loadArtwork()
    }

    /// Una cancion de mas de 10 h no existe: un valor asi viene en milisegundos.
    nonisolated static func seconds(_ value: Double) -> TimeInterval {
        value > 36_000 ? value / 1000 : value
    }

    private func readPosition() {
        guard let player,
              let value = run("tell application \"\(player.scriptName)\" to get player position", player: player)?.doubleValue
        else { return }
        position = value
        positionDate = .now
    }

    private func loadArtwork() {
        guard let player, let track else { return }
        let key = "\(player.rawValue)|\(track.title)|\(track.album)"
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        switch player {
        case .music:
            let data = run("tell application \"Music\" to get raw data of artwork 1 of current track", player: player)?.data
            artwork = data.flatMap(NSImage.init(data:))
        case .spotify:
            guard let link = run("tell application \"Spotify\" to get artwork url of current track", player: player)?.stringValue,
                  let url = URL(string: link) else { return }
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = NSImage(data: data), self.artworkKey == key else { return }
                self.artwork = image
            }
        }
    }

    private func clear() {
        player = nil
        track = nil
        isPlaying = false
        artwork = nil
        artworkKey = nil
    }

    @discardableResult
    private func run(_ source: String, player: Player) -> NSAppleEventDescriptor? {
        guard player.isRunning else { return nil }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Visor: AppleScript \(player.scriptName): \(error)") }
        return result
    }
}
