import AppKit
import SwiftUI
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var contentView: ContentView?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupStatusBarItem()
        setupKeyboardShortcut()
        setupMainMenu()

        // Listen for openSettings notification from FloatingPanel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettings,
            object: nil
        )
    }

    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        DocumentManager.shared.openFile(at: filename)
        showPanel()
        return true
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            DocumentManager.shared.openFile(at: filename)
        }
        showPanel()
    }

    private func setupPanel() {
        contentView = ContentView()
        let hostingView = NSHostingView(rootView: contentView!)
        panel = FloatingPanel(contentView: hostingView)
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "QuickNote")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show QuickNote", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "New", action: #selector(newTab), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Open File...", action: #selector(openFile), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "w"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Save", action: #selector(saveFile), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit QuickNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func setupMainMenu() {
        // Add keyboard shortcuts via main menu
        let mainMenu = NSMenu()

        // App menu (required - first item is always app menu)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "QuickNote")
        appMenu.addItem(NSMenuItem(title: "About QuickNote", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide QuickNote", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Quit QuickNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")

        let newItem = NSMenuItem(title: "New", action: #selector(newTab), keyEquivalent: "n")
        newItem.target = self
        fileMenu.addItem(newItem)

        let openItem = NSMenuItem(title: "Open...", action: #selector(openFile), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        fileMenu.addItem(NSMenuItem.separator())

        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "w")
        closeItem.target = self
        fileMenu.addItem(closeItem)

        fileMenu.addItem(NSMenuItem.separator())

        let saveItem = NSMenuItem(title: "Save", action: #selector(saveFile), keyEquivalent: "s")
        saveItem.target = self
        fileMenu.addItem(saveItem)

        let saveAsItem = NSMenuItem(title: "Save As...", action: #selector(saveFileAs), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.target = self
        fileMenu.addItem(saveAsItem)

        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu (required for text editing shortcuts like Cmd+C, Cmd+V to work)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu (for tab navigation)
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        let nextTabItem = NSMenuItem(title: "Next Tab", action: #selector(nextTab), keyEquivalent: "]")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        nextTabItem.target = self
        viewMenu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(title: "Previous Tab", action: #selector(previousTab), keyEquivalent: "[")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        prevTabItem.target = self
        viewMenu.addItem(prevTabItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupKeyboardShortcut() {
        // Cmd + Option + Ctrl + O (global hotkey)
        hotKey = HotKey(key: .o, modifiers: [.command, .option, .control])
        hotKey?.keyDownHandler = { [weak self] in
            self?.togglePanel()
        }
    }

    @objc private func togglePanel() {
        guard let panel = panel else { return }

        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    @objc private func showPanel() {
        guard let panel = panel else { return }

        // Use accessory policy to stay out of dock while still receiving focus
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        panel.makeKeyAndOrderFront(nil)

        // Post notification to focus the text editor in SwiftUI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .focusTextEditor, object: nil)
        }
    }

    @objc private func newTab() {
        DocumentManager.shared.newDocument()
    }

    @objc private func openFile() {
        DocumentManager.shared.openDocument()
    }

    @objc private func closeTab() {
        DocumentManager.shared.closeActiveDocument()
    }

    @objc private func saveFile() {
        DocumentManager.shared.saveActiveDocument()
    }

    @objc private func saveFileAs() {
        DocumentManager.shared.saveActiveDocumentAs()
    }

    @objc private func nextTab() {
        DocumentManager.shared.nextTab()
    }

    @objc private func previousTab() {
        DocumentManager.shared.previousTab()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)

            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Settings"
            settingsWindow?.styleMask = [.titled, .closable]
            settingsWindow?.setContentSize(NSSize(width: 450, height: 280))
        }

        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
