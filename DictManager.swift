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
            newStores[info.name] = stores[info.name] ?? DictionaryStore(path: info.url.path)
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
        if filterNames.contains(name) {
            guard filterNames.count > 1 else { return }
            filterNames.removeAll { $0 == name }
        } else {
            filterNames.append(name)
        }
        UserDefaults.standard.set(filterNames, forKey: Self.filterKey)
    }

    var isEmpty: Bool { allDicts.isEmpty }

    // MARK: - Import via Finder

    /// Shows a file picker for .sqlite and .mdx files.
    /// Returns selected URLs separated by type; does NOT import or convert anything.
    func showImportPanel() -> (sqlite: [URL], mdx: [URL]) {
        let panel = NSOpenPanel()
        panel.title   = "导入词典"
        panel.message = "选择 .mdx 词典文件或已转换的 .sqlite 文件"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = false
        var types: [UTType] = []
        if let t = UTType(filenameExtension: "sqlite") { types.append(t) }
        if let t = UTType(filenameExtension: "mdx")    { types.append(t) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK else { return ([], []) }
        let sqlite = panel.urls.filter { $0.pathExtension.lowercased() == "sqlite" }
        let mdx    = panel.urls.filter { $0.pathExtension.lowercased() == "mdx" }
        return (sqlite, mdx)
    }

    func importSQLite(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        let fm = FileManager.default
        for url in urls {
            let dest = Self.dirURL.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: url, to: dest)
        }
        refresh()
    }

    // MARK: - MDX conversion

    enum ConverterError: Error {
        case binaryNotFound
        case processFailed(String)

        var message: String {
            switch self {
            case .binaryNotFound:
                return "找不到内置转换器（Resources/converter/mdx2db）。\n请重新运行 ./build.sh 构建应用。"
            case .processFailed(let output):
                return output.isEmpty ? "转换进程异常退出，无错误输出。" : output
            }
        }
    }

    /// Runs the bundled mdx2db converter in the background.
    /// Calls progressHandler on main thread with each output line.
    /// Calls completion on main thread when finished.
    func convertMDX(at url: URL,
                    progressHandler: @escaping (String) -> Void,
                    completion: @escaping (Result<Void, ConverterError>) -> Void) {
        let resourcesURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources")
        let converterURL = resourcesURL.appendingPathComponent("converter/mdx2db")

        guard FileManager.default.fileExists(atPath: converterURL.path) else {
            completion(.failure(.binaryNotFound))
            return
        }

        let outputURL = Self.dirURL
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".sqlite")

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = converterURL
            process.arguments     = [url.path, outputURL.path]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError  = errPipe

            var collectedOutput: [String] = []

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                guard let line = String(data: handle.availableData, encoding: .utf8) else { return }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                collectedOutput.append(trimmed)
                DispatchQueue.main.async { progressHandler(trimmed) }
            }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.processFailed(error.localizedDescription)))
                }
                return
            }

            outPipe.fileHandleForReading.readabilityHandler = nil
            let errData   = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errString = String(data: errData, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                DispatchQueue.main.async {
                    self.refresh()
                    completion(.success(()))
                }
            } else {
                let combined = (collectedOutput + [errString])
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async { completion(.failure(.processFailed(combined))) }
            }
        }
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
        dicts.filter { stores[$0]?.html(for: word) != nil }
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