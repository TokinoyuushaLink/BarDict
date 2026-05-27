
// DictPanel.swift
import SwiftUI
import AppKit

struct DictionaryPanel: View {
    var onDismiss:      () -> Void        = {}
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var onDictChange:   (String) -> Void  = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @State private var query          = ""
    @State private var suggestions:  [String] = []
    @State private var currentHTML:  String?
    @State private var selectedWord: String? = nil
    @State private var recents:      [String] = RecentStore.load()
    @State private var searchFocusRequest: Int = 0
    @State private var hoveredWord:  String? = nil

    // Multi-dict detail state
    @State private var currentWord:         String   = ""
    @State private var wordDicts:           [String] = []   // dicts that have the current word
    @State private var selectedDictName:    String   = ""
    @State private var currentDictCss:      String?  = nil

    // Entry-link navigation history
    @State private var history: [String] = []

    @AppStorage("textSizeIndex")      private var textSizeIndex:      Int    = 1
    @AppStorage("useEmbeddedCSS")     private var useEmbeddedCSS:     Bool   = true
    @AppStorage("preferredLanguage")  private var preferredLanguage:  String = ""
    @ObservedObject private var manager = DictionaryManager.shared

    static  let listHeight:   CGFloat = 380
    static  let detailHeight: CGFloat = 520
    private static let fontSizes: [CGFloat] = [13, 14.3, 15.6, 16.9, 18.2]

    private var currentList: [String] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? recents : suggestions
    }

    var body: some View {
        VStack(spacing: 0) {
            if manager.isEmpty {
                DictNotFoundView()
            } else {
                searchBar
                Divider()
                contentArea
                    .clipped()
            }
        }
        .id(preferredLanguage)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if colorScheme == .light {
                Color(NSColor.windowBackgroundColor).opacity(0.70)
            }
        }
        // Re-run suggestions when filter changes
        .onChange(of: manager.filterNames) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty, currentHTML == nil else { return }
            suggestions = manager.suggest(prefix: q, filteredBy: manager.filterNames)
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondary)
                .font(.body)
            SearchField(
                text: $query,
                placeholder: L.searchPlaceholder,
                focusRequest: searchFocusRequest,
                onTextChange: { newValue in
                    let wasInDetail = currentHTML != nil
                    let update = {
                        currentHTML  = nil
                        selectedWord = nil
                        wordDicts    = []
                        suggestions  = manager.suggest(prefix: newValue, filteredBy: manager.filterNames)
                        if wasInDetail { onHeightChange(Self.listHeight) }
                    }
                    if wasInDetail {
                        withAnimation(.easeInOut(duration: 0.22)) { update() }
                    } else {
                        update()
                    }
                },
                onSubmit:    confirmSelection,
                onEscape:    handleEscape,
                onArrowDown: { if currentHTML == nil { moveSelection(by:  1) } },
                onArrowUp:   { if currentHTML == nil { moveSelection(by: -1) } },
                onTab:       { shift in if currentHTML == nil { moveSelection(by: shift ? -1 : 1) } }
            )
            if !query.isEmpty {
                Button { withAnimation(.easeInOut(duration: 0.22)) { clearAll() } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: Content area

    @ViewBuilder
    private var contentArea: some View {
        if let html = currentHTML {
            VStack(spacing: 0) {
                if wordDicts.count > 1 {
                    dictSwitcherBar
                    Divider()
                }
                WebEntryView(
                    html: html,
                    isDark: colorScheme == .dark,
                    fontSize: Self.fontSizes[textSizeIndex],
                    dictCss: useEmbeddedCSS ? currentDictCss : nil
                ) { linkedWord in navigateTo(linkedWord) }
                .overlay(alignment: .topLeading) {
                    if !history.isEmpty { backButton }
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .trailing).combined(with: .opacity)
            ))
        } else {
            VStack(spacing: 0) {
                if manager.enabledNames.count > 1 {
                    filterBar
                    Divider()
                }
                if currentList.isEmpty {
                    ContentUnavailableViewCompat()
                } else {
                    listView
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }

    // MARK: Filter bar (list mode, below search)

    private var filterBar: some View {
        let groups     = langGroups(dicts: manager.enabledNames, map: manager.dictLangMap)
        let showLabels = groups.count > 1
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                    if idx > 0 {
                        Divider().frame(height: 14).padding(.horizontal, 6)
                    }
                    if showLabels {
                        Text(group.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                    }
                    HStack(spacing: 6) {
                        ForEach(group.dicts, id: \.self) { name in
                            DictChip(
                                label: shortDictName(name),
                                isOn: manager.filterNames.contains(name)
                            ) {
                                manager.toggleFilter(name)
                                onDictChange(name)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private struct LangGroup {
        let label: String
        let dicts: [String]
    }

    private func langGroups(dicts: [String], map: [String: String]) -> [LangGroup] {
        var buckets: [(lang: AppLang?, dicts: [String])] = []
        var byLang:  [String: [String]] = [:]
        var none:    [String] = []
        for d in dicts {
            if let code = map[d], !code.isEmpty, let lang = AppLang(rawValue: code) {
                byLang[code, default: []].append(d)
                _ = lang
            } else {
                none.append(d)
            }
        }
        for lang in AppLang.allCases where lang != .auto {
            if let ds = byLang[lang.rawValue], !ds.isEmpty {
                buckets.append((lang: lang, dicts: ds))
            }
        }
        if !none.isEmpty {
            buckets.append((lang: nil, dicts: none))
        }
        return buckets.map { b in
            LangGroup(label: b.lang?.displayName ?? L.unassigned, dicts: b.dicts)
        }
    }

    // MARK: Dict switcher bar (detail mode, above entry)

    private var dictSwitcherBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(wordDicts, id: \.self) { name in
                    DictChip(
                        label: shortDictName(name),
                        isOn: selectedDictName == name
                    ) {
                        switchDict(name)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: Word list

    private var listView: some View {
        let isRecent = query.trimmingCharacters(in: .whitespaces).isEmpty
        return List(selection: $selectedWord) {
            if isRecent {
                HStack {
                    Text(L.recentSearches)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Button {
                        RecentStore.clearAll()
                        recents = RecentStore.load()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .selectionDisabled()
            }
            ForEach(currentList, id: \.self) { word in
                let selected   = selectedWord == word
                let showDelete = isRecent && (selected || hoveredWord == word)
                HStack(spacing: 0) {
                    Button {
                        selectedWord = word
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { lookup(word) }
                    } label: {
                        Text(word)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showDelete {
                        Button {
                            RecentStore.remove(word)
                            recents = RecentStore.load()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(selected ? Color.white.opacity(0.7) : Color.secondary)
                                .padding(.trailing, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .tag(word)
                .listRowBackground(selected ? Color.accentColor : Color.clear)
                .listRowSeparator(.hidden)
                .onHover { isHovered in hoveredWord = isHovered ? word : nil }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: Back button (floats over WebView)

    private var backButton: some View {
        Button(action: goBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.secondary)
        }
        .buttonStyle(BackButtonStyle())
        .padding(10)
    }

    // MARK: Helpers

    private func shortDictName(_ name: String) -> String {
        name.count <= 5 ? name : String(name.prefix(4)) + "…"
    }

    // MARK: Actions

    private func moveSelection(by delta: Int) {
        let list = currentList
        guard !list.isEmpty else { return }
        if let current = selectedWord, let idx = list.firstIndex(of: current) {
            selectedWord = list[max(0, min(list.count - 1, idx + delta))]
        } else {
            selectedWord = delta > 0 ? list.first : list.last
        }
    }

    private func confirmSelection() {
        let word = selectedWord ?? currentList.first ?? ""
        guard !word.isEmpty else { return }
        selectedWord = word
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { lookup(word) }
    }

    private func handleEscape() {
        if currentHTML != nil {
            withAnimation(.easeInOut(duration: 0.22)) { clearAll() }
        } else if !query.isEmpty {
            clearAll()
        } else {
            onDismiss()
        }
    }

    private func clearAll() {
        query            = ""
        suggestions      = []
        currentHTML      = nil
        selectedWord     = nil
        currentWord      = ""
        wordDicts        = []
        selectedDictName = ""
        history          = []
        onHeightChange(Self.listHeight)
    }

    // Called from list view — clears navigation history
    private func lookup(_ word: String) {
        history = []
        withAnimation(.easeInOut(duration: 0.22)) {
            doLookup(word)
        }
    }

    // Called from entry:// links — pushes current word onto history
    private func navigateTo(_ word: String) {
        if !currentWord.isEmpty { history.append(currentWord) }
        doLookup(word)
    }

    private func goBack() {
        guard let prev = history.popLast() else { return }
        doLookup(prev)
    }

    private func doLookup(_ word: String) {
        guard !word.isEmpty else { return }
        query       = word
        currentWord = word
        suggestions = manager.suggest(prefix: word, filteredBy: manager.filterNames)

        let dicts = manager.availableDicts(for: word, among: manager.filterNames)
        wordDicts        = dicts
        selectedDictName = dicts.first ?? ""
        let html         = dicts.first.flatMap { manager.html(for: word, in: $0) }
        currentHTML      = html
        currentDictCss   = dicts.first.flatMap { manager.css(for: $0) }
        selectedWord     = nil

        if let firstDict = dicts.first { onDictChange(firstDict) }
        onHeightChange(html != nil ? Self.detailHeight : Self.listHeight)
        searchFocusRequest += 1
        RecentStore.add(word)
        recents = RecentStore.load()
    }

    private func switchDict(_ name: String) {
        guard !currentWord.isEmpty else { return }
        selectedDictName = name
        currentHTML      = manager.html(for: currentWord, in: name)
        currentDictCss   = manager.css(for: name)
        onDictChange(name)
    }
}

// MARK: - Back button style (icon only, color-change on press)

private struct BackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.4 : 1)
    }
}

// MARK: - Chip button (shared by filter bar and dict switcher)

private struct DictChip: View {
    let label:  String
    let isOn:   Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent searches

private enum RecentStore {
    private static let maxCount = 50

    private static var url: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BarDict")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("recent.json")
    }

    static func load() -> [String] {
        guard let data = try? Data(contentsOf: url),
              let arr  = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    static func add(_ word: String) {
        var list = load()
        list.removeAll { $0.lowercased() == word.lowercased() }
        list.insert(word, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func remove(_ word: String) {
        var list = load()
        list.removeAll { $0.lowercased() == word.lowercased() }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clearAll() {
        guard let data = try? JSONEncoder().encode([String]()) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Custom NSTextField

private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder:  String           = ""
    var focusRequest: Int              = 0
    var onTextChange: (String) -> Void = { _ in }
    var onSubmit:     () -> Void       = {}
    var onEscape:     () -> Void       = {}
    var onArrowDown:  () -> Void       = {}
    var onArrowUp:    () -> Void       = {}
    var onTab:        (Bool) -> Void   = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString  = placeholder
        field.isBordered         = false
        field.drawsBackground    = false
        field.focusRingType      = .none
        field.font               = .systemFont(ofSize: NSFont.systemFontSize)
        field.cell?.wraps        = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            nsView.window?.makeFirstResponder(nsView)
            nsView.currentEditor()?.selectAll(nil)
            return
        }
        guard nsView.stringValue != text else { return }
        nsView.stringValue = text
        if let editor = nsView.currentEditor() {
            editor.selectedRange = NSRange(location: nsView.stringValue.utf16.count, length: 0)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var lastFocusRequest: Int = 0
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let v = field.stringValue
            parent.text = v
            parent.onTextChange(v)
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):   parent.onSubmit();    return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onEscape();    return true
            case #selector(NSResponder.moveDown(_:)):        parent.onArrowDown(); return true
            case #selector(NSResponder.moveUp(_:)):          parent.onArrowUp();   return true
            case #selector(NSResponder.insertTab(_:)):       parent.onTab(false);  return true
            case #selector(NSResponder.insertBacktab(_:)):   parent.onTab(true);   return true
            default: return false
            }
        }
    }
}

// MARK: - Placeholder views

struct DictNotFoundView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(L.noDictImported).font(.headline)
            Text(L.importHint)
                .foregroundStyle(.secondary).font(.subheadline)
                .multilineTextAlignment(.center).padding(.horizontal, 16)
            Button(L.openDictFolder) {
                NSWorkspace.shared.open(DictionaryManager.dirURL)
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentUnavailableViewCompat: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "character.book.closed")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(L.typeToSearch).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}