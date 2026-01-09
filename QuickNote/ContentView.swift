import SwiftUI

struct ContentView: View {
    @ObservedObject var manager = DocumentManager.shared
    @FocusState private var isTextEditorFocused: Bool

    // Dark theme colors
    private let backgroundColor = Color(red: 0.129, green: 0.133, blue: 0.149) // #212226
    private let textColor = Color(red: 0.925, green: 0.937, blue: 0.957) // Nord snow storm #ECEFF4

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            // Editor
            if let document = manager.activeDocument {
                TextEditor(text: Binding(
                    get: { document.content },
                    set: { document.content = $0 }
                ))
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundColor(textColor)
                .scrollContentBackground(.hidden)
                .background(backgroundColor)
                .focused($isTextEditorFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 300, minHeight: 200)
        .onReceive(NotificationCenter.default.publisher(for: .focusTextEditor)) { _ in
            isTextEditorFocused = true
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextEditorFocused = true
            }
        }
    }
}

extension Notification.Name {
    static let focusTextEditor = Notification.Name("focusTextEditor")
    static let openSettings = Notification.Name("openSettings")
}
