import SwiftUI

struct ContentView: View {
    @ObservedObject var manager = DocumentManager.shared

    // Dark theme colors
    private let backgroundColor = Color(red: 0.129, green: 0.133, blue: 0.149) // #212226
    private let textColor = Color(red: 0.925, green: 0.937, blue: 0.957) // Nord snow storm #ECEFF4

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            // Editor
            if let document = manager.activeDocument {
                MarkdownTextView(
                    text: Binding(
                        get: { document.content },
                        set: { document.content = $0 }
                    ),
                    font: .monospacedSystemFont(ofSize: 15, weight: .regular),
                    textColor: NSColor(red: 0.925, green: 0.937, blue: 0.957, alpha: 1.0),
                    backgroundColor: NSColor(red: 0.129, green: 0.133, blue: 0.149, alpha: 1.0)
                )
            }
        }
        .frame(minWidth: 300, minHeight: 200)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .focusTextEditor, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let focusTextEditor = Notification.Name("focusTextEditor")
    static let openSettings = Notification.Name("openSettings")
}
