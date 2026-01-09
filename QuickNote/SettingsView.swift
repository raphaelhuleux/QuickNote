import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager = DocumentManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Toggle QuickNote:")
                    Spacer()
                    Text("⌥ O")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }
                Text("Custom shortcuts coming in a future update")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Keyboard Shortcut")
            }

            Section {
                HStack {
                    Text("Default folder:")
                    Spacer()
                    Text(manager.defaultFolder)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("Choose Folder...") {
                    manager.selectDefaultFolder()
                }
            } header: {
                Text("Default Save Location")
            }

            Section {
                Button("Reveal Default Folder in Finder") {
                    let url = URL(fileURLWithPath: manager.defaultFolder)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }
            } header: {
                Text("Actions")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 280)
    }
}
