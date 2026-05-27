import Foundation
import AppKit
import UniformTypeIdentifiers

struct DictInfo: Identifiable, Hashable {
    let name: String   // filename stem, e.g. "新世纪英汉词典"
    let url: URL
    var id: String { name }
}

final class DictionaryManager: ObservableObject {

    static let shared = DictionaryManager()

    private static let enabledKey = "enabledDictNames"
    private static let filterKey  = "filterDictNames"

    static let dirURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BarDict")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    @Published private(set) var allDicts:    [DictInfo] = []
    @Published private(set) var enabledNames: [String]  = []
    @Published private(set) var filterNames:  [String]  = []   // subset shown in list
    @Published              var dictLangMap:  [String: String] = {
        (UserDefaults.standard.dictionary(forKey: "dictLangMap") as? [String: String]) ?? [:]
    }()

    private var stores: [String: DictionaryStore] = [:]

    private init() { refresh() }

    // MARK: - Scan & reload

    func refresh() {
        let fm   = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: Self.dirURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        let infos = urls.map { DictInfo(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
        let names = Set(infos.map { $0.name })

        var savedEnabled = UserDefaults.standard.stringArray(forKey: Self.enabledKey) ?? []
        savedEnabled = savedEnabled.filter { names.contains($0) }
        if savedEnabled.isEmpty { savedEnabled = infos.map { $0.name } }

        var savedFilter = UserDefaults.standard.stringArray(forKey: Self.filterKey) ?? []
        savedFilter = savedFilter.filter { Set(savedEnabled).contains($0) }
        if savedFilter.isEmpty { savedFilter = savedEnabled }

        var newStores: [String: DictionaryStore] = [:]
        for info in infos {
            if let existing = stores[info.name] {
                newStores[info.name] = existing
            } else if let store = DictionaryStore(path: info.url.path) {
                newStores[info.name] = store
            } else {
                print("[BarDict] 无法打开词典数据库: \(info.url.lastPathComponent)")
            }
        }

        allDicts     = infos
        enabledNames = savedEnabled
        filterNames  = savedFilter
        stores       = newStores
        persist()
    }

    // MARK: - Toggle enabled (from menu)

    func toggle(_ name: String) {
        if enabledNames.contains(name) {
            guard enabledNames.count > 1 else { return }
            enabledNames.removeAll { $0 == name }
            filterNames.removeAll  { $0 == name }
            if filterNames.isEmpty, let first = enabledNames.first { filterNames = [first] }
        } else {
            enabledNames.append(name)
            filterNames.append(name)    // auto-add to filter when enabling
        }
        persist()
    }

    // MARK: - Toggle filter (from list filter bar)

    func toggleFilter(_ name: String) {
        let clickedLang = dictLangMap[name]   // nil = unassigned group

        if filterNames.contains(name) {
            guard filterNames.count > 1 else { return }
            filterNames.removeAll { $0 == name }
        } else {
            // If the clicked dict is from a different language group, clear the current selection
            let currentLangs = Set(filterNames.map { dictLangMap[$0] })
            if !currentLangs.isEmpty && !currentLangs.contains(clickedLang) {
                filterNames = [name]
            } else {
                filterNames.append(name)
            }
        }
        UserDefaults.standard.set(filterNames, forKey: Self.filterKey)
    }

    // MARK: - Dict language assignment

    func setDictLang(_ dictName: String, lang: String) {
        if lang.isEmpty {
            dictLangMap.removeValue(forKey: dictName)
        } else {
            dictLangMap[dictName] = lang
        }
        UserDefaults.standard.set(dictLangMap, forKey: "dictLangMap")
    }

    var isEmpty: Bool { allDicts.isEmpty }

    // MARK: - Import via Finder

    func importDict() {
        let panel = NSOpenPanel()
        panel.title               = "导入词典"
        panel.message             = "选择由 build_db.py 生成的 .sqlite 文件"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = false
        if let t = UTType(filenameExtension: "sqlite") { panel.allowedContentTypes = [t] }

        guard panel.runModal() == .OK else { return }

        let fm = FileManager.default
        for url in panel.urls {
            let dest = Self.dirURL.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: url, to: dest)
        }
        refresh()
    }

    // MARK: - Query

    func suggest(prefix: String, limit: Int = 50, filteredBy dicts: [String]? = nil) -> [String] {
        let targets = dicts ?? enabledNames
        var seen    = Set<String>()
        var result: [String] = []
        for name in targets {
            guard let store = stores[name] else { continue }
            for word in store.suggest(prefix: prefix, limit: limit) {
                if seen.insert(word.lowercased()).inserted {
                    result.append(word)
                    if result.count >= limit { return result }
                }
            }
        }
        return result
    }

    /// Which dicts among `dicts` actually have an entry for `word`
    func availableDicts(for word: String, among dicts: [String]) -> [String] {
        dicts.filter { stores[$0]?.contains(word) == true }
    }

    /// HTML from a specific dict
    func html(for word: String, in dictName: String) -> String? {
        stores[dictName]?.html(for: word)
    }

    /// Dict-specific CSS embedded at build time (nil if not present)
    func css(for dictName: String) -> String? {
        stores[dictName]?.css()
    }

    /// HTML from the first enabled dict that has the word (fallback)
    func html(for word: String) -> String? {
        for name in enabledNames {
            if let h = stores[name]?.html(for: word) { return h }
        }
        return nil
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(enabledNames, forKey: Self.enabledKey)
        UserDefaults.standard.set(filterNames,  forKey: Self.filterKey)
    }
}