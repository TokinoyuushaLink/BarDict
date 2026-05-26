
// DictStore.swift
import Foundation
import SQLite3

// SQLite 绑定文本时需要这个,告诉 SQLite 拷贝字符串(否则 Swift 字符串可能提前释放)
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DictionaryStore {
    private var db: OpaquePointer?

    init?(path: String) {
        guard !path.isEmpty else { return nil }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// 前缀匹配,出候选列表
    func suggest(prefix: String, limit: Int = 50) -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let sql = """
        SELECT DISTINCT word FROM entries
        WHERE word LIKE ? COLLATE NOCASE
        ORDER BY length(word), word
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        // LIKE 的特殊字符 % _ 要转义,避免用户输入 % 时匹配异常
        let escaped = trimmed
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = escaped + "%"

        sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: c))
            }
        }
        return results
    }

    /// 读取词典附属 CSS（存储在 meta 表中，旧格式词典无此表时返回 nil）
    func css() -> String? {
        let sql = "SELECT value FROM meta WHERE key = 'css' LIMIT 1;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW,
              let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    /// 取某个词的完整 html,处理 @@@LINK 重定向
    func html(for word: String, depth: Int = 0) -> String? {
        guard depth < 5 else { return nil }   // 防循环重定向

        let sql = "SELECT html FROM entries WHERE word = ? COLLATE NOCASE LIMIT 1;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }

        sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let c = sqlite3_column_text(stmt, 0) else { return nil }
        let raw = String(cString: c)

        // 处理重定向条目 @@@LINK=目标词
        if raw.hasPrefix("@@@LINK=") {
            let target = raw
                .replacingOccurrences(of: "@@@LINK=", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return html(for: target, depth: depth + 1)
        }
        return raw
    }
}
