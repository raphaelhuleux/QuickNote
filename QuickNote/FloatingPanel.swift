import AppKit
import SwiftUI

class FloatingPanel: NSPanel, NSToolbarDelegate {
    private let tabBarIdentifier = NSToolbarItem.Identifier("TabBar")
    private var tabBarHostingView: NSHostingView<TabBarView>?

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Floating behavior
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false

        // Appearance - Dark theme
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = NSColor(red: 0.129, green: 0.133, blue: 0.149, alpha: 1.0) // #212226

        // Allow it to become key window for text input
        isMovableByWindowBackground = true

        // Set minimum size
        minSize = NSSize(width: 300, height: 200)

        // Set content
        self.contentView = contentView

        // Setup toolbar for tabs in title bar
        setupToolbar()

        // Center on screen
        center()
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "QuickNoteToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false

        self.toolbar = toolbar
        self.toolbarStyle = .unifiedCompact
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == tabBarIdentifier {
            let item = NSToolbarItem(itemIdentifier: tabBarIdentifier)

            let tabBarView = TabBarView(manager: DocumentManager.shared)
            let hostingView = NSHostingView(rootView: tabBarView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 28)

            item.view = hostingView
            item.minSize = NSSize(width: 200, height: 28)
            item.maxSize = NSSize(width: 2000, height: 28)

            tabBarHostingView = hostingView

            return item
        }
        return nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [tabBarIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [tabBarIdentifier]
    }

    // Allow the panel to become key window (for text input)
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Close the panel when pressing Escape
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    // MARK: - Keyboard Shortcuts

    // Intercept keyboard shortcuts BEFORE they reach TextEditor
    // Using sendEvent to catch events before they go to the view hierarchy
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let hasShift = event.modifierFlags.contains(.shift)

            var handled = true
            switch (key, hasShift) {
            case ("n", false):
                DocumentManager.shared.newDocument()
            case ("o", false):
                DocumentManager.shared.openDocument()
            case ("s", false):
                DocumentManager.shared.saveActiveDocument()
            case ("s", true):
                DocumentManager.shared.saveActiveDocumentAs()
            case ("w", false):
                DocumentManager.shared.closeActiveDocument()
            case (",", false):
                NotificationCenter.default.post(name: .openSettings, object: nil)
            case ("]", true):
                DocumentManager.shared.nextTab()
            case ("[", true):
                DocumentManager.shared.previousTab()
            default:
                handled = false
            }

            if handled {
                return // Don't pass to super, we handled it
            }
        }

        super.sendEvent(event)
    }
}
