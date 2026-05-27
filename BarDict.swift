
// BarDict.swift
import SwiftUI
import AppKit
import Carbon

@main
struct DictApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

// Subclass that lets us lock preferredContentSize during animation,
// preventing NSPopover's KVO handler from interrupting it.
private final class LockedHostingController<V: View>: NSHostingController<V> {
    var isLocked = false
    override var preferredContentSize: NSSize {
        get { super.preferredContentSize }
        set { if !isLocked { super.preferredContentSize = newValue } }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem:          NSStatusItem!
    private var popover:             NSPopover!
    private var hostingVC:           LockedHostingController<DictionaryPanel>!
    private var trackedHeight:       CGFloat = DictionaryPanel.listHeight
    private var previousInputSource:  String? = nil  // ID of source to restore on close
    private var hotkeyRef:            EventHotKeyRef?
    private var hotkeyEventHandler:   EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        hostingVC = LockedHostingController(
            rootView: DictionaryPanel(
                onDismiss:      { [weak self] in self?.popover.close() },
                onHeightChange: { [weak self] h in self?.resizePopover(to: h) },
                onDictChange:   { [weak self] name in self?.handleDictChange(name) }
            )
        )

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: DictionaryPanel.listHeight)
        popover.behavior = .transient
        popover.delegate  = self
        popover.contentViewController = hostingVC

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: NSEvent.EventTypeMask(arrayLiteral: .leftMouseUp, .rightMouseUp))
        }

        updateHotkey()
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showIconMenu(sender, event: event)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.close()
        } else {
            switchToTargetInputSource()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func showIconMenu(_ sender: NSStatusBarButton, event: NSEvent) {
        let menu = NSMenu()
        menu.appearance = NSApp.effectiveAppearance

        // Font size submenu
        let sizeSubmenu = NSMenu()
        let currentIdx = UserDefaults.standard.integer(forKey: "textSizeIndex")
        for (i, label) in ["100%", "110%", "120%", "130%", "140%"].enumerated() {
            let item = NSMenuItem(title: label, action: #selector(setFontSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (i == currentIdx) ? .on : .off
            sizeSubmenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: L.fontSize, action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeSubmenu
        menu.addItem(sizeItem)

        // Input source submenu
        let imSubmenu   = NSMenu()
        let currentIMID = UserDefaults.standard.string(forKey: "targetInputSourceID") ?? ""
        let noneItem    = NSMenuItem(title: L.noSwitch, action: #selector(setInputSource(_:)), keyEquivalent: "")
        noneItem.target = self
        noneItem.representedObject = ""
        noneItem.state = currentIMID.isEmpty ? .on : .off
        imSubmenu.addItem(noneItem)
        imSubmenu.addItem(.separator())
        let sources = availableInputSources()
        for (id, name) in sources {
            let item = NSMenuItem(title: name, action: #selector(setInputSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = (id == currentIMID) ? .on : .off
            imSubmenu.addItem(item)
        }
        imSubmenu.addItem(.separator())
        let byDictItem = NSMenuItem(title: L.byDictOption, action: #selector(setInputSource(_:)), keyEquivalent: "")
        byDictItem.target = self
        byDictItem.representedObject = "byDict"
        byDictItem.state = (currentIMID == "byDict") ? .on : .off
        imSubmenu.addItem(byDictItem)
        let imItem = NSMenuItem(title: L.switchIMEOnOpen, action: nil, keyEquivalent: "")
        imItem.submenu = imSubmenu
        menu.addItem(.separator())
        menu.addItem(imItem)

        // Language → IME submenu
        let langIMESubmenu = NSMenu()
        let langIMEMap = UserDefaults.standard.dictionary(forKey: "langInputSourceMap") as? [String: String] ?? [:]
        for lang in AppLang.allCases where lang != .auto {
            let langSubMenu   = NSMenu()
            let currentLangIM = langIMEMap[lang.rawValue] ?? ""
            let lnoneItem = NSMenuItem(title: L.noSwitch, action: #selector(setLangInputSource(_:)), keyEquivalent: "")
            lnoneItem.target = self
            lnoneItem.representedObject = ["lang": lang.rawValue, "source": ""] as NSDictionary
            lnoneItem.state = currentLangIM.isEmpty ? .on : .off
            langSubMenu.addItem(lnoneItem)
            langSubMenu.addItem(.separator())
            for (id, name) in sources {
                let item = NSMenuItem(title: name, action: #selector(setLangInputSource(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["lang": lang.rawValue, "source": id] as NSDictionary
                item.state = (id == currentLangIM) ? .on : .off
                langSubMenu.addItem(item)
            }
            let langItem = NSMenuItem(title: lang.displayName, action: nil, keyEquivalent: "")
            langItem.submenu = langSubMenu
            langIMESubmenu.addItem(langItem)
        }
        let langIMEItem = NSMenuItem(title: L.langIME, action: nil, keyEquivalent: "")
        langIMEItem.submenu = langIMESubmenu
        menu.addItem(langIMEItem)

        // Dict → Language submenu
        let dictLangSubmenu = NSMenu()
        let mgr0       = DictionaryManager.shared
        let dictLangMap = mgr0.dictLangMap
        if mgr0.enabledNames.isEmpty {
            let emptyItem = NSMenuItem(title: L.noDicts, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            dictLangSubmenu.addItem(emptyItem)
        } else {
            for dictName in mgr0.enabledNames {
                let perDictMenu  = NSMenu()
                let currentLang  = dictLangMap[dictName] ?? ""
                let dnoneItem = NSMenuItem(title: L.unassigned, action: #selector(setDictLang(_:)), keyEquivalent: "")
                dnoneItem.target = self
                dnoneItem.representedObject = ["dict": dictName, "lang": ""] as NSDictionary
                dnoneItem.state = currentLang.isEmpty ? .on : .off
                perDictMenu.addItem(dnoneItem)
                perDictMenu.addItem(.separator())
                for lang in AppLang.allCases where lang != .auto {
                    let item = NSMenuItem(title: lang.displayName, action: #selector(setDictLang(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = ["dict": dictName, "lang": lang.rawValue] as NSDictionary
                    item.state = (lang.rawValue == currentLang) ? .on : .off
                    perDictMenu.addItem(item)
                }
                let dictMenuItem = NSMenuItem(title: dictName, action: nil, keyEquivalent: "")
                dictMenuItem.submenu = perDictMenu
                dictLangSubmenu.addItem(dictMenuItem)
            }
        }
        let dictLangItem = NSMenuItem(title: L.dictLang, action: nil, keyEquivalent: "")
        dictLangItem.submenu = dictLangSubmenu
        menu.addItem(dictLangItem)
        menu.addItem(.separator())

        // Global hotkey submenu
        let hotkeySubmenu  = NSMenu()
        let hotkeyChoice   = UserDefaults.standard.string(forKey: "globalHotkeyChoice") ?? ""
        for (label, value) in [(L.hotkeyDisabled, ""), ("Shift+Space", "shift+space"), ("Option+Space", "option+space")] {
            let item = NSMenuItem(title: label, action: #selector(setHotkey(_:)), keyEquivalent: "")
            item.target            = self
            item.representedObject = value
            item.state             = (hotkeyChoice == value) ? .on : .off
            hotkeySubmenu.addItem(item)
        }
        let hotkeyItem = NSMenuItem(title: L.globalHotkey, action: nil, keyEquivalent: "")
        hotkeyItem.submenu = hotkeySubmenu
        menu.addItem(hotkeyItem)

        // Embedded CSS toggle
        let useCSS = UserDefaults.standard.object(forKey: "useEmbeddedCSS") as? Bool ?? true
        let cssItem = NSMenuItem(title: L.useEmbeddedCSS, action: #selector(toggleEmbeddedCSS), keyEquivalent: "")
        cssItem.target = self
        cssItem.state  = useCSS ? .on : .off
        menu.addItem(cssItem)

        // Language submenu
        let langSubmenu  = NSMenu()
        let currentLang  = UserDefaults.standard.string(forKey: "preferredLanguage") ?? ""
        for lang in AppLang.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target            = self
            item.representedObject = lang.rawValue
            item.state             = (currentLang == lang.rawValue) ? .on : .off
            langSubmenu.addItem(item)
        }
        let langItem = NSMenuItem(title: L.language, action: nil, keyEquivalent: "")
        langItem.submenu = langSubmenu
        menu.addItem(langItem)

        menu.addItem(.separator())

        // Import dict
        let importItem = NSMenuItem(title: L.importDict, action: #selector(importDict), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        // Dict selection submenu
        let dictSubmenu = NSMenu()
        let mgr = DictionaryManager.shared
        if mgr.allDicts.isEmpty {
            let empty = NSMenuItem(title: L.noDicts, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            dictSubmenu.addItem(empty)
        } else {
            for info in mgr.allDicts {
                let item = NSMenuItem(title: info.name, action: #selector(toggleDict(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = info.name
                item.state = mgr.enabledNames.contains(info.name) ? .on : .off
                dictSubmenu.addItem(item)
            }
        }
        let dictItem = NSMenuItem(title: L.selectDict, action: nil, keyEquivalent: "")
        dictItem.submenu = dictSubmenu
        menu.addItem(dictItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L.quit, action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func importDict() {
        let (sqliteURLs, mdxURLs) = DictionaryManager.shared.showImportPanel()
        DictionaryManager.shared.importSQLite(from: sqliteURLs)
        if !mdxURLs.isEmpty {
            convertMDXSequentially(queue: mdxURLs, index: 0)
        }
    }

    // MARK: - MDX conversion

    private var conversionProgressPanel: NSPanel?

    private func convertMDXSequentially(queue: [URL], index: Int) {
        guard index < queue.count else { return }
        let url = queue[index]

        let panel = makeProgressPanel(filename: url.lastPathComponent)
        panel.makeKeyAndOrderFront(nil)
        conversionProgressPanel = panel

        DictionaryManager.shared.convertMDX(at: url, progressHandler: { [weak panel] status in
            (panel?.contentView?.subviews
                .compactMap { $0 as? NSTextField }.first)?.stringValue = status
        }, completion: { [weak self, weak panel] result in
            panel?.close()
            self?.conversionProgressPanel = nil
            if case .failure(let error) = result {
                self?.showConvertError(error.message, filename: url.lastPathComponent)
            }
            self?.convertMDXSequentially(queue: queue, index: index + 1)
        })
    }

    private func makeProgressPanel(filename: String) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 72),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.center()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 72))

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.frame = NSRect(x: 20, y: 26, width: 20, height: 20)
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: L.converting(filename))
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 48, y: 27, width: 296, height: 18)

        container.addSubview(spinner)
        container.addSubview(label)
        panel.contentView?.addSubview(container)
        return panel
    }

    private func showConvertError(_ message: String, filename: String) {
        let alert = NSAlert()
        alert.messageText    = L.conversionFailed(filename)
        alert.alertStyle     = .critical
        alert.addButton(withTitle: L.ok)
        alert.addButton(withTitle: L.copyError)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 140))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 378, height: 138))
        textView.string          = message
        textView.isEditable      = false
        textView.isSelectable    = true
        textView.font            = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor       = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        scrollView.documentView  = textView

        alert.accessoryView = scrollView

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message, forType: .string)
        }
    }

    @objc private func toggleDict(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        DictionaryManager.shared.toggle(name)
    }

    @objc private func toggleEmbeddedCSS() {
        let current = UserDefaults.standard.object(forKey: "useEmbeddedCSS") as? Bool ?? true
        UserDefaults.standard.set(!current, forKey: "useEmbeddedCSS")
    }

    @objc private func setFontSize(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "textSizeIndex")
    }

    @objc private func setInputSource(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String ?? "", forKey: "targetInputSourceID")
    }

    @objc private func setDictLang(_ sender: NSMenuItem) {
        guard let repr = sender.representedObject as? NSDictionary,
              let dictName = repr["dict"] as? String,
              let lang     = repr["lang"] as? String else { return }
        DictionaryManager.shared.setDictLang(dictName, lang: lang)
    }

    @objc private func setLangInputSource(_ sender: NSMenuItem) {
        guard let repr     = sender.representedObject as? NSDictionary,
              let lang     = repr["lang"] as? String,
              let sourceID = repr["source"] as? String else { return }
        var map = UserDefaults.standard.dictionary(forKey: "langInputSourceMap") as? [String: String] ?? [:]
        if sourceID.isEmpty {
            map.removeValue(forKey: lang)
        } else {
            map[lang] = sourceID
        }
        UserDefaults.standard.set(map, forKey: "langInputSourceMap")
    }

    @objc private func setHotkey(_ sender: NSMenuItem) {
        let choice = sender.representedObject as? String ?? ""
        UserDefaults.standard.set(choice, forKey: "globalHotkeyChoice")
        updateHotkey()
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        let value = sender.representedObject as? String ?? ""
        UserDefaults.standard.set(value, forKey: "preferredLanguage")
    }

    // Sync popover.contentSize only when hidden, so showing it next time uses the right size.
    func popoverDidClose(_ notification: Notification) {
        popover.contentSize = NSSize(width: 360, height: trackedHeight)
        if let prev = previousInputSource {
            previousInputSource = nil
            restoreInputSource(id: prev)
        }
    }

    // Restores a CJK IME reliably by briefly bouncing through ABC first,
    // which forces the IME server to re-initialize and show candidate windows.
    private func restoreInputSource(id: String) {
        let needsBounce = !id.contains("Roman") && !id.contains(".ABC") && !id.contains("US")
        guard needsBounce else {
            selectInputSource(id: id)
            return
        }
        // Switch to ABC momentarily so the IME resets, then restore target after focus settles.
        if let abcID = availableInputSources().first(where: { $0.id.contains(".ABC.") || $0.id.contains("Roman") })?.id {
            selectInputSource(id: abcID)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.selectInputSource(id: id)
        }
    }

    // MARK: - Global hotkey (Shift+Space)

    private func updateHotkey() {
        unregisterHotkey()
        let choice = UserDefaults.standard.string(forKey: "globalHotkeyChoice") ?? ""
        guard !choice.isEmpty else { return }
        registerHotkey(modifier: choice == "option+space" ? UInt32(optionKey) : UInt32(shiftKey))
    }

    private func registerHotkey(modifier: UInt32) {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                DispatchQueue.main.async {
                    if let button = delegate.statusItem.button {
                        delegate.togglePopover(button)
                    }
                }
                return noErr
            },
            1, &eventSpec, selfPtr, &hotkeyEventHandler
        )

        var hkID = EventHotKeyID()
        hkID.signature = 0x42444B54  // 'BDKT'
        hkID.id = 1
        RegisterEventHotKey(49, modifier, hkID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    private func unregisterHotkey() {
        if let ref = hotkeyRef     { UnregisterEventHotKey(ref); hotkeyRef = nil }
        if let hdl = hotkeyEventHandler { RemoveEventHandler(hdl); hotkeyEventHandler = nil }
    }

    // MARK: - Input source helpers

    private func tisString(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func availableInputSources() -> [(id: String, name: String)] {
        let props = [kTISPropertyInputSourceIsEnabled: true,
                     kTISPropertyInputSourceIsSelectCapable: true] as CFDictionary
        guard let cf = TISCreateInputSourceList(props, false) else { return [] }
        let list = cf.takeRetainedValue() as! [TISInputSource]
        return list.compactMap { src in
            guard tisString(src, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String),
                  let id   = tisString(src, kTISPropertyInputSourceID),
                  let name = tisString(src, kTISPropertyLocalizedName)
            else { return nil }
            return (id: id, name: name)
        }
    }

    private func currentInputSourceID() -> String? {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return tisString(src, kTISPropertyInputSourceID)
    }

    private func selectInputSource(id: String) {
        let props = [kTISPropertyInputSourceID: id] as CFDictionary
        guard let cf = TISCreateInputSourceList(props, false),
              let src = (cf.takeRetainedValue() as! [TISInputSource]).first
        else { return }
        TISSelectInputSource(src)
    }

    private func switchToTargetInputSource() {
        let targetID = UserDefaults.standard.string(forKey: "targetInputSourceID") ?? ""
        guard !targetID.isEmpty else { return }
        previousInputSource = currentInputSourceID()
        if targetID == "byDict" {
            // Switch based on the language of the currently active filter group
            if let firstDict = DictionaryManager.shared.filterNames.first {
                handleDictChange(firstDict)
            }
        } else {
            selectInputSource(id: targetID)
        }
    }

    private func handleDictChange(_ dictName: String) {
        guard UserDefaults.standard.string(forKey: "targetInputSourceID") == "byDict" else { return }
        guard let lang = DictionaryManager.shared.dictLangMap[dictName], !lang.isEmpty else { return }
        let langIMEMap = UserDefaults.standard.dictionary(forKey: "langInputSourceMap") as? [String: String] ?? [:]
        guard let imID = langIMEMap[lang], !imID.isEmpty else { return }
        selectInputSource(id: imID)
    }

    private func resizePopover(to height: CGFloat) {
        let delta = height - trackedHeight
        guard abs(delta) > 1 else { return }
        trackedHeight = height

        guard popover.isShown, let window = hostingVC.view.window else {
            // Popover not visible — just update stored size directly.
            popover.contentSize = NSSize(width: 360, height: height)
            return
        }

        hostingVC.isLocked = true

        let fromFrame = window.frame
        let toFrame   = NSRect(x: fromFrame.minX, y: fromFrame.minY - delta,
                               width: fromFrame.width, height: fromFrame.height + delta)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            window.animator().setFrame(toFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.hostingVC.isLocked = false
        })
    }
}