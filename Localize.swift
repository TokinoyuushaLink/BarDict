
// Localize.swift
import Foundation

enum AppLang: String, CaseIterable {
    case auto = ""
    case zh   = "zh"
    case en   = "en"
    case ja   = "ja"
    case de   = "de"
    case es   = "es"

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .zh:   return "中文"
        case .en:   return "English"
        case .ja:   return "日本語"
        case .de:   return "Deutsch"
        case .es:   return "Español"
        }
    }
}

enum L {
    static var current: AppLang {
        let pref = UserDefaults.standard.string(forKey: "preferredLanguage") ?? ""
        if let lang = AppLang(rawValue: pref), lang != .auto { return lang }
        let sys = Locale.current.language.languageCode?.identifier ?? "en"
        return AppLang(rawValue: sys) ?? .en
    }

    // MARK: - Menu items

    static var language: String {
        switch current {
        case .zh: return "语言"
        case .ja: return "言語"
        case .de: return "Sprache"
        case .es: return "Idioma"
        default:  return "Language"
        }
    }

    static var fontSize: String {
        switch current {
        case .zh: return "字体大小"
        case .ja: return "フォントサイズ"
        case .de: return "Schriftgröße"
        case .es: return "Tamaño de fuente"
        default:  return "Font Size"
        }
    }

    static var noSwitch: String {
        switch current {
        case .zh: return "不切换"
        case .ja: return "切り替えない"
        case .de: return "Nicht wechseln"
        case .es: return "No cambiar"
        default:  return "Don't Switch"
        }
    }

    static var switchIMEOnOpen: String {
        switch current {
        case .zh: return "打开时切换输入法"
        case .ja: return "起動時に入力方法を切替"
        case .de: return "Eingabemethode beim Öffnen wechseln"
        case .es: return "Cambiar método de entrada al abrir"
        default:  return "Switch Input Method on Open"
        }
    }

    static var byDictOption: String {
        switch current {
        case .zh: return "根据词典语言"
        case .ja: return "辞書の言語に合わせる"
        case .de: return "Nach Wörterbuchsprache"
        case .es: return "Según idioma del diccionario"
        default:  return "By Dictionary Language"
        }
    }

    static var dictLang: String {
        switch current {
        case .zh: return "词典语言"
        case .ja: return "辞書の言語"
        case .de: return "Wörterbuchsprache"
        case .es: return "Idioma del diccionario"
        default:  return "Dictionary Language"
        }
    }

    static var langIME: String {
        switch current {
        case .zh: return "语言输入法"
        case .ja: return "言語の入力方法"
        case .de: return "Sprach-Eingabemethode"
        case .es: return "Método de entrada por idioma"
        default:  return "Language Input Method"
        }
    }

    static var unassigned: String {
        switch current {
        case .zh: return "未分类"
        case .ja: return "未分類"
        case .de: return "Nicht zugeordnet"
        case .es: return "Sin clasificar"
        default:  return "Unassigned"
        }
    }

    static var hotkeyDisabled: String {
        switch current {
        case .zh: return "不使用"
        case .ja: return "無効"
        case .de: return "Deaktiviert"
        case .es: return "Desactivado"
        default:  return "Disabled"
        }
    }

    static var globalHotkey: String {
        switch current {
        case .zh: return "全局快捷键"
        case .ja: return "グローバルショートカット"
        case .de: return "Globaler Hotkey"
        case .es: return "Atajo global"
        default:  return "Global Hotkey"
        }
    }

    static var useEmbeddedCSS: String {
        switch current {
        case .zh: return "使用词典内嵌样式"
        case .ja: return "辞書のスタイルを使用"
        case .de: return "Wörterbuch-CSS verwenden"
        case .es: return "Usar CSS del diccionario"
        default:  return "Use Dictionary CSS"
        }
    }

    static var importDict: String {
        switch current {
        case .zh: return "导入词典…"
        case .ja: return "辞書をインポート…"
        case .de: return "Wörterbuch importieren…"
        case .es: return "Importar diccionario…"
        default:  return "Import Dictionary…"
        }
    }

    static var noDicts: String {
        switch current {
        case .zh: return "暂无词典"
        case .ja: return "辞書がありません"
        case .de: return "Keine Wörterbücher"
        case .es: return "Sin diccionarios"
        default:  return "No Dictionaries"
        }
    }

    static var selectDict: String {
        switch current {
        case .zh: return "词典选择"
        case .ja: return "辞書を選択"
        case .de: return "Wörterbuch wählen"
        case .es: return "Seleccionar diccionario"
        default:  return "Select Dictionary"
        }
    }

    static var quit: String {
        switch current {
        case .zh: return "退出"
        case .ja: return "終了"
        case .de: return "Beenden"
        case .es: return "Salir"
        default:  return "Quit"
        }
    }

    // MARK: - Conversion panel

    static func converting(_ filename: String) -> String {
        switch current {
        case .zh: return "正在转换 \(filename)…"
        case .ja: return "\(filename) を変換中…"
        case .de: return "\(filename) wird konvertiert…"
        case .es: return "Convirtiendo \(filename)…"
        default:  return "Converting \(filename)…"
        }
    }

    static func conversionFailed(_ filename: String) -> String {
        switch current {
        case .zh: return "「\(filename)」转换失败"
        case .ja: return "「\(filename)」の変換に失敗"
        case .de: return "Konvertierung von \(filename) fehlgeschlagen"
        case .es: return "Error al convertir \(filename)"
        default:  return "Failed to Convert \(filename)"
        }
    }

    static var ok: String {
        switch current {
        case .zh: return "好"
        default:  return "OK"
        }
    }

    static var copyError: String {
        switch current {
        case .zh: return "复制错误信息"
        case .ja: return "エラーをコピー"
        case .de: return "Fehler kopieren"
        case .es: return "Copiar error"
        default:  return "Copy Error"
        }
    }

    // MARK: - Search panel

    static var searchPlaceholder: String {
        switch current {
        case .zh: return "搜索单词"
        case .ja: return "単語を検索"
        case .de: return "Suchen"
        case .es: return "Buscar"
        default:  return "Search"
        }
    }

    static var recentSearches: String {
        switch current {
        case .zh: return "最近查询"
        case .ja: return "最近"
        case .de: return "Zuletzt"
        case .es: return "Reciente"
        default:  return "Recent"
        }
    }

    static var noDictImported: String {
        switch current {
        case .zh: return "尚未导入词典"
        case .ja: return "辞書が未インポート"
        case .de: return "Kein Wörterbuch importiert"
        case .es: return "Sin diccionario importado"
        default:  return "No Dictionary Imported"
        }
    }

    static var importHint: String {
        switch current {
        case .zh: return "右键点击菜单栏图标，选择「导入词典」"
        case .ja: return "メニューバーアイコンを右クリックし\n「辞書をインポート」を選択"
        case .de: return "Rechtsklick auf das Menüleistensymbol\nund \"Wörterbuch importieren\" wählen"
        case .es: return "Clic derecho en el icono de la barra de menús\ny selecciona \"Importar diccionario\""
        default:  return "Right-click the menu bar icon\nand select \"Import Dictionary\""
        }
    }

    static var openDictFolder: String {
        switch current {
        case .zh: return "打开词典目录"
        case .ja: return "辞書フォルダを開く"
        case .de: return "Wörterbuchordner öffnen"
        case .es: return "Abrir carpeta de diccionarios"
        default:  return "Open Dictionary Folder"
        }
    }

    static var typeToSearch: String {
        switch current {
        case .zh: return "输入单词查询"
        case .ja: return "単語を入力して検索"
        case .de: return "Wort eingeben und nachschlagen"
        case .es: return "Escribe una palabra para buscar"
        default:  return "Type a word to look up"
        }
    }

    static var noFilterSelected: String {
        switch current {
        case .zh: return "未启用任何过滤"
        case .ja: return "フィルターなし"
        case .de: return "Kein Filter ausgewählt"
        case .es: return "Sin filtro seleccionado"
        default:  return "No filter selected"
        }
    }
}