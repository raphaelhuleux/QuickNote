import AppKit

// Use traditional AppKit main instead of SwiftUI App lifecycle
// This gives us proper control over keyboard shortcuts and file opening

@main
struct QuickNoteMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
