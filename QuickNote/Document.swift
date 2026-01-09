import Foundation

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
