import XCTest
import Foundation

// MARK: - Document Model (copied for testing since we can't import executable target)
// This mirrors the Document class from the main app

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

final class DocumentTests: XCTestCase {

    var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    // MARK: - Initialization Tests

    func testInitWithDefaultValues() {
        let document = Document()

        XCTAssertNotNil(document.id)
        XCTAssertNil(document.filePath)
        XCTAssertEqual(document.content, "")
        XCTAssertFalse(document.isDirty)
    }

    func testInitWithFilePath() {
        let path = "/Users/test/notes/test.md"
        let document = Document(filePath: path)

        XCTAssertEqual(document.filePath, path)
        XCTAssertEqual(document.content, "")
        XCTAssertFalse(document.isDirty)
    }

    func testInitWithContent() {
        let content = "Hello, World!"
        let document = Document(content: content)

        XCTAssertEqual(document.content, content)
        XCTAssertNil(document.filePath)
    }

    func testInitWithAllParameters() {
        let id = UUID()
        let path = "/test/path.md"
        let content = "Test content"

        let document = Document(id: id, filePath: path, content: content)

        XCTAssertEqual(document.id, id)
        XCTAssertEqual(document.filePath, path)
        XCTAssertEqual(document.content, content)
    }

    // MARK: - fileName Tests

    func testFileNameReturnsLastPathComponent() {
        let document = Document(filePath: "/Users/test/Documents/my-note.md")
        XCTAssertEqual(document.fileName, "my-note.md")
    }

    func testFileNameReturnsUntitledWhenNoPath() {
        let document = Document()
        XCTAssertEqual(document.fileName, "Untitled")
    }

    func testFileNameWithDeepPath() {
        let document = Document(filePath: "/very/deep/nested/path/to/file.txt")
        XCTAssertEqual(document.fileName, "file.txt")
    }

    func testFileNameWithSpaces() {
        let document = Document(filePath: "/Users/test/My Documents/My Note.md")
        XCTAssertEqual(document.fileName, "My Note.md")
    }

    // MARK: - isUntitled Tests

    func testIsUntitledTrueWhenNoPath() {
        let document = Document()
        XCTAssertTrue(document.isUntitled)
    }

    func testIsUntitledFalseWhenPathExists() {
        let document = Document(filePath: "/test/path.md")
        XCTAssertFalse(document.isUntitled)
    }

    // MARK: - markDirty Tests

    func testMarkDirty() {
        let document = Document()
        XCTAssertFalse(document.isDirty)

        document.markDirty()

        XCTAssertTrue(document.isDirty)
    }

    func testMarkDirtyMultipleTimes() {
        let document = Document()

        document.markDirty()
        document.markDirty()
        document.markDirty()

        XCTAssertTrue(document.isDirty)
    }

    // MARK: - Load Tests

    func testLoadSetsContentAndClearsDirty() throws {
        let testContent = "Test file content\nWith multiple lines"
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let document = Document(filePath: testFile.path)
        document.isDirty = true

        document.load()

        XCTAssertEqual(document.content, testContent)
        XCTAssertFalse(document.isDirty)
    }

    func testLoadNonExistentFile() {
        let document = Document(filePath: "/nonexistent/path/file.md")

        document.load()

        // Should not crash, content should remain empty
        XCTAssertEqual(document.content, "")
    }

    func testLoadWithNilPath() {
        let document = Document()
        document.content = "existing content"

        document.load()

        // Should not crash, content should remain unchanged
        XCTAssertEqual(document.content, "existing content")
    }

    func testLoadEmptyFile() throws {
        let testFile = tempDirectory.appendingPathComponent("empty.md")
        try "".write(to: testFile, atomically: true, encoding: .utf8)

        let document = Document(filePath: testFile.path)
        document.content = "some content"
        document.isDirty = true

        document.load()

        XCTAssertEqual(document.content, "")
        XCTAssertFalse(document.isDirty)
    }

    func testTildeExpansionInPath() throws {
        // Create file in temp directory simulating home path
        let testContent = "Tilde test content"
        let testFile = tempDirectory.appendingPathComponent("tilde-test.md")
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        // Use actual path since we can't mock tilde expansion
        let document = Document(filePath: testFile.path)
        document.load()

        XCTAssertEqual(document.content, testContent)
    }

    func testLoadUnicodeContent() throws {
        let testContent = "Unicode content: 你好世界 🌍 مرحبا"
        let testFile = tempDirectory.appendingPathComponent("unicode.md")
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let document = Document(filePath: testFile.path)
        document.load()

        XCTAssertEqual(document.content, testContent)
    }

    func testLoadLargeFile() throws {
        let testContent = String(repeating: "Line of text\n", count: 10000)
        let testFile = tempDirectory.appendingPathComponent("large.md")
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let document = Document(filePath: testFile.path)
        document.load()

        XCTAssertEqual(document.content, testContent)
    }

    // MARK: - Save Tests

    func testSaveClearsDirtyFlag() throws {
        let testFile = tempDirectory.appendingPathComponent("save-test.md")

        let document = Document(filePath: testFile.path, content: "Test content")
        document.isDirty = true

        document.save()

        XCTAssertFalse(document.isDirty)
    }

    func testSaveCreatesFile() throws {
        let testFile = tempDirectory.appendingPathComponent("new-file.md")
        let content = "New file content"

        let document = Document(filePath: testFile.path, content: content)
        document.save()

        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        let savedContent = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(savedContent, content)
    }

    func testSaveCreatesDirectoryIfNeeded() throws {
        let nestedPath = tempDirectory.appendingPathComponent("nested/deep/path/file.md")
        let content = "Nested content"

        let document = Document(filePath: nestedPath.path, content: content)
        document.save()

        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedPath.path))
        let savedContent = try String(contentsOf: nestedPath, encoding: .utf8)
        XCTAssertEqual(savedContent, content)
    }

    func testSaveOverwritesExistingFile() throws {
        let testFile = tempDirectory.appendingPathComponent("overwrite.md")
        try "Original content".write(to: testFile, atomically: true, encoding: .utf8)

        let newContent = "Updated content"
        let document = Document(filePath: testFile.path, content: newContent)
        document.save()

        let savedContent = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(savedContent, newContent)
    }

    func testSaveWithNilPath() {
        let document = Document(content: "Some content")
        document.isDirty = true

        document.save()

        // Should not crash, dirty flag should remain true since save didn't succeed
        XCTAssertTrue(document.isDirty)
    }

    func testSaveUnicodeContent() throws {
        let testFile = tempDirectory.appendingPathComponent("unicode-save.md")
        let content = "Unicode: 日本語 한국어 العربية"

        let document = Document(filePath: testFile.path, content: content)
        document.save()

        let savedContent = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(savedContent, content)
    }

    func testSaveEmptyContent() throws {
        let testFile = tempDirectory.appendingPathComponent("empty-save.md")

        let document = Document(filePath: testFile.path, content: "")
        document.save()

        let savedContent = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(savedContent, "")
    }

    // MARK: - Load/Save Round Trip Tests

    func testLoadSaveRoundTrip() throws {
        let originalContent = "Round trip content\nWith newlines\n\tAnd tabs"
        let testFile = tempDirectory.appendingPathComponent("roundtrip.md")

        // Save
        let doc1 = Document(filePath: testFile.path, content: originalContent)
        doc1.save()

        // Load
        let doc2 = Document(filePath: testFile.path)
        doc2.load()

        XCTAssertEqual(doc2.content, originalContent)
    }

    // MARK: - Edge Cases

    func testFileNameWithOnlyFileName() {
        let document = Document(filePath: "justfile.md")
        XCTAssertEqual(document.fileName, "justfile.md")
    }

    func testContentChangeDoesNotAutoMarkDirty() {
        let document = Document()
        document.content = "New content"

        // Note: The dirty flag is only set through markDirty() or DocumentManager observation
        // Direct content changes don't auto-set it (this is intentional design)
        XCTAssertFalse(document.isDirty)
    }
}
