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

    /// Fondo blanco como en Mail (los correos estan pensados para el), margenes y
    /// imagenes que no se salen.
    static func wrap(_ html: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="light">
        <style>
        html,body{background:#ffffff;color:#111;margin:0;padding:10px 12px;font:13px -apple-system,system-ui,sans-serif;word-wrap:break-word}
        img{max-width:100%;height:auto}
        table{max-width:100%}
        </style></head><body>\(html)</body></html>
        """
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
