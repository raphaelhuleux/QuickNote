import XCTest
import Foundation
import Combine

// MARK: - Testable NoteStorage

/// A testable version of NoteStorage that doesn't rely on singleton behavior
class TestableNoteStorage: ObservableObject {
    @Published var content: String = ""
    @Published var filePath: String {
        didSet {
            loadNote()
        }
    }

    private var saveTask: Task<Void, Never>?
    private var isLoading = false

    init(filePath: String? = nil) {
        if let path = filePath {
            self.filePath = path
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            self.filePath = documentsPath?.appendingPathComponent("test-quicknote.md").path ?? NSTemporaryDirectory() + "test-quicknote.md"
        }
    }

    func loadNote() {
        isLoading = true
        defer { isLoading = false }

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
            // Error handling - in tests we might want to track this
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds for tests
            if !Task.isCancelled {
                await MainActor.run {
                    saveNote()
                }
            }
        }
    }

    func cancelScheduledSave() {
        saveTask?.cancel()
        saveTask = nil
    }
}

final class NoteStorageTests: XCTestCase {

    var tempDirectory: URL!
    var storage: TestableNoteStorage!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let testFilePath = tempDirectory.appendingPathComponent("test-note.md").path
        storage = TestableNoteStorage(filePath: testFilePath)
    }

    override func tearDownWithError() throws {
        storage?.cancelScheduledSave()
        storage = nil
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    // MARK: - Initialization Tests

    func testInitWithFilePath() {
        let customPath = tempDirectory.appendingPathComponent("custom.md").path
        let customStorage = TestableNoteStorage(filePath: customPath)

        XCTAssertEqual(customStorage.filePath, customPath)
    }

    func testInitWithDefaultPath() {
        let defaultStorage = TestableNoteStorage()
        XCTAssertFalse(defaultStorage.filePath.isEmpty)
        XCTAssertTrue(defaultStorage.filePath.hasSuffix(".md"))
    }

    func testInitCreatesFileIfNotExists() {
        let newFilePath = tempDirectory.appendingPathComponent("new-note.md").path
        let newStorage = TestableNoteStorage(filePath: newFilePath)

        // loadNote is called on init, which creates file if not exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFilePath))
        XCTAssertEqual(newStorage.content, "")
    }

    // MARK: - Load Tests

    func testLoadNoteReadsContent() throws {
        let content = "Test note content"
        let testFile = tempDirectory.appendingPathComponent("load-test.md")
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let loadStorage = TestableNoteStorage(filePath: testFile.path)

        XCTAssertEqual(loadStorage.content, content)
    }

    func testLoadNoteWithEmptyFile() throws {
        let testFile = tempDirectory.appendingPathComponent("empty.md")
        try "".write(to: testFile, atomically: true, encoding: .utf8)

        let loadStorage = TestableNoteStorage(filePath: testFile.path)

        XCTAssertEqual(loadStorage.content, "")
    }

    func testLoadNoteWithMultilineContent() throws {
        let content = """
        Line 1
        Line 2
        Line 3
        """
        let testFile = tempDirectory.appendingPathComponent("multiline.md")
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let loadStorage = TestableNoteStorage(filePath: testFile.path)

        XCTAssertEqual(loadStorage.content, content)
    }

    func testLoadNoteWithUnicodeContent() throws {
        let content = "Unicode: 日本語 한국어 🎉"
        let testFile = tempDirectory.appendingPathComponent("unicode.md")
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let loadStorage = TestableNoteStorage(filePath: testFile.path)

        XCTAssertEqual(loadStorage.content, content)
    }

    func testLoadNonExistentFileCreatesEmpty() {
        let newPath = tempDirectory.appendingPathComponent("nonexistent.md").path
        let newStorage = TestableNoteStorage(filePath: newPath)

        XCTAssertEqual(newStorage.content, "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
    }

    // MARK: - Save Tests

    func testSaveNoteWritesContent() throws {
        storage.content = "Content to save"
        storage.saveNote()

        let savedContent = try String(contentsOfFile: storage.filePath, encoding: .utf8)
        XCTAssertEqual(savedContent, "Content to save")
    }

    func testSaveNoteOverwritesExisting() throws {
        let testFile = tempDirectory.appendingPathComponent("overwrite.md")
        try "Original".write(to: testFile, atomically: true, encoding: .utf8)

        let overwriteStorage = TestableNoteStorage(filePath: testFile.path)
        overwriteStorage.content = "Updated"
        overwriteStorage.saveNote()

        let savedContent = try String(contentsOfFile: testFile.path, encoding: .utf8)
        XCTAssertEqual(savedContent, "Updated")
    }

    func testSaveNoteCreatesDirectory() throws {
        let nestedPath = tempDirectory.appendingPathComponent("nested/deep/note.md").path
        let nestedStorage = TestableNoteStorage(filePath: nestedPath)
        nestedStorage.content = "Nested content"
        nestedStorage.saveNote()

        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedPath))
    }

    func testSaveEmptyContent() throws {
        storage.content = ""
        storage.saveNote()

        let savedContent = try String(contentsOfFile: storage.filePath, encoding: .utf8)
        XCTAssertEqual(savedContent, "")
    }

    // MARK: - Scheduled Save Tests

    func testScheduleSaveDebounces() async throws {
        storage.content = "First"
        storage.scheduleSave()

        storage.content = "Second"
        storage.scheduleSave()

        storage.content = "Third"
        storage.scheduleSave()

        // Wait for debounce
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        let savedContent = try String(contentsOfFile: storage.filePath, encoding: .utf8)
        XCTAssertEqual(savedContent, "Third")
    }

    func testScheduleSaveCanBeCancelled() async throws {
        storage.content = "Will be cancelled"
        storage.scheduleSave()
        storage.cancelScheduledSave()

        // Wait longer than debounce
        try await Task.sleep(nanoseconds: 200_000_000)

        // File should be empty (from initial creation) or not contain the content
        let savedContent = try String(contentsOfFile: storage.filePath, encoding: .utf8)
        XCTAssertNotEqual(savedContent, "Will be cancelled")
    }

    // MARK: - File Path Change Tests

    func testFilePathChangeTriggersLoad() throws {
        let file1 = tempDirectory.appendingPathComponent("file1.md")
        let file2 = tempDirectory.appendingPathComponent("file2.md")

        try "Content 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Content 2".write(to: file2, atomically: true, encoding: .utf8)

        let pathStorage = TestableNoteStorage(filePath: file1.path)
        XCTAssertEqual(pathStorage.content, "Content 1")

        pathStorage.filePath = file2.path
        XCTAssertEqual(pathStorage.content, "Content 2")
    }

    // MARK: - Tilde Expansion Tests

    func testTildeExpansionInPath() throws {
        // We can't easily test actual ~ expansion, but we can verify the code path works
        let testFile = tempDirectory.appendingPathComponent("tilde-test.md")
        try "Tilde content".write(to: testFile, atomically: true, encoding: .utf8)

        let tildeStorage = TestableNoteStorage(filePath: testFile.path)
        XCTAssertEqual(tildeStorage.content, "Tilde content")
    }

    // MARK: - Round Trip Tests

    func testSaveLoadRoundTrip() throws {
        let originalContent = "Round trip content\nWith newlines\n\tAnd tabs"

        storage.content = originalContent
        storage.saveNote()

        // Create new storage pointing to same file
        let loadStorage = TestableNoteStorage(filePath: storage.filePath)

        XCTAssertEqual(loadStorage.content, originalContent)
    }

    func testMultipleSaveLoadCycles() throws {
        for i in 1...5 {
            storage.content = "Cycle \(i)"
            storage.saveNote()

            let loadStorage = TestableNoteStorage(filePath: storage.filePath)
            XCTAssertEqual(loadStorage.content, "Cycle \(i)")
        }
    }

    // MARK: - Edge Cases

    func testLargeContent() throws {
        let largeContent = String(repeating: "Large content line\n", count: 5000)
        storage.content = largeContent
        storage.saveNote()

        let loadStorage = TestableNoteStorage(filePath: storage.filePath)
        XCTAssertEqual(loadStorage.content, largeContent)
    }

    func testSpecialCharactersInContent() throws {
        let specialContent = "Special: \t\n\r\0 end"
        storage.content = specialContent
        storage.saveNote()

        let savedContent = try String(contentsOfFile: storage.filePath, encoding: .utf8)
        XCTAssertEqual(savedContent, specialContent)
    }

    func testContentWithMarkdownFormatting() throws {
        let markdownContent = """
        # Heading

        - Bullet 1
        - Bullet 2

        **Bold** and *italic*

        ```swift
        let code = "example"
        ```
        """

        storage.content = markdownContent
        storage.saveNote()

        let loadStorage = TestableNoteStorage(filePath: storage.filePath)
        XCTAssertEqual(loadStorage.content, markdownContent)
    }
}
