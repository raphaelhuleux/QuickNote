import Foundation
import AppKit
import UniformTypeIdentifiers
import Combine

class DocumentManager: ObservableObject {
    @Published var documents: [Document] = []
    @Published var activeDocumentId: UUID?
    @Published var defaultFolder: String {
        didSet {
            UserDefaults.standard.set(defaultFolder, forKey: "defaultFolder")
        }
    }

    private var saveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var documentCancellables: [UUID: AnyCancellable] = [:]

    static let shared = DocumentManager()

    var activeDocument: Document? {
        guard let id = activeDocumentId else { return nil }
        return documents.first { $0.id == id }
    }

    var activeDocumentIndex: Int? {
        guard let id = activeDocumentId else { return nil }
        return documents.firstIndex { $0.id == id }
    }

    private init() {
        // Load default folder
        if let savedFolder = UserDefaults.standard.string(forKey: "defaultFolder"), !savedFolder.isEmpty {
            self.defaultFolder = savedFolder
        } else {
            // Bug fix: Avoid force unwrap - use guard with fallback to temp directory
            guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                self.defaultFolder = NSTemporaryDirectory()
                restoreSession()
                if documents.isEmpty {
                    newDocument()
                }
                return
            }
            self.defaultFolder = documentsPath.path
        }

        restoreSession()

        // If no documents restored, create an empty one
        if documents.isEmpty {
            newDocument()
        }
    }

    // MARK: - Default Folder

    func selectDefaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the default folder for new notes"
        panel.prompt = "Select Folder"

        // Bug fix: Use URL(fileURLWithPath:) for file system paths, not URL(string:)
        let folder = URL(fileURLWithPath: defaultFolder)
        panel.directoryURL = folder

        if panel.runModal() == .OK, let url = panel.url {
            defaultFolder = url.path
        }
    }

    // MARK: - Document Management

    func newDocument() {
        let doc = Document()
        documents.append(doc)
        activeDocumentId = doc.id
        observeDocument(doc)
        saveSession()
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select markdown files to open"
        panel.prompt = "Open"

        // Start in default folder
        panel.directoryURL = URL(fileURLWithPath: defaultFolder)

        if panel.runModal() == .OK {
            for url in panel.urls {
                openFile(at: url.path)
            }
        }
    }

    func openFile(at path: String) {
        // Check if already open
        if let existing = documents.first(where: { $0.filePath == path }) {
            activeDocumentId = existing.id
            return
        }

        let doc = Document(filePath: path)
        doc.load()
        documents.append(doc)
        activeDocumentId = doc.id
        observeDocument(doc)
        saveSession()
    }

    func closeDocument(_ document: Document) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }

        // If dirty, show confirmation dialog
        if document.isDirty {
            let response = showSaveConfirmation(for: document)
            switch response {
            case .save:
                if document.isUntitled {
                    if !saveDocumentAs(document) {
                        return // User cancelled save dialog
                    }
                } else {
                    document.save()
                }
            case .dontSave:
                // Discard changes, continue with close
                break
            case .cancel:
                return // Abort close
            }
        }

        // Bug fix: Clean up Combine subscription to prevent memory leak
        documentCancellables.removeValue(forKey: document.id)

        documents.remove(at: index)

        // Update active document
        if activeDocumentId == document.id {
            if documents.isEmpty {
                newDocument()
            } else {
                let newIndex = min(index, documents.count - 1)
                activeDocumentId = documents[newIndex].id
            }
        }

        saveSession()
    }

    private enum SaveConfirmationResponse {
        case save, dontSave, cancel
    }

    private func showSaveConfirmation(for document: Document) -> SaveConfirmationResponse {
        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to \"\(document.fileName)\"?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .dontSave
        default:
            return .cancel
        }
    }

    private func saveDocumentAs(_ document: Document) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = document.isUntitled ? "Untitled.md" : document.fileName
        panel.message = "Save your note"
        panel.prompt = "Save"
        panel.directoryURL = URL(fileURLWithPath: defaultFolder)

        if panel.runModal() == .OK, let url = panel.url {
            document.filePath = url.path
            document.save()
            saveSession()
            return true
        }
        return false
    }

    func closeActiveDocument() {
        guard let doc = activeDocument else { return }
        closeDocument(doc)
    }

    func saveActiveDocument() {
        guard let doc = activeDocument else { return }

        if doc.isUntitled {
            saveActiveDocumentAs()
        } else {
            doc.save()
        }
    }

    func saveActiveDocumentAs() {
        guard let doc = activeDocument else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = doc.isUntitled ? "Untitled.md" : doc.fileName
        panel.message = "Save your note"
        panel.prompt = "Save"
        panel.directoryURL = URL(fileURLWithPath: defaultFolder)

        if panel.runModal() == .OK, let url = panel.url {
            doc.filePath = url.path
            doc.save()
            saveSession()
        }
    }

    func setActiveDocument(_ document: Document) {
        activeDocumentId = document.id
    }

    func nextTab() {
        guard let index = activeDocumentIndex, documents.count > 1 else { return }
        let nextIndex = (index + 1) % documents.count
        activeDocumentId = documents[nextIndex].id
    }

    func previousTab() {
        guard let index = activeDocumentIndex, documents.count > 1 else { return }
        let prevIndex = (index - 1 + documents.count) % documents.count
        activeDocumentId = documents[prevIndex].id
    }

    // MARK: - Auto-save (disabled - manual save only)

    private func observeDocument(_ document: Document) {
        // Bug fix: Store cancellable per-document for proper cleanup on close
        let cancellable = document.$content
            .dropFirst()
            .sink { [weak document] _ in
                document?.markDirty()
            }
        documentCancellables[document.id] = cancellable
    }

    // MARK: - Session Persistence

    private func saveSession() {
        let paths = documents.compactMap { $0.filePath }
        UserDefaults.standard.set(paths, forKey: "openDocumentPaths")

        if let activeId = activeDocumentId,
           let activeDoc = documents.first(where: { $0.id == activeId }),
           let activePath = activeDoc.filePath {
            UserDefaults.standard.set(activePath, forKey: "activeDocumentPath")
        }
    }

    private func restoreSession() {
        guard let paths = UserDefaults.standard.stringArray(forKey: "openDocumentPaths") else { return }
        let activePath = UserDefaults.standard.string(forKey: "activeDocumentPath")

        for path in paths {
            if FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath) {
                let doc = Document(filePath: path)
                doc.load()
                documents.append(doc)
                observeDocument(doc)

                if path == activePath {
                    activeDocumentId = doc.id
                }
            }
        }

        // Set first document as active if none was restored
        if activeDocumentId == nil, let first = documents.first {
            activeDocumentId = first.id
        }
    }
}
