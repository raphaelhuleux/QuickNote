import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

class NoteStorage: ObservableObject {
    @Published var content: String = ""
    @Published var filePath: String {
        didSet {
            UserDefaults.standard.set(filePath, forKey: "noteFilePath")
            loadNote()
        }
    }

    private var saveTask: Task<Void, Never>?
    private var isLoading = false

    static let shared = NoteStorage()

    private init() {
        // Load saved file path or use default
        if let savedPath = UserDefaults.standard.string(forKey: "noteFilePath"), !savedPath.isEmpty {
            self.filePath = savedPath
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.filePath = documentsPath.appendingPathComponent("quicknote.md").path
        }

        loadNote()
    }

    func loadNote() {
        isLoading = true
        defer { isLoading = false }

        let expandedPath = (filePath as NSString).expandingTildeInPath

        if FileManager.default.fileExists(atPath: expandedPath) {
            do {
                content = try String(contentsOfFile: expandedPath, encoding: .utf8)
            } catch {
                print("Error loading note: \(error)")
                content = ""
            }
        } else {
            content = ""
            // Create the file if it doesn't exist
            saveNote()
        }
    }

    func saveNote() {
        let expandedPath = (filePath as NSString).expandingTildeInPath

        do {
            // Ensure directory exists
            let directory = (expandedPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

            try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
        } catch {
            print("Error saving note: \(error)")
        }
    }

    // Debounced save - saves 0.5 seconds after last change
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            if !Task.isCancelled {
                await MainActor.run {
                    saveNote()
                }
            }
        }
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a markdown file for your notes"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
        }
    }

    func createNewFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "quicknote.md"
        panel.message = "Create a new markdown file for your notes"
        panel.prompt = "Create"

        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
        }
    }
}
