import SwiftUI
import AppKit

class AutoContinueTextView: NSTextView {

    // Handle special key presses
    override func keyDown(with event: NSEvent) {
        // Tab key (keyCode 48)
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) {
                handleUnindent()
            } else {
                handleIndent()
            }
            return
        }

        // Return/Enter key (keyCode 36 = Return, 76 = Enter on numpad)
        if event.keyCode == 36 || event.keyCode == 76 {
            handleNewline()
            return
        }
        super.keyDown(with: event)
    }

    private func handleNewline() {
        guard let textStorage = self.textStorage else {
            insertNewlineCharacter()
            return
        }

        let text = textStorage.string as NSString
        let cursorLocation = selectedRange().location

        // Get the current line range and strip any trailing newline
        let lineRange = text.lineRange(for: NSRange(location: cursorLocation, length: 0))
        var currentLine = text.substring(with: lineRange)

        // Remove trailing newline if present
        if currentLine.hasSuffix("\n") {
            currentLine = String(currentLine.dropLast())
        }

        // Check for bullet points: "- " or "* " at start (with optional leading whitespace)
        if let bulletMatch = currentLine.range(of: #"^(\s*[-*] )"#, options: .regularExpression) {
            let bulletPrefix = String(currentLine[bulletMatch])
            let contentAfterBullet = String(currentLine[bulletMatch.upperBound...]).trimmingCharacters(in: .whitespaces)

            if contentAfterBullet.isEmpty {
                // Empty bullet - remove it and just add newline
                let rangeToDelete = NSRange(location: lineRange.location, length: currentLine.count)
                if shouldChangeText(in: rangeToDelete, replacementString: "") {
                    textStorage.replaceCharacters(in: rangeToDelete, with: "")
                    setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    didChangeText()
                }
            } else {
                // Continue the bullet
                insertNewlineCharacter()
                insertText(bulletPrefix, replacementRange: selectedRange())
            }
            return
        }

        // Check for numbered lists: "1. " or "1) " at start (with optional leading whitespace)
        if let numberMatch = currentLine.range(of: #"^(\s*)(\d+)([.)] )"#, options: .regularExpression) {
            // Extract the full prefix and components
            let fullPrefix = String(currentLine[numberMatch])
            let contentAfterNumber = String(currentLine[numberMatch.upperBound...]).trimmingCharacters(in: .whitespaces)

            // Parse out the number
            if let numMatch = currentLine.range(of: #"\d+"#, options: .regularExpression) {
                let numberStr = String(currentLine[numMatch])

                if contentAfterNumber.isEmpty {
                    // Empty numbered item - remove it
                    let rangeToDelete = NSRange(location: lineRange.location, length: currentLine.count)
                    if shouldChangeText(in: rangeToDelete, replacementString: "") {
                        textStorage.replaceCharacters(in: rangeToDelete, with: "")
                        setSelectedRange(NSRange(location: lineRange.location, length: 0))
                        didChangeText()
                    }
                } else if let number = Int(numberStr) {
                    // Continue with next number
                    let nextNumber = number + 1
                    // Replace the number in the prefix
                    let nextPrefix = fullPrefix.replacingOccurrences(of: numberStr, with: String(nextNumber))
                    insertNewlineCharacter()
                    insertText(nextPrefix, replacementRange: selectedRange())
                } else {
                    insertNewlineCharacter()
                }
                return
            }
        }

        // Default: just insert newline
        insertNewlineCharacter()
    }

    private func insertNewlineCharacter() {
        insertText("\n", replacementRange: selectedRange())
    }

    private func handleIndent() {
        guard let textStorage = self.textStorage else {
            insertText("\t", replacementRange: selectedRange())
            return
        }

        let text = textStorage.string as NSString
        let cursorLocation = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: cursorLocation, length: 0))
        var currentLine = text.substring(with: lineRange)

        // Remove trailing newline if present
        let hasNewline = currentLine.hasSuffix("\n")
        if hasNewline {
            currentLine = String(currentLine.dropLast())
        }

        // Check for bullet points: "- " or "* " at start (with optional leading whitespace)
        if currentLine.range(of: #"^\s*[-*] "#, options: .regularExpression) != nil {
            // Insert tab at line start
            let insertRange = NSRange(location: lineRange.location, length: 0)
            if shouldChangeText(in: insertRange, replacementString: "\t") {
                textStorage.replaceCharacters(in: insertRange, with: "\t")
                setSelectedRange(NSRange(location: cursorLocation + 1, length: 0))
                didChangeText()
            }
            return
        }

        // Check for numbered lists: "1. " or "1) " at start (with optional leading whitespace)
        if let numberMatch = currentLine.range(of: #"^(\s*)(\d+)([.)] )"#, options: .regularExpression) {
            // For numbered list: insert tab and reset number to 1
            let existingIndent = String(currentLine[currentLine.startIndex..<numberMatch.lowerBound])
            let numRange = currentLine.range(of: #"\d+"#, options: .regularExpression)!
            let suffix = String(currentLine[numRange.upperBound..<numberMatch.upperBound])
            let content = String(currentLine[numberMatch.upperBound...])
            let newLine = "\t" + existingIndent + "1" + suffix + content

            let replaceRange = NSRange(location: lineRange.location, length: currentLine.count)
            if shouldChangeText(in: replaceRange, replacementString: newLine) {
                textStorage.replaceCharacters(in: replaceRange, with: newLine)
                // Position cursor at end of line
                setSelectedRange(NSRange(location: lineRange.location + newLine.count, length: 0))
                didChangeText()
            }
            return
        }

        // Normal tab insert at cursor
        insertText("\t", replacementRange: selectedRange())
    }

    private func handleUnindent() {
        guard let textStorage = self.textStorage else { return }

        let text = textStorage.string as NSString
        let cursorLocation = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: cursorLocation, length: 0))
        var currentLine = text.substring(with: lineRange)

        // Remove trailing newline if present
        let hasNewline = currentLine.hasSuffix("\n")
        if hasNewline {
            currentLine = String(currentLine.dropLast())
        }

        // Check if line starts with a tab or spaces
        var indentToRemove = ""
        if currentLine.hasPrefix("\t") {
            indentToRemove = "\t"
        } else if currentLine.hasPrefix("    ") {
            indentToRemove = "    "
        } else if currentLine.hasPrefix("  ") {
            indentToRemove = "  "
        } else {
            // No indentation to remove
            return
        }

        // Remove the indentation
        let newLine = String(currentLine.dropFirst(indentToRemove.count))

        // For numbered lists, also reset to 1
        var finalLine = newLine
        if let numberMatch = newLine.range(of: #"^(\s*)(\d+)([.)] )"#, options: .regularExpression) {
            let existingIndent = String(newLine[newLine.startIndex..<numberMatch.lowerBound])
            let numRange = newLine.range(of: #"\d+"#, options: .regularExpression)!
            let suffix = String(newLine[numRange.upperBound..<numberMatch.upperBound])
            let content = String(newLine[numberMatch.upperBound...])
            finalLine = existingIndent + "1" + suffix + content
        }

        let replaceRange = NSRange(location: lineRange.location, length: currentLine.count)
        if shouldChangeText(in: replaceRange, replacementString: finalLine) {
            textStorage.replaceCharacters(in: replaceRange, with: finalLine)
            // Adjust cursor position
            let newCursorPos = max(lineRange.location, cursorLocation - indentToRemove.count)
            setSelectedRange(NSRange(location: newCursorPos, length: 0))
            didChangeText()
        }
    }
}

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var backgroundColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = AutoContinueTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
        textView.insertionPointColor = textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 16, height: 12)

        // Configure text container for proper wrapping
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.delegate = context.coordinator

        scrollView.documentView = textView

        // Store reference for focus handling
        context.coordinator.textView = textView

        // Listen for focus notification
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.focusTextView),
            name: .focusTextEditor,
            object: nil
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if text differs to avoid cursor jumping
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        @objc func focusTextView() {
            DispatchQueue.main.async { [weak self] in
                guard let textView = self?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
