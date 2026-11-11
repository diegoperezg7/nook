import AppKit
import ApplicationServices

/// Notificaciones en el notch leyendo los avisos de macOS por Accesibilidad. En
/// macOS 27 ya no existe la base de datos de notificaciones que lee `NotificationFeed`,
/// y el aviso trae ademas sus acciones: "Responder" (WhatsApp, Mensajes...) permite
/// contestar desde el notch con el campo de respuesta del propio aviso, asi la
/// respuesta va siempre al chat correcto. Solo mientras el aviso sigue en pantalla.
@MainActor
final class NotificationBanners {
    struct Banner: Equatable {
        /// UUID del aviso en el Centro de notificaciones.
        let id: String
        let appName: String
        var bundleID: String?
        let title: String
        let subtitle: String
        let body: String
        let canReply: Bool

        /// macOS reutiliza el mismo aviso para el siguiente mensaje de la app: cuenta
        /// como nuevo si cambia su contenido.
        var key: String { "\(id)|\(title)|\(subtitle)|\(body)" }
    }

    var onBanner: ((Banner) -> Void)?
    private var timer: Timer?
    private var seen: [String] = []
    private var primed = false

    static let centerBundleID = "com.apple.notificationcenterui"
    /// Avisos nuevos (estilo temporal y permanente); la lista del Centro de
    /// notificaciones usa otros roles y no cuenta.
    static let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        primed = false
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        guard AXAccess.isTrusted else { return }
        let banners = Self.current()
        // La primera vuelta solo apunta los que ya estaban: no se repiten.
        defer { primed = true }
        for banner in banners where !seen.contains(banner.key) {
            seen.append(banner.key)
            #if DEBUG
            NSLog("VISORBANNERS nuevo de %@ primed=%d responder=%d", banner.appName, primed ? 1 : 0, banner.canReply ? 1 : 0)
            #endif
            if primed { onBanner?(banner) }
        }
        if seen.count > 200 { seen.removeFirst(seen.count - 200) }
    }

    // MARK: - Lectura

    /// Avisos en pantalla ahora mismo.
    static func current() -> [Banner] {
        groups().compactMap { banner(from: $0) }
    }

    private static func groups() -> [AXUIElement] {
        guard let center = NSRunningApplication.runningApplications(withBundleIdentifier: centerBundleID).first else { return [] }
        let app = AXUIElementCreateApplication(center.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var found: [AXUIElement] = []
        var queue = (elements(app, kAXWindowsAttribute)).map { ($0, 0) }
        while !queue.isEmpty, found.count < 10 {
            let (element, depth) = queue.removeFirst()
            if let subrole = string(element, kAXSubroleAttribute), bannerSubroles.contains(subrole) {
                found.append(element)
                continue
            }
            guard depth < 8 else { continue }
            queue += elements(element, kAXChildrenAttribute).map { ($0, depth + 1) }
        }
        return found
    }

    private static func banner(from group: AXUIElement) -> Banner? {
        guard let id = string(group, kAXIdentifierAttribute) else { return nil }
        var texts: [String: String] = [:]
        for child in elements(group, kAXChildrenAttribute) {
            if let key = string(child, kAXIdentifierAttribute), let value = string(child, kAXValueAttribute) { texts[key] = value }
        }
        var banner = parse(id: id, description: string(group, kAXDescriptionAttribute) ?? "", texts: texts, actions: actionNames(group))
        if let name = banner?.appName {
            banner?.bundleID = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.bundleIdentifier
        }
        return banner
    }

    /// Datos de un aviso: la descripcion empieza por el nombre de la app ("WhatsApp,
    /// Ana, Hola"); los textos llevan identificador `title`, `subtitle` y `body`.
    nonisolated static func parse(id: String, description: String, texts: [String: String], actions: [String]) -> Banner? {
        let app = clean(description.components(separatedBy: ",").first ?? "")
        let title = clean(texts["title"] ?? ""), subtitle = clean(texts["subtitle"] ?? ""), body = clean(texts["body"] ?? "")
        guard !app.isEmpty, !(title.isEmpty && body.isEmpty) else { return nil }
        let canReply = actions.contains { isReply(actionTitle($0)) }
        return Banner(id: id, appName: app, title: title, subtitle: subtitle, body: body, canReply: canReply)
    }

    /// "Name:Responder\nTarget:0x0\nSelector:(null)" -> "Responder".
    nonisolated static func actionTitle(_ raw: String) -> String {
        guard raw.hasPrefix("Name:") else { return raw }
        return clean(String(raw.dropFirst(5).prefix { $0 != "\n" }))
    }

    nonisolated static func isReply(_ title: String) -> Bool {
        ["responder", "reply", "contestar"].contains(title.lowercased())
    }

    nonisolated static func isSend(_ title: String) -> Bool {
        ["enviar", "send"].contains(title.lowercased())
    }

    /// Sin las marcas de direccion (U+200E, U+200F) que mete macOS ni espacios.
    nonisolated static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{200E}\u{200F}").union(.whitespacesAndNewlines))
    }

    // MARK: - Responder

    /// Abre la respuesta del aviso, escribe el texto y lo envia. `false` si el aviso
    /// ya no esta o no se pudo (la tarjeta ofrece entonces abrir la app).
    func reply(to id: String, text: String, completion: @escaping (Bool) -> Void) {
        guard AXAccess.isTrusted, let group = Self.groups().first(where: { Self.string($0, kAXIdentifierAttribute) == id }),
              let action = Self.actionNames(group).first(where: { Self.isReply(Self.actionTitle($0)) }) else {
            completion(false)
            return
        }
        // macOS puede devolver error aunque abra el campo: se comprueba el campo.
        AXUIElementPerformAction(group, action as CFString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let field = Self.find(in: group, where: { Self.string($0, kAXRoleAttribute) == kAXTextAreaRole as String || Self.string($0, kAXRoleAttribute) == kAXTextFieldRole as String }) else {
                completion(false)
                return
            }
            AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString) == .success else {
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if let send = Self.actionNames(group).first(where: { Self.isSend(Self.actionTitle($0)) }) {
                    AXUIElementPerformAction(group, send as CFString)
                    completion(true)
                } else if let button = Self.find(in: group, where: {
                    Self.string($0, kAXRoleAttribute) == kAXButtonRole as String && Self.isSend(Self.clean(Self.string($0, kAXDescriptionAttribute) ?? ""))
                }) {
                    completion(AXUIElementPerformAction(button, kAXPressAction as CFString) == .success)
                } else {
                    completion(false)
                }
            }
        }
    }

    // MARK: - Accesibilidad

    private static func find(in root: AXUIElement, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = [(root, 0)]
        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            if element != root, match(element) { return element }
            guard depth < 6 else { continue }
            queue += elements(element, kAXChildrenAttribute).map { ($0, depth + 1) }
        }
        return nil
    }

    private static func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        AXUIElementCopyActionNames(element, &names)
        return names as? [String] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
