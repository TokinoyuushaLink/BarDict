import SwiftUI
import WebKit

struct WebEntryView: NSViewRepresentable {
    let html: String
    let isDark: Bool
    let fontSize: CGFloat
    var dictCss: String? = nil
    var onEntryLink: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(
            source: """
            window.addEventListener('scroll', function() {
                if (window.scrollX !== 0) window.scrollTo(0, window.scrollY);
            }, { passive: true });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }

    // MARK: - HTML wrapper

    private var wrappedHTML: String {
        let dictStyleBlock = dictCss.map { "<style>\($0)</style>" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        \(dictStyleBlock)
        <style>\(css)</style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    // MARK: - Override CSS

    private var css: String {
        """
        :root { color-scheme: light dark; }
        html, body {
            background: transparent !important;
            margin: 0; padding: 12px 14px;
            font-family: -apple-system, "Helvetica Neue", sans-serif;
            font-size: \(fontSize)px;
            line-height: 1.65;
            color: #1a1a1a;
            overflow-x: hidden;
        }
        * {
            background: transparent !important;
            background-color: transparent !important;
            max-width: 100%;
        }

        /* --- Hide layout noise --- */
        a[href="#topAnchor"],
        a[style*="position:fixed"],
        *[style*="position:fixed"],
        *[style*="position: fixed"],
        .word-audio,
        a[href^="sound://"],
        a.fayin,
        img[src="uk_pron.png"],
        img[src="us_pron.png"],
        link { display: none !important; }

        /* --- Headwords --- */
        h2, h3.entry_title {
            display: block;
            font-size: 1.5em; font-weight: 700;
            margin: 0 0 4px;
            color: #111;
        }
        .hw, span.hw { font-size: 1.5em; font-weight: 700; color: #111; }
        /* Oxford wraps headword in span.h-g > span.hw */
        .h-g .hw { display: inline; }

        /* --- Pronunciation --- */
        pron, .pr, .phon-gb, .phon-us, [class*="phon"] {
            font-size: 0.88em; color: #666;
        }

        /* --- Part of speech --- */
        .class, .pos, span[class="pos"] {
            font-style: italic; color: #666; font-size: 0.9em;
        }

        /* --- Chinese / definitions --- */
        .zh, .chn { color: #444; }
        .df        { color: #333; }
        .sense     { margin: 3px 0; }

        /* --- Examples --- */
        p.ex, .eg, .x-g,
        .def-sentence-from { margin-left: 14px; font-size: 0.9em; color: #555; }
        .def-sentence-to   { margin-left: 14px; font-size: 0.87em; color: #666; }

        /* --- Cross-reference links --- */
        a[href^="entry://"] {
            color: #0066cc; text-decoration: none; cursor: pointer;
        }
        a[href^="entry://"]:hover { text-decoration: underline; }

        /* --- Numbered sense labels --- */
        b.num { color: #888; }

        /* --- Definition lists (Collins) --- */
        dl { margin: 0; }
        dt { font-weight: 600; margin-top: 6px; }
        dd { margin-left: 12px; }
        dd.empt, dd:empty { display: none !important; }

        /* --- Oxford frequency chart (no CSS in db) --- */
        ranks { display: none !important; }

        /* --- Block horizontal overflow --- */
        html { overflow-x: hidden; max-width: 100vw; }
        body { overflow-x: hidden; max-width: 100%; }
        img, video, table, pre { max-width: 100% !important; }

        /* ========== DARK MODE ========== */
        @media (prefers-color-scheme: dark) {
            body { color: #e0e0e0; }
            h2, h3.entry_title, .hw, span.hw  { color: #f5f5f5; }
            pron, .pr, .phon-gb, .phon-us,
            [class*="phon"]                    { color: #aaa; }
            .class, .pos, span[class="pos"]    { color: #aaa; }
            .zh, .chn                          { color: #ccc; }
            .df                                { color: #ddd; }
            p.ex, .eg, .x-g,
            .def-sentence-from                 { color: #aaa; }
            .def-sentence-to                   { color: #999; }
            a[href^="entry://"]                { color: #6699ff; }
            b.num                              { color: #777; }
        }
        """
    }

    // MARK: - Navigation delegate

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebEntryView
        init(_ parent: WebEntryView) { self.parent = parent }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.allow); return }
            let s = url.absoluteString
            if s.hasPrefix("entry://") {
                let word = s
                    .replacingOccurrences(of: "entry://", with: "")
                    .removingPercentEncoding ?? s
                parent.onEntryLink(word)
                decisionHandler(.cancel)
            } else if s.hasPrefix("about:") {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
