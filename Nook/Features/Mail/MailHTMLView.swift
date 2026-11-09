import AppKit
import SwiftUI
import WebKit

/// Un correo HTML como en Mail: sin JavaScript, los enlaces se abren en el navegador
/// y las imagenes remotas bloqueadas hasta que se piden (suelen servir para saber
/// si has abierto el correo).
struct MailHTMLView: NSViewRepresentable {
    let html: String
    let allowRemote: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let key = "\(html.hashValue)-\(allowRemote)"
        guard context.coordinator.loaded != key else { return }
        context.coordinator.loaded = key
        let controller = view.configuration.userContentController
        controller.removeAllContentRuleLists()
        let page = Self.wrap(html)
        guard !allowRemote else {
            view.loadHTMLString(page, baseURL: nil)
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "nook-block-remote", encodedContentRuleList: Self.blockRemote) { list, _ in
            if let list { controller.add(list) }
            view.loadHTMLString(page, baseURL: nil)
        }
    }

    /// Como Mail: un correo sin fondos propios (el tipico escrito a mano) se ve en
    /// oscuro, a juego con el notch; uno diseñado (newsletter, factura) va sobre
    /// blanco, porque esta pensado para eso y oscurecerlo lo rompe.
    static func wrap(_ html: String) -> String {
        let dark = isPlain(html)
        let page = dark
            ? "html,body{background:#1c1c1e!important;color:#ececf0!important}*{color:inherit!important;background:transparent!important}a{color:#7da2ff!important}"
            : "html,body{background:#ffffff;color:#111}"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="\(dark ? "dark" : "light")">
        <style>
        \(page)
        html,body{margin:0;padding:10px 12px;font:13px -apple-system,system-ui,sans-serif;word-wrap:break-word}
        img{max-width:100%;height:auto}
        table{max-width:100%}
        </style></head><body>\(html)</body></html>
        """
    }

    /// Sin colores de fondo en ningun sitio (ni bgcolor ni background en el CSS).
    static func isPlain(_ html: String) -> Bool {
        let pattern = #"bgcolor\s*=|background(-color|-image)?\s*:\s*(?!\s*(transparent|none|inherit|initial)\b)"#
        return html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil
    }

    /// Todo bloqueado salvo las imagenes incrustadas (data:).
    static let blockRemote = """
    [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
     {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}},
     {"trigger":{"url-filter":"^about:"},"action":{"type":"ignore-previous-rules"}}]
    """

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?

        /// Los enlaces se abren en el navegador, no dentro del notch.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
