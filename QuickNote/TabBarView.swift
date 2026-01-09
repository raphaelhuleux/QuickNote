import SwiftUI

struct TabBarView: View {
    @ObservedObject var manager: DocumentManager

    // Colors matching the app theme
    private let tabBarBackground = Color(red: 0.10, green: 0.10, blue: 0.11) // #1a1a1c
    private let activeTabColor = Color(red: 0.129, green: 0.133, blue: 0.149) // #212226
    private let inactiveTabColor = Color(red: 0.08, green: 0.08, blue: 0.09) // #141417
    private let textColor = Color(red: 0.925, green: 0.937, blue: 0.957) // #ECEFF4
    private let dimTextColor = Color(red: 0.6, green: 0.6, blue: 0.65)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(manager.documents) { document in
                    TabItemView(
                        document: document,
                        isActive: manager.activeDocumentId == document.id,
                        activeTabColor: activeTabColor,
                        inactiveTabColor: inactiveTabColor,
                        textColor: textColor,
                        dimTextColor: dimTextColor,
                        onSelect: {
                            manager.setActiveDocument(document)
                        },
                        onClose: {
                            manager.closeDocument(document)
                        }
                    )
                }

                // New tab button
                Button(action: {
                    manager.newDocument()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(dimTextColor)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)

                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 32)
        .background(tabBarBackground)
    }
}

struct TabItemView: View {
    @ObservedObject var document: Document
    let isActive: Bool
    let activeTabColor: Color
    let inactiveTabColor: Color
    let textColor: Color
    let dimTextColor: Color
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Dirty indicator
            if document.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }

            // Filename
            Text(document.fileName)
                .font(.system(size: 12))
                .foregroundColor(isActive ? textColor : dimTextColor)
                .lineLimit(1)

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(dimTextColor)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(isHovering ? Color.white.opacity(0.1) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isActive ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? activeTabColor : (isHovering ? inactiveTabColor : Color.clear))
        )
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
