import SwiftUI
import Foundation


// MARK: - 文件图标

extension FileNode {
    var icon: (name: String, color: Color) {
        if isDirectory { return ("folder.fill", .jrPrimary.opacity(0.75)) }
        switch ext {
        case "kt": return ("k.square.fill", .jrPurple)
        case "java": return ("cup.and.saucer.fill", .jrWarning)
        case "yaml", "yml": return ("doc.text.fill", .jrSuccess)
        case "xml": return ("chevron.left.forwardslash.chevron.right", .jrWarning)
        case "properties": return ("slider.horizontal.3", .jrTextSecondary)
        case "json": return ("curlybraces", .jrWarning)
        case "gradle", "kts": return ("hammer.fill", .jrPrimary)
        case "sql": return ("cylinder.split.1x2.fill", .jrSuccess)
        case "md": return ("text.alignleft", .jrTextSecondary)
        case "sh": return ("terminal.fill", .jrTextSecondary)
        case "png", "jpg", "jpeg", "gif", "svg": return ("photo.fill", .jrPurple)
        case "jar", "class": return ("shippingbox.fill", .jrTextTertiary)
        default: return ("doc.fill", .jrTextTertiary)
        }
    }
}

// MARK: - 文件树视图

struct FileTreeView: View {
    let project: Project
    let onOpen: (String) -> Void

    @StateObject private var model: FileTreeModel
    @State private var filterText = ""

    init(project: Project, onOpen: @escaping (String) -> Void) {
        self.project = project
        self.onOpen = onOpen
        _model = StateObject(wrappedValue: FileTreeModel(root: project.path))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jrTextTertiary)
                TextField("查找文件,如 application-dev", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onChange(of: filterText) { v in
                        model.updateSearch(v)
                    }
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                        model.updateSearch("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.jrTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    model.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jrTextSecondary)
                }
                .buttonStyle(.plain)
                .help("刷新文件树")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Divider().overlay(Color.jrBorder.opacity(0.6))

            if filterText.isEmpty {
                treeList
            } else {
                searchList
            }
        }
        .background(Color.jrCard)
    }

    private var treeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.visibleRows(), id: \.node.id) { row in
                    FileRow(node: row.node,
                            depth: row.depth,
                            isExpanded: model.expanded.contains(row.node.path),
                            subtitle: nil)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if row.node.isDirectory {
                                model.toggle(row.node)
                            } else {
                                onOpen(row.node.path)
                            }
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var searchList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.searchResults.isEmpty {
                    Text("无匹配文件")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.jrTextTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }
                ForEach(model.searchResults) { node in
                    let rel = node.path.replacingOccurrences(of: project.path + "/", with: "")
                    FileRow(node: node, depth: 0, isExpanded: false,
                            subtitle: (rel as NSString).deletingLastPathComponent)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(node.path) }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 文件行

private struct FileRow: View {
    let node: FileNode
    let depth: Int
    let isExpanded: Bool
    let subtitle: String?

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 5) {
            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.jrTextTertiary)
                    .frame(width: 9)
            } else {
                Color.clear.frame(width: 9)
            }

            Image(systemName: node.icon.name)
                .font(.system(size: 10))
                .foregroundStyle(node.icon.color)
                .frame(width: 13)

            VStack(alignment: .leading, spacing: 0) {
                Text(node.name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.jrTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.jrTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 12 + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(hovered ? Color.jrBg : Color.clear)
        )
        .onHover { hovered = $0 }
    }
}

// MARK: - 编辑器视图

struct FileEditorView: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Color.jrBorder.opacity(0.6))

            if editor.currentPath == nil {
                EmptyStateView(icon: "doc.text",
                               title: "未打开文件",
                               subtitle: "在左侧文件树中选择文件\n可直接编辑并保存配置")
            } else if let err = editor.errorMessage, editor.text.isEmpty {
                EmptyStateView(icon: "exclamationmark.triangle",
                               title: "无法打开",
                               subtitle: err)
            } else {
                editorBody
            }
        }
        .background(Color.jrCard)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.jrTextTertiary)

            if let _ = editor.currentPath {
                Text(editor.fileName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.jrTextPrimary)
                    .lineLimit(1)
                if editor.isDirty {
                    Circle().fill(Color.jrWarning).frame(width: 6, height: 6)
                        .help("有未保存的修改")
                }
                Text(editor.relativePath)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color.jrTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .layoutPriority(-1)
            } else {
                Text("编辑器")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.jrTextSecondary)
            }

            Spacer(minLength: 4)

            if editor.currentPath != nil {
                Text("\(lineCount) 行")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jrTextTertiary)

                Button {
                    if editor.save() {
                        store.statusMessage = "已保存 \(editor.fileName)"
                        store.refreshGit()
                    }
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .disabled(!editor.isDirty)
                .help("保存 (⌘S)")

                Button {
                    editor.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .help("关闭文件")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.jrBg)
    }

    private var lineCount: Int {
        editor.text.isEmpty ? 0 : editor.text.components(separatedBy: .newlines).count
    }

    /// 依据当前文件扩展名决定高亮语法
    private var language: SyntaxLanguage {
        guard let path = editor.currentPath else { return .plain }
        return SyntaxLanguage.from(ext: (path as NSString).pathExtension)
    }

    private var editorBody: some View {
        ZStack(alignment: .top) {
            Color.jrCard

            CodeEditor(
                text: Binding(
                    get: { editor.text },
                    set: { newValue in
                        editor.text = newValue
                        editor.markEdited()
                    }
                ),
                language: language,
                onChange: { editor.markEdited() }
            )

            if let err = editor.errorMessage {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(err)
                            .font(.system(size: 11))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.jrDanger.opacity(0.12))
                    .foregroundStyle(Color.jrDanger)
                    Spacer()
                }
            }
        }
    }
}
