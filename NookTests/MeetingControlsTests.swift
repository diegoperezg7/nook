import XCTest
@testable import Nook

/// Controles de llamada: que etiquetas cuentan como silenciar, camara o colgar, y
/// que procesos que graban son una llamada.
final class MeetingControlsTests: XCTestCase {
    func testMicLabels() {
        let mic = MeetingControls.Action.mic
        XCTAssertTrue(mic.matches("Mute (⌘+Shift+M)")) // Teams
        XCTAssertTrue(mic.matches("Unmute"))
        XCTAssertTrue(mic.matches("Turn off microphone (⌘ + d)")) // Meet
        XCTAssertTrue(mic.matches("Desactivar micrófono (⌘ + d)"))
        XCTAssertTrue(mic.matches("Silenciar"))
        XCTAssertFalse(mic.matches("Muted"))
        XCTAssertFalse(mic.matches("Microphone"), "el selector de dispositivo no es silenciar")
        XCTAssertFalse(mic.matches(""))
    }

    /// El estado se lee de lo que el boton invita a hacer: "Unmute" es que esta
    /// silenciado. Una etiqueta que no lo dice no da estado (no se adivina).
    func testStateFromLabels() {
        let mic = MeetingControls.Action.mic
        XCTAssertEqual(mic.isOff(label: "Unmute mic (⌘+Shift+M)"), true) // Teams silenciado
        XCTAssertEqual(mic.isOff(label: "Mute mic (⌘+Shift+M)"), false)
        XCTAssertEqual(mic.isOff(label: "Turn on microphone (⌘ + d)"), true) // Meet
        XCTAssertEqual(mic.isOff(label: "Turn off microphone (⌘ + d)"), false)
        XCTAssertEqual(mic.isOff(label: "Activar micrófono"), true)
        XCTAssertEqual(mic.isOff(label: "Desactivar el micrófono"), false)
        XCTAssertEqual(mic.isOff(label: "Reactivar micrófono"), true)
        XCTAssertEqual(mic.isOff(label: "Quitar silencio"), true)
        XCTAssertEqual(mic.isOff(label: "Silenciar"), false)
        XCTAssertEqual(mic.isOff(label: "Unmute Audio"), true) // Zoom
        XCTAssertNil(mic.isOff(label: "Micrófono"), "FaceTime no dice el estado")
        XCTAssertNil(mic.isOff(label: "Muted"))

        let camera = MeetingControls.Action.camera
        XCTAssertEqual(camera.isOff(label: "Turn camera on (⌘+Shift+O)"), true) // Teams
        XCTAssertEqual(camera.isOff(label: "Turn camera off (⌘+Shift+O)"), false)
        XCTAssertEqual(camera.isOff(label: "Start Video"), true) // Zoom
        XCTAssertEqual(camera.isOff(label: "Stop Video"), false)
        XCTAssertEqual(camera.isOff(label: "Activar cámara"), true)
        XCTAssertEqual(camera.isOff(label: "Apagar la cámara"), false)
        XCTAssertNil(camera.isOff(label: "Cámara"))
        XCTAssertNil(MeetingControls.Action.leave.isOff(label: "Leave"))
    }

    func testCameraLabels() {
        let camera = MeetingControls.Action.camera
        XCTAssertTrue(camera.matches("Turn off camera (⌘ + e)"))
        XCTAssertTrue(camera.matches("Desactivar cámara"))
        XCTAssertTrue(camera.matches("Stop Video"))
        XCTAssertTrue(camera.matches("Turn On Camera")) // Discord
        XCTAssertFalse(camera.matches("Camera settings"))
    }

    func testLeaveLabelsNeverQuitTheApp() {
        let leave = MeetingControls.Action.leave
        XCTAssertTrue(leave.matches("Leave call"))
        XCTAssertTrue(leave.matches("Salir"))
        XCTAssertTrue(leave.matches("Colgar"))
        XCTAssertTrue(leave.matches("Disconnect")) // Discord
        XCTAssertTrue(leave.matches("End Call"))
        XCTAssertFalse(leave.matches("Salir de FaceTime"))
        XCTAssertFalse(leave.matches("Quit FaceTime"))
        XCTAssertFalse(leave.matches("Leaves"))
    }

    /// FaceTime: "Micrófono", "Cámara" y "Finalizar" no son etiquetas de accion; valen
    /// sus identificadores.
    func testFaceTimeIdentifiers() {
        XCTAssertTrue(MeetingControls.Action.mic.identifiers.contains("toggleMicMenuButton"))
        XCTAssertTrue(MeetingControls.Action.camera.identifiers.contains("toggleVideoButton"))
        XCTAssertTrue(MeetingControls.Action.leave.identifiers.contains("leaveButton"))
        XCTAssertFalse(MeetingControls.Action.leave.matches("Finalizar"))
    }

    /// Un navegador que graba solo es llamada en una web de reuniones (no al dictar).
    func testBrowserNeedsAMeetingSite() {
        XCTAssertEqual(MeetingControls.meetingSite(in: ["Meet - abc-defg-hij - Google Chrome"]), "Meet")
        XCTAssertEqual(MeetingControls.meetingSite(in: ["Inbox", "Reunión | Microsoft Teams"]), "Teams")
        XCTAssertNil(MeetingControls.meetingSite(in: ["Claude - Google Chrome", "ChatGPT"]))
        XCTAssertNil(MeetingControls.meetingSite(in: []))
    }

    func testSystemAndOwnProcessesAreNotCalls() {
        XCTAssertTrue(MeetingControls.isCallCandidate("com.microsoft.teams2"))
        XCTAssertTrue(MeetingControls.isCallCandidate("com.hnc.Discord"))
        XCTAssertTrue(MeetingControls.isCallCandidate("com.apple.FaceTime"))
        XCTAssertTrue(MeetingControls.isCallCandidate("com.apple.Safari"))
        XCTAssertFalse(MeetingControls.isCallCandidate("com.apple.VoiceMemos"))
        XCTAssertFalse(MeetingControls.isCallCandidate("com.apple.SpeechRecognitionCore.speechrecognitiond"))
        XCTAssertFalse(MeetingControls.isCallCandidate("com.diegoperez.visor"))
        XCTAssertFalse(MeetingControls.isCallCandidate("com.diegoperez.visor.debug"))
    }
}
