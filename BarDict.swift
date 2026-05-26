
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
                onHeightChange: { [weak self] h in self?.resizePopover(to: h) }
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
        let sizeItem = NSMenuItem(title: "字体大小", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeSubmenu
        menu.addItem(sizeItem)

        // Input source submenu
        let imSubmenu   = NSMenu()
        let currentIMID = UserDefaults.standard.string(forKey: "targetInputSourceID") ?? ""
        let noneItem    = NSMenuItem(title: "不切换", action: #selector(setInputSource(_:)), keyEquivalent: "")
        noneItem.target = self
        noneItem.representedObject = ""
        noneItem.state = currentIMID.isEmpty ? .on : .off
        imSubmenu.addItem(noneItem)
        imSubmenu.addItem(.separator())
        for (id, name) in availableInputSources() {
            let item = NSMenuItem(title: name, action: #selector(setInputSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = (id == currentIMID) ? .on : .off
            imSubmenu.addItem(item)
        }
        let imItem = NSMenuItem(title: "打开时切换输入法", action: nil, keyEquivalent: "")
        imItem.submenu = imSubmenu
        menu.addItem(imItem)

        // Global hotkey submenu
        let hotkeySubmenu  = NSMenu()
        let hotkeyChoice   = UserDefaults.standard.string(forKey: "globalHotkeyChoice") ?? ""
        for (label, value) in [("不使用", ""), ("Shift+Space", "shift+space"), ("Option+Space", "option+space")] {
            let item = NSMenuItem(title: label, action: #selector(setHotkey(_:)), keyEquivalent: "")
            item.target            = self
            item.representedObject = value
            item.state             = (hotkeyChoice == value) ? .on : .off
            hotkeySubmenu.addItem(item)
        }
        let hotkeyItem = NSMenuItem(title: "全局快捷键", action: nil, keyEquivalent: "")
        hotkeyItem.submenu = hotkeySubmenu
        menu.addItem(hotkeyItem)

        // Embedded CSS toggle
        let useCSS = UserDefaults.standard.object(forKey: "useEmbeddedCSS") as? Bool ?? true
        let cssItem = NSMenuItem(title: "使用词典内嵌样式", action: #selector(toggleEmbeddedCSS), keyEquivalent: "")
        cssItem.target = self
        cssItem.state  = useCSS ? .on : .off
        menu.addItem(cssItem)

        menu.addItem(.separator())

        // Import dict
        let importItem = NSMenuItem(title: "导入词典…", action: #selector(importDict), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        // Dict selection submenu
        let dictSubmenu = NSMenu()
        let mgr = DictionaryManager.shared
        if mgr.allDicts.isEmpty {
            let empty = NSMenuItem(title: "暂无词典", action: nil, keyEquivalent: "")
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
        let dictItem = NSMenuItem(title: "词典选择", action: nil, keyEquivalent: "")
        dictItem.submenu = dictSubmenu
        menu.addItem(dictItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func importDict() {
        DictionaryManager.shared.importDict()
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

    @objc private func setHotkey(_ sender: NSMenuItem) {
        let choice = sender.representedObject as? String ?? ""
        UserDefaults.standard.set(choice, forKey: "globalHotkeyChoice")
        updateHotkey()
    }

    // Sync popover.contentSize only when hidden, so showing it next time uses the right size.
    func popoverDidClose(_ notification: Notification) {
        popover.contentSize = NSSize(width: 360, height: trackedHeight)
        if let prev = previousInputSource {
            selectInputSource(id: prev)
            previousInputSource = nil
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
        selectInputSource(id: targetID)
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