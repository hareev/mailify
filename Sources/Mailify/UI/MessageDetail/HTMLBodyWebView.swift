import SwiftUI
import WebKit

/// Read-only HTML renderer for email bodies. Deliberately narrow: JavaScript
/// disabled, no WKUserContentController, no message-handler bridge — this is
/// NOT the old app-logic-in-a-WebView pattern, just a rendering surface, since
/// NSAttributedString's HTML support is too limited for real marketing/
/// newsletter emails (no CSS layout, unreliable image loading).
struct HTMLBodyWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.wrap(html), baseURL: nil)
    }

    /// Wraps the raw body in a minimal shell with a system-font default and a
    /// viewport meta tag, so plain-text fallback (wrapped in <pre> upstream)
    /// and real HTML emails both render reasonably.
    private static func wrap(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body { font-family: -apple-system, sans-serif; font-size: 14px; color: #1c1c1e;
                 margin: 0; padding: 4px; word-wrap: break-word; }
          img { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}
