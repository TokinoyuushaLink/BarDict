import SwiftUI
import WebKit

struct WebEntryView: NSViewRepresentable {
    typealias NSViewType = TrackpadWebView

    let html: String
    let isDark: Bool
    let fontSize: CGFloat
    var dictCss: String?               = nil
    var onEntryLink:    (String) -> Void = { _ in }
    var onSwipeRight:   (() -> Void)?    = nil
    var onSwipeLeft:    (() -> Void)?    = nil
    var onScrollY:      ((CGFloat) -> Void)? = nil
    var restoreScrollY: CGFloat          = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TrackpadWebView {
        let config = WKWebViewConfiguration()
        // Proxy avoids the retain cycle from add(_:name:)
        config.userContentController.add(
            ScriptMessageProxy(context.coordinator), name: "scroll"
        )
        config.userContentController.addUserScript(WKUserScript(
            source: """
            window.addEventListener('scroll', function() {
                if (window.scrollX !== 0) window.scrollTo(0, window.scrollY);
                window.webkit.messageHandlers.scroll.postMessage(window.scrollY);
            }, { passive: true });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let webView = TrackpadWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: TrackpadWebView, context: Context) {
        context.coordinator.parent = self
        webView.onSwipeRight = onSwipeRight
        webView.onSwipeLeft  = onSwipeLeft
        webView.appearance   = NSAppearance(named: isDark ? .darkAqua : .aqua)
        // Only reload when HTML actually changes — prevents scroll-to-top on unrelated state updates
        let html = wrappedHTML
        guard html != context.coordinator.loadedHTML else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
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

        /* --- 新世纪汉英大词典 结构 --- */
        /* 词性标签 h5 默认 margin 是空行主因 */
        h5 { margin: 4px 0 1px; font-size: 0.88em; font-weight: normal; color: #888; }
        /* 义项列表去掉默认缩进和 bullet */
        ol.info-list { margin: 0; padding-left: 0; list-style: none; }
        ol.info-list > li { margin: 2px 0; padding: 0; }
        /* 每个义项前的 height:1px 占位 div */
        div[style*="height: 1px"] { display: none !important; }
        /* 发音按钮隐藏（不可点击但占行高） */
        .btn-sound { display: none !important; }
        /* 例句块 */
        .info-cite { margin: 1px 0 1px 14px; }
        .info-cite p { margin: 1px 0; }
        /* 义项编号 */
        i.number { font-style: normal; color: #999; font-size: 0.85em; margin-right: 3px; }
        /* 相关词条列表 */
        p.gray { margin: 1px 0; font-size: 0.88em; }
        p:empty, p.gray:empty { display: none !important; }

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

    // MARK: - JS → Swift message proxy (weak ref avoids retain cycle)

    private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
        weak var coordinator: Coordinator?
        init(_ c: Coordinator) { coordinator = c }
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let y = message.body as? Double else { return }
            coordinator?.parent.onScrollY?(CGFloat(y))
        }
    }

    // MARK: - Trackpad-aware WKWebView

    final class TrackpadWebView: WKWebView {
        var onSwipeRight: (() -> Void)?
        var onSwipeLeft:  (() -> Void)?

        private var cumulativeDX: CGFloat = 0
        private var cumulativeDY: CGFloat = 0
        private var isHorizontal: Bool?   = nil
        private let lockThreshold: CGFloat  = 5
        private let swipeThreshold: CGFloat = 40

        override func scrollWheel(with event: NSEvent) {
            if event.phase == .began {
                cumulativeDX = 0
                cumulativeDY = 0
                isHorizontal = nil
            }

            // Only accumulate real gesture events, not momentum
            if !event.phase.isEmpty {
                cumulativeDX += event.scrollingDeltaX
                cumulativeDY += event.scrollingDeltaY
            }

            if isHorizontal == nil {
                let ax = abs(cumulativeDX), ay = abs(cumulativeDY)
                if ax > lockThreshold || ay > lockThreshold {
                    isHorizontal = ax > ay
                }
            }

            if isHorizontal == true {
                // Confirmed horizontal: intercept for swipe, never scroll
                if event.phase == .ended {
                    if cumulativeDX > swipeThreshold {
                        onSwipeRight?()
                    } else if cumulativeDX < -swipeThreshold {
                        onSwipeLeft?()
                    }
                }
            } else {
                // Vertical or not yet determined: pass through so rubber-band
                // elastic scroll at top/bottom is preserved. Any incidental
                // horizontal drift is reset by the JS scroll listener.
                super.scrollWheel(with: event)
            }
        }
    }

    // MARK: - Navigation delegate

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebEntryView
        var loadedHTML: String = ""
        init(_ parent: WebEntryView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let y = parent.restoreScrollY
            guard y > 0 else { return }
            webView.evaluateJavaScript("window.scrollTo(0, \(y));", completionHandler: nil)
        }

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
