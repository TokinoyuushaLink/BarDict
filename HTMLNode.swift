// HTMLNode.swift — lightweight HTML tokenizer & tree builder for NCECD entries
import Foundation

struct HTMLNode {
    let tag: String          // "" = text node
    let classes: [String]
    let href: String?
    let text: String         // only used when tag == ""
    let children: [HTMLNode]

    var isText: Bool { tag.isEmpty }
    func hasClass(_ c: String) -> Bool { classes.contains(c) }
    func textContent() -> String {
        isText ? text : children.map { $0.textContent() }.joined()
    }
    func firstChild(tag t: String) -> HTMLNode? { children.first { $0.tag == t } }
    func firstChild(class c: String) -> HTMLNode? { children.first { $0.hasClass(c) } }
}

// MARK: - Public entry point

func parseHTML(_ raw: String) -> [HTMLNode] {
    let toks = tokenize(raw)
    var i = 0
    return buildChildren(toks, at: &i, stop: nil)
}

// MARK: - Tokenizer

private enum Tok {
    case open(tag: String, classes: [String], href: String?)
    case close(tag: String)
    case text(String)
}

private let voidTags: Set<String> = ["br", "hr", "img", "input", "link", "meta"]

private func tokenize(_ html: String) -> [Tok] {
    var result: [Tok] = []
    var i = html.startIndex

    while i < html.endIndex {
        guard html[i] == "<" else {
            // Text node
            let end = html[i...].firstIndex(of: "<") ?? html.endIndex
            let raw = String(html[i..<end])
            let decoded = htmlDecode(raw)
            if !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.text(decoded))
            } else if decoded.contains("\u{00A0}") {
                result.append(.text(decoded))
            }
            i = end
            continue
        }

        let afterLt = html.index(after: i)
        guard let gt = html[afterLt...].firstIndex(of: ">") else {
            i = html.index(after: i)
            continue
        }
        let inner = String(html[afterLt..<gt])
        i = html.index(after: gt)

        if inner.hasPrefix("/") {
            // Closing tag — strip any trailing attributes/text
            let name = String(inner.dropFirst().prefix(while: { $0.isLetter || $0.isNumber })).lowercased()
            if !name.isEmpty { result.append(.close(tag: name)) }
        } else if !inner.hasPrefix("!") {
            // Opening tag
            let (tag, classes, href) = parseOpenTag(inner)
            if !tag.isEmpty {
                result.append(.open(tag: tag, classes: classes, href: href))
                // Void elements never have close tags
                if voidTags.contains(tag) {
                    result.append(.close(tag: tag))
                }
            }
        }
    }
    return result
}

private func parseOpenTag(_ s: String) -> (tag: String, classes: [String], href: String?) {
    let s2 = s.hasSuffix("/") ? String(s.dropLast()).trimmingCharacters(in: .whitespaces) : s
    let tag = String(s2.prefix(while: { !$0.isWhitespace })).lowercased()
    guard !tag.isEmpty else { return ("", [], nil) }

    var classes: [String] = []
    var href: String?

    if let m = s2.firstMatch(of: #/class="([^"]*)"/#) {
        classes = String(m.1).split(separator: " ").map(String.init)
    }
    if let m = s2.firstMatch(of: #/href="([^"]*)"/#) {
        href = String(m.1)
    }
    return (tag, classes, href)
}

private func htmlDecode(_ s: String) -> String {
    s.replacingOccurrences(of: "&amp;",  with: "&")
     .replacingOccurrences(of: "&lt;",   with: "<")
     .replacingOccurrences(of: "&gt;",   with: ">")
     .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
     .replacingOccurrences(of: "&#39;",  with: "'")
     .replacingOccurrences(of: "&quot;", with: "\"")
}

// MARK: - Tree builder

private func buildChildren(_ toks: [Tok], at pos: inout Int, stop: String?) -> [HTMLNode] {
    var nodes: [HTMLNode] = []
    while pos < toks.count {
        switch toks[pos] {
        case .text(let t):
            nodes.append(HTMLNode(tag: "", classes: [], href: nil, text: t, children: []))
            pos += 1

        case .open(let tag, let classes, let href):
            pos += 1
            let children = buildChildren(toks, at: &pos, stop: tag)
            nodes.append(HTMLNode(tag: tag, classes: classes, href: href, text: "", children: children))

        case .close(let tag):
            if tag == stop {
                pos += 1        // consume the matching close tag
                return nodes
            }
            if stop == nil {
                pos += 1        // top level: skip orphaned close tags
                continue
            }
            // Mismatched close at a nested level — do NOT consume it;
            // return to parent so it can match its own stop tag.
            return nodes
        }
    }
    return nodes
}