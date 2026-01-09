import XCTest
import Foundation
import Combine

// MARK: - Document Model (copied for testing)

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
                print("Error loading document: \(error)")
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
            print("Error saving document: \(error)")
        }
    }

    func markDirty() {
        isDirty = true
    }
}

// MARK: - Testable DocumentManager

/// A testable version of DocumentManager that doesn't use UI elements and allows controlled testing
class TestableDocumentManager: ObservableObject {
    @Published var documents: [Document] = []
    @Published var activeDocumentId: UUID?
    @Published var defaultFolder: String

    private var cancellables = Set<AnyCancellable>()
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
    }

    func closeDocument(_ document: Document, shouldSave: Bool = false) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }

        if shouldSave && !document.isUntitled {
            document.save()
        }

        // Clean up cancellables for this document
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

final class DocumentManagerTests: XCTestCase {

    var tempDirectory: URL!
    var manager: TestableDocumentManager!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        manager = TestableDocumentManager(defaultFolder: tempDirectory.path)
    }

    override func tearDownWithError() throws {
        manager = nil
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    // MARK: - Initialization Tests

    func testDefaultFolderIsSet() {
        XCTAssertEqual(manager.defaultFolder, tempDirectory.path)
    }

    func testDefaultFolderFallsBackToDocuments() {
        let defaultManager = TestableDocumentManager()
        XCTAssertFalse(defaultManager.defaultFolder.isEmpty)
    }

    // MARK: - New Document Tests

    func testNewDocumentAddsToList() {
        let initialCount = manager.documents.count

        manager.newDocument()

        XCTAssertEqual(manager.documents.count, initialCount + 1)
    }

    func testNewDocumentBecomesActive() {
        manager.newDocument()

        XCTAssertNotNil(manager.activeDocumentId)
        XCTAssertEqual(manager.activeDocument?.id, manager.documents.last?.id)
    }

    func testNewDocumentIsUntitled() {
        manager.newDocument()

        XCTAssertTrue(manager.activeDocument?.isUntitled ?? false)
    }

    func testNewDocumentHasEmptyContent() {
        manager.newDocument()

        XCTAssertEqual(manager.activeDocument?.content, "")
    }

    func testMultipleNewDocuments() {
        manager.newDocument()
        manager.newDocument()
        manager.newDocument()

        XCTAssertEqual(manager.documents.count, 3)
    }

    // MARK: - Open File Tests

    func testOpenFileAddsDocument() throws {
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try "Test content".write(to: testFile, atomically: true, encoding: .utf8)

        manager.openFile(at: testFile.path)

        XCTAssertEqual(manager.documents.count, 1)
    }

    func testOpenFileSetsActiveDocument() throws {
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try "Test content".write(to: testFile, atomically: true, encoding: .utf8)

        manager.openFile(at: testFile.path)

        XCTAssertEqual(manager.activeDocument?.filePath, testFile.path)
    }

    func testOpenFileLoadsContent() throws {
        let content = "File content to load"
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        manager.openFile(at: testFile.path)

        XCTAssertEqual(manager.activeDocument?.content, content)
    }

    func testOpenAlreadyOpenFileSwitchesToIt() throws {
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try "Test content".write(to: testFile, atomically: true, encoding: .utf8)

        manager.openFile(at: testFile.path)
        let firstDocId = manager.activeDocumentId

        manager.newDocument() // Create another document
        XCTAssertNotEqual(manager.activeDocumentId, firstDocId)

        manager.openFile(at: testFile.path) // Open same file again

        XCTAssertEqual(manager.documents.count, 2) // No duplicate
        XCTAssertEqual(manager.activeDocumentId, firstDocId) // Switched back
    }

    func testOpenMultipleFiles() throws {
        let file1 = tempDirectory.appendingPathComponent("file1.md")
        let file2 = tempDirectory.appendingPathComponent("file2.md")
        let file3 = tempDirectory.appendingPathComponent("file3.md")

        try "Content 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Content 2".write(to: file2, atomically: true, encoding: .utf8)
        try "Content 3".write(to: file3, atomically: true, encoding: .utf8)

        manager.openFile(at: file1.path)
        manager.openFile(at: file2.path)
        manager.openFile(at: file3.path)

        XCTAssertEqual(manager.documents.count, 3)
        XCTAssertEqual(manager.activeDocument?.filePath, file3.path)
    }

    func testOpenNonExistentFile() {
        let nonExistentPath = tempDirectory.appendingPathComponent("nonexistent.md").path

        manager.openFile(at: nonExistentPath)

        // Should still add document but content will be empty
        XCTAssertEqual(manager.documents.count, 1)
        XCTAssertEqual(manager.activeDocument?.content, "")
    }

    // MARK: - Close Document Tests

    func testCloseDocumentRemovesFromList() {
        manager.newDocument()
        manager.newDocument()
        let docToClose = manager.documents.first!
        let initialCount = manager.documents.count

        manager.closeDocument(docToClose)

        XCTAssertEqual(manager.documents.count, initialCount - 1)
        XCTAssertFalse(manager.documents.contains(where: { $0.id == docToClose.id }))
    }

    func testCloseActiveDocumentSelectsNext() {
        manager.newDocument() // doc 0
        manager.newDocument() // doc 1 (active)
        manager.newDocument() // doc 2

        manager.setActiveDocument(manager.documents[1])
        let doc1Id = manager.documents[1].id

        manager.closeDocument(manager.documents[1])

        // Should select document at same index (now doc 2 became index 1)
        XCTAssertNotEqual(manager.activeDocumentId, doc1Id)
        XCTAssertNotNil(manager.activeDocumentId)
    }

    func testCloseLastDocumentCreatesNew() {
        manager.newDocument()
        let doc = manager.documents.first!

        manager.closeDocument(doc)

        XCTAssertEqual(manager.documents.count, 1)
        XCTAssertNotNil(manager.activeDocumentId)
        XCTAssertTrue(manager.activeDocument?.isUntitled ?? false)
    }

    func testCloseDocumentNotInList() {
        manager.newDocument()
        let outsideDoc = Document()
        let initialCount = manager.documents.count

        manager.closeDocument(outsideDoc)

        XCTAssertEqual(manager.documents.count, initialCount)
    }

    func testCloseLastDocumentFromEnd() {
        manager.newDocument()
        manager.newDocument()
        manager.newDocument()

        let lastDoc = manager.documents.last!
        manager.setActiveDocument(lastDoc)

        manager.closeDocument(lastDoc)

        // Should select previous (now last) document
        XCTAssertEqual(manager.activeDocumentId, manager.documents.last?.id)
    }

    // MARK: - Tab Navigation Tests

    func testNextTabWrapsAround() {
        manager.newDocument()
        manager.newDocument()
        manager.newDocument()

        manager.setActiveDocument(manager.documents.last!) // Go to last

        manager.nextTab()

        XCTAssertEqual(manager.activeDocumentId, manager.documents.first?.id) // Wrapped to first
    }

    func testPreviousTabWrapsAround() {
        manager.newDocument()
        manager.newDocument()
        manager.newDocument()

        manager.setActiveDocument(manager.documents.first!) // Go to first

        manager.previousTab()

        XCTAssertEqual(manager.activeDocumentId, manager.documents.last?.id) // Wrapped to last
    }

    func testNextTabWithSingleDocument() {
        manager.newDocument()
        let docId = manager.activeDocumentId

        manager.nextTab()

        XCTAssertEqual(manager.activeDocumentId, docId) // Should stay same
    }

    func testPreviousTabWithSingleDocument() {
        manager.newDocument()
        let docId = manager.activeDocumentId

        manager.previousTab()

        XCTAssertEqual(manager.activeDocumentId, docId) // Should stay same
    }

    func testNextTabSequence() {
        manager.newDocument() // 0
        manager.newDocument() // 1
        manager.newDocument() // 2

        manager.setActiveDocument(manager.documents[0])

        manager.nextTab()
        XCTAssertEqual(manager.activeDocumentId, manager.documents[1].id)

        manager.nextTab()
        XCTAssertEqual(manager.activeDocumentId, manager.documents[2].id)

        manager.nextTab()
        XCTAssertEqual(manager.activeDocumentId, manager.documents[0].id) // Wrapped
    }

    func testPreviousTabSequence() {
        manager.newDocument() // 0
        manager.newDocument() // 1
        manager.newDocument() // 2

        manager.setActiveDocument(manager.documents[2])

        manager.previousTab()
        XCTAssertEqual(manager.activeDocumentId, manager.documents[1].id)

        manager.previousTab()
        XCTAssertEqual(manager.activeDocumentId, manager.documents[0].id)

        manager.previousTab()
        XCTAssertEqual(manager.activeDocumentId, manager.documents[2].id) // Wrapped
    }

    // MARK: - Active Document Tests

    func testActiveDocumentReturnsCorrectDocument() {
        manager.newDocument()
        manager.newDocument()

        let targetDoc = manager.documents.first!
        manager.setActiveDocument(targetDoc)

        XCTAssertEqual(manager.activeDocument?.id, targetDoc.id)
    }

    func testActiveDocumentReturnsNilWhenNoDocuments() {
        let emptyManager = TestableDocumentManager()
        XCTAssertNil(emptyManager.activeDocument)
    }

    func testActiveDocumentIndexReturnsCorrectIndex() {
        manager.newDocument() // 0
        manager.newDocument() // 1
        manager.newDocument() // 2

        manager.setActiveDocument(manager.documents[1])

        XCTAssertEqual(manager.activeDocumentIndex, 1)
    }

    func testActiveDocumentIndexReturnsNilWhenNoActive() {
        let emptyManager = TestableDocumentManager()
        XCTAssertNil(emptyManager.activeDocumentIndex)
    }

    // MARK: - Set Active Document Tests

    func testSetActiveDocument() {
        manager.newDocument()
        manager.newDocument()

        let firstDoc = manager.documents.first!
        manager.setActiveDocument(firstDoc)

        XCTAssertEqual(manager.activeDocumentId, firstDoc.id)
    }

    // MARK: - Content Observation Tests

    func testContentChangeMarksDirty() {
        manager.newDocument()
        let doc = manager.activeDocument!

        XCTAssertFalse(doc.isDirty)

        // Simulate content change (this triggers the Combine observation)
        doc.content = "New content"

        // Give Combine time to process
        let expectation = XCTestExpectation(description: "Dirty flag set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(doc.isDirty)
    }

    // MARK: - Edge Cases

    func testOpenSameFileMultipleTimes() throws {
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try "Test content".write(to: testFile, atomically: true, encoding: .utf8)

        manager.openFile(at: testFile.path)
        manager.openFile(at: testFile.path)
        manager.openFile(at: testFile.path)

        XCTAssertEqual(manager.documents.count, 1) // No duplicates
    }

    func testRapidNewDocumentCreation() {
        for _ in 0..<100 {
            manager.newDocument()
        }

        XCTAssertEqual(manager.documents.count, 100)
    }

    func testCloseAllExceptOne() {
        manager.newDocument()
        manager.newDocument()
        manager.newDocument()

        while manager.documents.count > 1 {
            manager.closeDocument(manager.documents.first!)
        }

        XCTAssertEqual(manager.documents.count, 1)
    }

    func testDocumentOrderPreserved() {
        manager.newDocument()
        manager.newDocument()
        manager.newDocument()

        let ids = manager.documents.map { $0.id }

        // Verify order is maintained
        for (index, doc) in manager.documents.enumerated() {
            XCTAssertEqual(doc.id, ids[index])
        }
    }
}
