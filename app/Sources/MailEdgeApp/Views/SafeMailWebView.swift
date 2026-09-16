import AppKit
import SwiftUI
import WebKit

struct SafeMailWebView: NSViewRepresentable {
  let html: String?
  let plainText: String

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.websiteDataStore = .nonPersistent()

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.setValue(false, forKey: "drawsBackground")
    webView.allowsMagnification = true
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    let document = makeDocument()
    guard document != context.coordinator.lastDocument else { return }
    context.coordinator.lastDocument = document
    webView.loadHTMLString(document, baseURL: nil)
  }

  private func makeDocument() -> String {
    let body = html?.nilIfBlank ?? "<pre>\(plainText.htmlEscaped)</pre>"
    return """
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: cid:; style-src 'unsafe-inline'; font-src data:">
        <style>
          :root { color-scheme: light dark; font: -apple-system-body; }
          html, body { margin: 0; padding: 0; background: transparent; color: CanvasText; }
          body { padding: 20px; overflow-wrap: anywhere; line-height: 1.55; }
          img { max-width: 100% !important; height: auto !important; }
          table { max-width: 100% !important; }
          a { color: #3478f6; }
          pre { white-space: pre-wrap; font: inherit; margin: 0; }
          blockquote { border-left: 3px solid #8e8e93; margin-left: 0; padding-left: 14px; color: #6e6e73; }
        </style>
      </head>
      <body>\(body)</body>
      </html>
      """
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    var lastDocument = ""

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
      guard navigationAction.navigationType == .linkActivated,
        let url = navigationAction.request.url
      else {
        return .allow
      }
      if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
        NSWorkspace.shared.open(url)
      }
      return .cancel
    }
  }
}

extension String {
  fileprivate var htmlEscaped: String {
    replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
