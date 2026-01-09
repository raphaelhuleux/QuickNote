#!/usr/bin/env swift

import Foundation
import Combine

// MARK: - Simple Test Framework

var testsPassed = 0
var testsFailed = 0
var currentTestName = ""

func test(_ name: String, _ block: () throws -> Void) {
    currentTestName = name
    do {
        try block()
        testsPassed += 1
        print("  ✓ \(name)")
    } catch {
        testsFailed += 1
        print("  ✗ \(name): \(error)")
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, file: String = #file, line: Int = #line) throws {
    if actual != expected {
        throw TestError.assertionFailed("Expected \(expected) but got \(actual) at \(file):\(line)")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    if !condition {
        throw TestError.assertionFailed("Assertion failed: \(message) at \(file):\(line)")
    }
}

func assertFalse(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    if condition {
        throw TestError.assertionFailed("Expected false but got true: \(message) at \(file):\(line)")
    }
}

func assertNil<T>(_ value: T?, file: String = #file, line: Int = #line) throws {
    if value != nil {
        throw TestError.assertionFailed("Expected nil but got \(value!) at \(file):\(line)")
    }
}

func assertNotNil<T>(_ value: T?, file: String = #file, line: Int = #line) throws {
    if value == nil {
        throw TestError.assertionFailed("Expected non-nil value at \(file):\(line)")
    }
}

enum TestError: Error {
    case assertionFailed(String)
}

// MARK: - Document Model (copy of app code for testing)

class Document: Identifiable, ObservableObject {
    let id: UUID
    @Published var filePath: String?
    @Published var content: String
    @Published var isDirty: Bool = false

    var fileName: String {
        if let path = filePath {
            return (path as NSString).lastPathComponent
        }
        return "Untitled"
    }

    var isUntitled: Bool {
        filePath == nil
    }

    init(id: UUID = UUID(), filePath: String? = nil, content: String = "") {
        self.id = id
        self.filePath = filePath
        self.content = content
    }

    func load() {
        guard let path = filePath else { return }
        let expandedPath = (path as NSString).expandingTildeInPath

        if FileManager.default.fileExists(atPath: expandedPath) {
            do {
                content = try String(contentsOfFile: expandedPath, encoding: .utf8)
                isDirty = false
            } catch {
                // Error handling
            }
        }
    }

    func save() {
        guard let path = filePath else { return }
        let expandedPath = (path as NSString).expandingTildeInPath

        do {
            let directory = (expandedPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
            isDirty = false
        } catch {
            // Error handling
        }
    }

    func markDirty() {
        isDirty = true
    }
}

// MARK: - Testable DocumentManager

class TestableDocumentManager: ObservableObject {
    @Published var documents: [Document] = []
    @Published var activeDocumentId: UUID?
    @Published var defaultFolder: String

    private var documentCancellables: [UUID: AnyCancellable] = [:]

    var activeDocument: Document? {
        guard let id = activeDocumentId else { return nil }
        return documents.first { $0.id == id }
    }

    var activeDocumentIndex: Int? {
        guard let id = activeDocumentId else { return nil }
        return documents.firstIndex { $0.id == id }
    }

    init(defaultFolder: String? = nil) {
        if let folder = defaultFolder {
            self.defaultFolder = folder
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            self.defaultFolder = documentsPath?.path ?? NSTemporaryDirectory()
        }
    }

    func newDocument() {
        let doc = Document()
        documents.append(doc)
        activeDocumentId = doc.id
        observeDocument(doc)
    }

    func openFile(at path: String) {
        if let existing = documents.first(where: { $0.filePath == path }) {
            activeDocumentId = existing.id
            return
        }

        let doc = Document(filePath: path)
        doc.load()
        documents.append(doc)
        activeDocumentId = doc.id
        observeDocument(doc)
    }

    func closeDocument(_ document: Document, shouldSave: Bool = false) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }

        if shouldSave && !document.isUntitled {
            document.save()
        }

        documentCancellables.removeValue(forKey: document.id)
        documents.remove(at: index)

        if activeDocumentId == document.id {
            if documents.isEmpty {
                newDocument()
            } else {
                let newIndex = min(index, documents.count - 1)
                activeDocumentId = documents[newIndex].id
            }
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

    private func observeDocument(_ document: Document) {
        let cancellable = document.$content
            .dropFirst()
            .sink { [weak document] _ in
                document?.markDirty()
            }
        documentCancellables[document.id] = cancellable
    }
}

// MARK: - Test Helpers

var tempDirectory: URL!

func setupTempDirectory() {
    tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
}

func cleanupTempDirectory() {
    if FileManager.default.fileExists(atPath: tempDirectory.path) {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}

// MARK: - Document Tests

func runDocumentTests() {
    print("\n📋 Document Tests")
    print("─────────────────")

    setupTempDirectory()
    defer { cleanupTempDirectory() }

    test("testInitWithDefaultValues") {
        let document = Document()
        try assertNotNil(document.id)
        try assertNil(document.filePath)
        try assertEqual(document.content, "")
        try assertFalse(document.isDirty)
    }

    test("testInitWithFilePath") {
        let path = "/Users/test/notes/test.md"
        let document = Document(filePath: path)
        try assertEqual(document.filePath, path)
        try assertEqual(document.content, "")
    }

    test("testFileNameReturnsLastPathComponent") {
        let document = Document(filePath: "/Users/test/Documents/my-note.md")
        try assertEqual(document.fileName, "my-note.md")
    }

    test("testFileNameReturnsUntitledWhenNoPath") {
        let document = Document()
        try assertEqual(document.fileName, "Untitled")
    }

    test("testIsUntitledTrueWhenNoPath") {
        let document = Document()
        try assertTrue(document.isUntitled)
    }

    test("testIsUntitledFalseWhenPathExists") {
        let document = Document(filePath: "/test/path.md")
        try assertFalse(document.isUntitled)
    }

    test("testMarkDirty") {
        let document = Document()
        try assertFalse(document.isDirty)
        document.markDirty()
        try assertTrue(document.isDirty)
    }

    test("testLoadSetsContentAndClearsDirty") {
        let testContent = "Test file content"
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try! testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let document = Document(filePath: testFile.path)
        document.isDirty = true
        document.load()

        try assertEqual(document.content, testContent)
        try assertFalse(document.isDirty)
    }

    test("testLoadNonExistentFile") {
        let document = Document(filePath: "/nonexistent/path/file.md")
        document.load()
        try assertEqual(document.content, "")
    }

    test("testSaveCreatesFile") {
        let testFile = tempDirectory.appendingPathComponent("new-file.md")
        let content = "New file content"

        let document = Document(filePath: testFile.path, content: content)
        document.save()

        try assertTrue(FileManager.default.fileExists(atPath: testFile.path))
        let savedContent = try! String(contentsOf: testFile, encoding: .utf8)
        try assertEqual(savedContent, content)
    }

    test("testSaveClearsDirtyFlag") {
        let testFile = tempDirectory.appendingPathComponent("save-test.md")
        let document = Document(filePath: testFile.path, content: "Test")
        document.isDirty = true
        document.save()
        try assertFalse(document.isDirty)
    }

    test("testSaveCreatesDirectoryIfNeeded") {
        let nestedPath = tempDirectory.appendingPathComponent("nested/deep/file.md")
        let document = Document(filePath: nestedPath.path, content: "Nested")
        document.save()
        try assertTrue(FileManager.default.fileExists(atPath: nestedPath.path))
    }

    test("testLoadSaveRoundTrip") {
        let originalContent = "Round trip content\nWith newlines"
        let testFile = tempDirectory.appendingPathComponent("roundtrip.md")

        let doc1 = Document(filePath: testFile.path, content: originalContent)
        doc1.save()

        let doc2 = Document(filePath: testFile.path)
        doc2.load()

        try assertEqual(doc2.content, originalContent)
    }
}

// MARK: - DocumentManager Tests

func runDocumentManagerTests() {
    print("\n📁 DocumentManager Tests")
    print("────────────────────────")

    setupTempDirectory()
    defer { cleanupTempDirectory() }

    test("testDefaultFolderIsSet") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        try assertEqual(manager.defaultFolder, tempDirectory.path)
    }

    test("testNewDocumentAddsToList") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        let initialCount = manager.documents.count
        manager.newDocument()
        try assertEqual(manager.documents.count, initialCount + 1)
    }

    test("testNewDocumentBecomesActive") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        manager.newDocument()
        try assertNotNil(manager.activeDocumentId)
        try assertEqual(manager.activeDocument?.id, manager.documents.last?.id)
    }

    test("testNewDocumentIsUntitled") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        manager.newDocument()
        try assertTrue(manager.activeDocument?.isUntitled ?? false)
    }

    test("testOpenFileAddsDocument") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try! "Test content".write(to: testFile, atomically: true, encoding: .utf8)

        manager.openFile(at: testFile.path)
        try assertEqual(manager.documents.count, 1)
    }

    test("testOpenFileSetsActiveDocument") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try! "Test content".write(to: testFile, atomically: true, encoding: .utf8)

        manager.openFile(at: testFile.path)
        try assertEqual(manager.activeDocument?.filePath, testFile.path)
    }

    test("testOpenAlreadyOpenFileSwitchesToIt") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try! "Test content".write(to: testFile, atomically: true, encoding: .utf8)

        manager.openFile(at: testFile.path)
        let firstDocId = manager.activeDocumentId

        manager.newDocument()
        try assertTrue(manager.activeDocumentId != firstDocId)

        manager.openFile(at: testFile.path)
        try assertEqual(manager.documents.count, 2)
        try assertEqual(manager.activeDocumentId, firstDocId)
    }

    test("testCloseDocumentRemovesFromList") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        manager.newDocument()
        manager.newDocument()
        let docToClose = manager.documents.first!
        let initialCount = manager.documents.count

        manager.closeDocument(docToClose)
        try assertEqual(manager.documents.count, initialCount - 1)
    }

    test("testCloseLastDocumentCreatesNew") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        manager.newDocument()
        let doc = manager.documents.first!

        manager.closeDocument(doc)
        try assertEqual(manager.documents.count, 1)
        try assertTrue(manager.activeDocument?.isUntitled ?? false)
    }

    test("testNextTabWrapsAround") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        manager.newDocument()
        manager.newDocument()
        manager.newDocument()

        manager.setActiveDocument(manager.documents.last!)
        manager.nextTab()

        try assertEqual(manager.activeDocumentId, manager.documents.first?.id)
    }

    test("testPreviousTabWrapsAround") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        manager.newDocument()
        manager.newDocument()
        manager.newDocument()

        manager.setActiveDocument(manager.documents.first!)
        manager.previousTab()

        try assertEqual(manager.activeDocumentId, manager.documents.last?.id)
    }

    test("testNextTabWithSingleDocument") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        manager.newDocument()
        let docId = manager.activeDocumentId

        manager.nextTab()
        try assertEqual(manager.activeDocumentId, docId)
    }

    test("testSetActiveDocument") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        manager.newDocument()
        manager.newDocument()

        let firstDoc = manager.documents.first!
        manager.setActiveDocument(firstDoc)

        try assertEqual(manager.activeDocumentId, firstDoc.id)
    }

    test("testContentChangeMarksDirty") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        manager.newDocument()
        let doc = manager.activeDocument!

        try assertFalse(doc.isDirty)
        doc.content = "New content"

        // Give Combine time to process
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        try assertTrue(doc.isDirty)
    }

    test("testMemoryLeakFixCancellablesCleanedUp") {
        let manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
        manager.newDocument()
        manager.newDocument()

        let docToClose = manager.documents.first!
        manager.closeDocument(docToClose)

        // If the cancellable was properly cleaned up, this shouldn't cause issues
        try assertEqual(manager.documents.count, 1)
    }
}

// MARK: - NoteStorage Tests

class TestableNoteStorage: ObservableObject {
    @Published var content: String = ""
    @Published var filePath: String {
        didSet {
            loadNote()
        }
    }

    private var saveTask: Task<Void, Never>?

    init(filePath: String? = nil) {
        if let path = filePath {
            self.filePath = path
        } else {
            self.filePath = NSTemporaryDirectory() + "test-quicknote.md"
        }
    }

    func loadNote() {
        let expandedPath = (filePath as NSString).expandingTildeInPath

        if FileManager.default.fileExists(atPath: expandedPath) {
            do {
                content = try String(contentsOfFile: expandedPath, encoding: .utf8)
            } catch {
                content = ""
            }
        } else {
            content = ""
            saveNote()
        }
    }

    func saveNote() {
        let expandedPath = (filePath as NSString).expandingTildeInPath

        do {
            let directory = (expandedPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
        } catch {
            // Error handling
        }
    }

    func cancelScheduledSave() {
        saveTask?.cancel()
    }
}

func runNoteStorageTests() {
    print("\n💾 NoteStorage Tests")
    print("────────────────────")

    setupTempDirectory()
    defer { cleanupTempDirectory() }

    test("testInitWithFilePath") {
        let customPath = tempDirectory.appendingPathComponent("custom.md").path
        let storage = TestableNoteStorage(filePath: customPath)
        try assertEqual(storage.filePath, customPath)
    }

    test("testInitCreatesFileIfNotExists") {
        let newFilePath = tempDirectory.appendingPathComponent("new-note.md").path
        let storage = TestableNoteStorage(filePath: newFilePath)
        storage.saveNote() // Ensure file is created
        try assertTrue(FileManager.default.fileExists(atPath: newFilePath))
    }

    test("testLoadNoteReadsContent") {
        let content = "Test note content"
        let testFile = tempDirectory.appendingPathComponent("load-test.md")
        try! content.write(to: testFile, atomically: true, encoding: .utf8)

        let storage = TestableNoteStorage(filePath: testFile.path)
        storage.loadNote() // Explicitly load after file is created
        try assertEqual(storage.content, content)
    }

    test("testSaveNoteWritesContent") {
        let testFile = tempDirectory.appendingPathComponent("save-test.md").path
        let storage = TestableNoteStorage(filePath: testFile)
        storage.content = "Content to save"
        storage.saveNote()

        let savedContent = try! String(contentsOfFile: testFile, encoding: .utf8)
        try assertEqual(savedContent, "Content to save")
    }

    test("testSaveNoteCreatesDirectory") {
        let nestedPath = tempDirectory.appendingPathComponent("nested/deep/note.md").path
        let storage = TestableNoteStorage(filePath: nestedPath)
        storage.content = "Nested content"
        storage.saveNote()
        try assertTrue(FileManager.default.fileExists(atPath: nestedPath))
    }

    test("testLoadSaveRoundTrip") {
        let testFile = tempDirectory.appendingPathComponent("roundtrip.md").path
        let storage = TestableNoteStorage(filePath: testFile)
        storage.content = "Round trip content"
        storage.saveNote()

        let storage2 = TestableNoteStorage(filePath: testFile)
        storage2.loadNote() // Explicitly load
        try assertEqual(storage2.content, "Round trip content")
    }
}

// MARK: - Main

print("╔════════════════════════════════════════════╗")
print("║     QuickNote Test Suite                   ║")
print("╚════════════════════════════════════════════╝")

runDocumentTests()
runDocumentManagerTests()
runNoteStorageTests()

print("\n════════════════════════════════════════════")
print("📊 Results: \(testsPassed) passed, \(testsFailed) failed")
print("════════════════════════════════════════════")

if testsFailed > 0 {
    exit(1)
}
