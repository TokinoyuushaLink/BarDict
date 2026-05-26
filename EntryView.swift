// EntryView.swift — native SwiftUI renderer for NCECD dictionary entries
import SwiftUI

// MARK: - Top-level entry point

struct EntryView: View {
    let html: String
    var onEntryLink: (String) -> Void = { _ in }

    var body: some View {
        let nodes = parseHTML(html)
        let h2      = nodes.first { $0.tag == "h2" }
        let section = nodes.first { $0.tag == "section" }
        let kids    = section?.children ?? []

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                if let h2 {
                    EntryHeaderView(h2: h2, kids: kids)
                        .padding(.bottom, 6)
                }
                ForEach(Array(kids.enumerated()), id: \.offset) { _, n in
                    EntryBodyBlock(node: n, onLink: onEntryLink)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Header (word + pron + pos + tense)

struct EntryHeaderView: View {
    let h2: HTMLNode
    let kids: [HTMLNode]

    @ScaledMetric(relativeTo: .body) private var fs: CGFloat = 13

    var body: some View {
        let pron    = kids.first { $0.tag == "pron" }
        let abbr    = kids.first { $0.tag == "span" && $0.hasClass("abbre") }
        let posNode = kids.first { $0.tag == "span" && $0.hasClass("class") }
        let tense   = kids.first { $0.tag == "span" && $0.hasClass("tense") }

        VStack(alignment: .leading, spacing: 3) {
            headerLine(pron: pron, abbr: abbr, posNode: posNode)
                .fixedSize(horizontal: false, vertical: true)
            if let t = tense { tenseView(t) }
        }
    }

    private func headerLine(pron: HTMLNode?, abbr: HTMLNode?, posNode: HTMLNode?) -> Text {
        var t = Text(h2.textContent()).font(.system(size: fs * 1.7, weight: .bold))
        if let p = pron    { t = t + Text("  \(p.textContent())").font(.system(size: fs)).foregroundColor(.secondary) }
        if let a = abbr    { t = t + Text("  [\(a.textContent())]").font(.system(size: fs * 0.85)).foregroundColor(.secondary) }
        if let p = posNode { t = t + Text("  \(p.textContent())").font(.system(size: fs).italic()).foregroundColor(.secondary) }
        return t
    }

    private func tenseView(_ node: HTMLNode) -> some View {
        var parts: [String] = []
        for child in node.children {
            if child.hasClass("tensexxx") {
                for c in child.children where c.tag == "b" { parts.append(c.textContent()) }
            }
        }
        let label = parts.isEmpty ? node.textContent() : "(\(parts.joined(separator: ", ")))"
        return Text(label).font(.system(size: fs * 0.85)).foregroundStyle(Color.secondary)
    }
}

// MARK: - Body block dispatcher

struct EntryBodyBlock: View {
    let node: HTMLNode
    var onLink: (String) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .body) private var fs: CGFloat = 13

    var body: some View {
        switch blockKind(node) {
        case .skip:          EmptyView()
        case .classBox:      classBoxView
        case .sense:         senseView
        case .example:       exampleView
        case .phrase:        phraseView
        case .seeAlso:       seeAlsoView
        case .idiom:         idiomView
        case .phrBlock:      phrBlockView
        case .label:         labelView
        case .culture:       cultureView
        case .other:         EmptyView()
        }
    }

    // MARK: Block kind detection
    private enum Kind {
        case skip, classBox, sense, example, phrase, seeAlso, idiom, phrBlock, label, culture, other
    }
    private func blockKind(_ n: HTMLNode) -> Kind {
        if n.tag == "pron" { return .skip }
        if n.tag == "span" && (n.hasClass("tense") || n.hasClass("abbre") || n.hasClass("class")) { return .skip }
        if n.tag == "div"  && n.hasClass("class_box")  { return .classBox }
        if n.tag == "div"  && n.hasClass("sense")      { return .sense }
        if n.tag == "p"    && n.hasClass("ex")         { return .example }
        if n.tag == "div"  && n.hasClass("maybe_phrase") { return .phrase }
        if n.tag == "div"  && n.hasClass("also")       { return .seeAlso }
        if n.tag == "div"  && n.hasClass("idom")       { return .idiom }
        if n.tag == "div"  && n.hasClass("phr")        { return .phrBlock }
        if (n.tag == "span" || n.tag == "div") && (n.hasClass("label") || n.hasClass("label_box")) { return .label }
        if n.tag == "span" && n.hasClass("etips")      { return .label }
        if n.tag == "fieldset"                         { return .culture }
        return .other
    }

    // MARK: Adaptive colors
    private var exEnColor: Color {
        scheme == .dark
            ? Color(red: 0.80, green: 0.72, blue: 0.66)
            : Color(red: 0.28, green: 0.28, blue: 0.30)
    }

    // MARK: Sub-views

    private var classBoxView: some View {
        let badge = node.children.first { $0.hasClass("abc") }?.textContent() ?? ""
        let pos   = node.children.first { $0.hasClass("class") }?.textContent() ?? ""
        return HStack(spacing: 6) {
            if !badge.isEmpty {
                Text(badge)
                    .font(.system(size: fs * 0.77))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }
            Text(pos).font(.system(size: fs).bold().italic()).foregroundStyle(Color.secondary)
        }
        .padding(.top, 10).padding(.bottom, 2)
    }

    private var senseView: some View {
        inlineText(node.children, fs: fs)
            .font(.system(size: fs))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
    }

    private var exampleView: some View {
        let zh      = node.children.first { $0.tag == "span" && $0.hasClass("zh") }
        let enNodes = node.children.filter { !($0.tag == "span" && $0.hasClass("zh")) }
        return VStack(alignment: .leading, spacing: 1) {
            inlineText(enNodes, fs: fs * 0.92)
                .foregroundColor(exEnColor)
                .font(.system(size: fs * 0.92))
                .fixedSize(horizontal: false, vertical: true)
            if let zh {
                Text(zh.textContent())
                    .font(.system(size: fs * 0.92)).foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 14)
        .padding(.vertical, 3)
    }

    private var phraseView: some View {
        let label = node.children.first { $0.hasClass("label") }
        let en    = node.children.first { $0.hasClass("mphr_en") }
        let zh    = node.children.first { $0.tag == "span" && $0.hasClass("zh") }
        return HStack(alignment: .top, spacing: 4) {
            if let l = label {
                Text(l.textContent()).font(.system(size: fs * 0.85)).foregroundStyle(Color.secondary)
            }
            if let en {
                (Text(en.textContent()).fontWeight(.medium)
                 + (zh.map { Text("  \($0.textContent())").foregroundColor(Color.secondary) } ?? Text("")))
                    .font(.system(size: fs * 0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 2)
    }

    private var seeAlsoView: some View {
        let links = node.children.filter { $0.tag == "a" }
        return Group {
            if !links.isEmpty {
                HStack(spacing: 4) {
                    Text("See also").font(.system(size: fs * 0.92).italic()).foregroundStyle(Color.secondary)
                    ForEach(Array(links.enumerated()), id: \.offset) { _, a in
                        Button(a.textContent()) { followLink(a.href) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color(.linkColor))
                            .font(.system(size: fs * 0.92))
                    }
                }
                .padding(.vertical, 4)
            } else {
                let raw = node.children
                    .filter { $0.tag != "b" }
                    .map { $0.textContent() }
                    .joined()
                    .trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty {
                    (Text("See also  ").font(.system(size: fs * 0.92).italic()).foregroundColor(Color.secondary)
                     + Text(raw).font(.system(size: fs * 0.92)).foregroundColor(Color(.linkColor)))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private var idiomView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("idiom").font(.system(size: fs).bold().italic()).padding(.top, 10).padding(.bottom, 4)
            ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                EntryBodyBlock(node: child, onLink: onLink)
            }
        }
    }

    private var phrBlockView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = node.children.first(where: { $0.tag == "b" }) {
                Text(title.textContent() + ":")
                    .font(.system(size: fs).bold()).foregroundStyle(Color.orange)
                    .padding(.top, 10).padding(.bottom, 2)
            }
            ForEach(Array(node.children.dropFirst().enumerated()), id: \.offset) { _, child in
                EntryBodyBlock(node: child, onLink: onLink)
            }
        }
    }

    private var labelView: some View {
        Text(node.textContent())
            .font(.system(size: fs * 0.85).italic())
            .foregroundStyle(Color.secondary)
            .padding(.vertical, 1)
    }

    private var cultureView: some View {
        let title = node.children.first { $0.hasClass("notetitle") || $0.tag == "legend" }
        let body  = node.children.filter { $0.tag != "legend" && !$0.hasClass("notetitle") }
        return VStack(alignment: .leading, spacing: 4) {
            if let t = title {
                Text(t.textContent()).font(.system(size: fs * 0.92).bold()).foregroundStyle(Color.secondary)
            }
            Text(body.map { $0.textContent() }.joined().trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: fs * 0.85)).foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.07))
        .cornerRadius(6)
        .padding(.vertical, 6)
    }

    // MARK: - Link handler
    private func followLink(_ href: String?) {
        guard let href else { return }
        let word = href
            .replacingOccurrences(of: "entry://", with: "")
            .removingPercentEncoding ?? href
        onLink(word)
    }
}

// MARK: - Inline Text helpers (free functions to avoid struct bloat)

func inlineText(_ nodes: [HTMLNode], fs: CGFloat) -> Text {
    nodes.reduce(Text("")) { $0 + nodeToText($1, fs: fs) }
}

private let colColor = Color(.tertiaryLabelColor)

func nodeToText(_ n: HTMLNode, fs: CGFloat) -> Text {
    if n.isText { return Text(n.text) }
    let inner = inlineText(n.children, fs: fs)

    if n.tag == "b" {
        if n.hasClass("num") {
            return Text(n.textContent()).bold().foregroundColor(.secondary) + Text("\u{2002}")
        }
        return inner.bold()
    }
    if n.tag == "strong" {
        if n.hasClass("brief_ex") {
            let s = n.textContent().trimmingCharacters(in: .whitespaces)
            return Text(s).italic().foregroundColor(.secondary) + Text("  ")
        }
        return inner.bold()
    }
    if n.tag == "sup"  { return inlineText(n.children, fs: fs).font(.system(size: fs * 0.77)).baselineOffset(5) }
    if n.tag == "i"    { return inner.italic() }
    if n.tag == "a"    { return inner.foregroundColor(Color(.linkColor)) }
    if n.tag == "pron" { return inner.foregroundColor(.secondary) }

    if n.tag == "span" { return spanToText(n, inner: inner, fs: fs) }
    return inner
}

private func spanToText(_ n: HTMLNode, inner: Text, fs: CGFloat) -> Text {
    if n.hasClass("zh")          { return Text(" ") + inner }
    if n.hasClass("collocation") { return Text(" ") + inner.foregroundColor(colColor).italic() }
    if n.hasClass("nmb")         { return Text(" or ").italic().foregroundColor(.secondary) }
    if n.hasClass("or")          { return Text(" or ").italic().foregroundColor(.secondary) }
    if n.hasClass("pluralor")    { return Text(" or ").italic().foregroundColor(.secondary) }
    if n.hasClass("dodo")        { return inner + Text("  ") }
    if n.hasClass("idom")        { return inner.bold().italic() }
    if n.hasClass("label")       { return Text(" ") + inner.font(.system(size: fs * 0.85)).foregroundColor(.secondary) }
    if n.hasClass("class")       { return Text(" ") + inner.italic().foregroundColor(.secondary) }
    if n.hasClass("abbre") || n.hasClass("abbrecar") || n.hasClass("symbol") {
        return Text(" [") + inner + Text("]")
    }
    return inner
}