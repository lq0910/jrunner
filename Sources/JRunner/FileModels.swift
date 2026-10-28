import Foundation
import Combine

// MARK: - 文件节点

struct FileNode: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    var id: String { path }

    var ext: String {
        (name as NSString).pathExtension.lowercased()
    }

}

// MARK: - 文件树模型

final class FileTreeModel: ObservableObject {

    let root: String
    @Published private(set) var childrenMap: [String: [FileNode]] = [:]
    @Published private(set) var expanded: Set<String> = []
    @Published private(set) var searchResults: [FileNode] = []
    @Published var filter: String = ""

    /// 构建/依赖目录不展示,避免干扰
    private let skipDirs: Set<String> = [
        ".git", ".idea", ".gradle", ".mvn", ".settings", "build", "target",
        "node_modules", "out", "bin", "obj", "dist", ".next", ".cache",
        "logs", "log", ".DS_Store", "__pycache__", ".venv", "venv"
    ]

    private var searchGen = 0

    init(root: String) {
        self.root = root
        load(root)
        // 默认展开根
        expanded.insert(root)
    }

    func children(of dir: String) -> [FileNode] {
        childrenMap[dir] ?? []
    }

    /// 读取目录内容(后台读取,主线程赋值)
    func load(_ dir: String) {
        guard childrenMap[dir] == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let nodes = FileTreeModel.readDirectory(dir, skip: self.skipDirs)
            DispatchQueue.main.async {
                self.childrenMap[dir] = nodes
            }
        }
    }

    private static func readDirectory(_ dir: String, skip: Set<String>) -> [FileNode] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        var nodes: [FileNode] = []
        for name in names {
            if name.hasPrefix(".") && name != ".gitignore" && name != ".env" && name != ".editorconfig" { continue }
            if skip.contains(name) { continue }
            let full = dir + "/" + name
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            // 跳过符号链接,避免环路
            if let attrs = try? fm.attributesOfItem(atPath: full),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink { continue }
            nodes.append(FileNode(path: full, name: name, isDirectory: isDir.boolValue))
        }

        // 目录在前,同类按名称排序
        nodes.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return nodes
    }

    func toggle(_ node: FileNode) {
        guard node.isDirectory else { return }
        if expanded.contains(node.path) {
            expanded.remove(node.path)
        } else {
            expanded.insert(node.path)
            load(node.path)
        }
    }

    func reload() {
        childrenMap.removeAll()
        expanded = [root]
        load(root)
    }

    /// 展开到指定文件所在目录
    func reveal(_ path: String) {
        var dir = (path as NSString).deletingLastPathComponent
        var toExpand: [String] = []
        while dir.count >= root.count && dir.hasPrefix(root) {
            toExpand.append(dir)
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        for d in toExpand { expanded.insert(d); load(d) }
    }

    /// 扁平化当前可见行(依赖展开状态)
    func visibleRows() -> [(node: FileNode, depth: Int)] {
        var out: [(FileNode, Int)] = []
        func walk(_ dir: String, _ depth: Int) {
            guard depth < 14 else { return }
            for node in children(of: dir) {
                out.append((node, depth))
                if node.isDirectory, expanded.contains(node.path) {
                    walk(node.path, depth + 1)
                }
            }
        }
        walk(root, 0)
        return out
    }

    // MARK: 搜索

    func updateSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        searchGen += 1
        let gen = searchGen

        guard !q.isEmpty else {
            searchResults = []
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var results: [FileNode] = []
            var visited = 0

            func walk(_ dir: String, _ depth: Int) {
                guard depth < 10, visited < 4000, results.count < 200 else { return }
                let fm = FileManager.default
                guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
                for name in names {
                    visited += 1
                    if name.hasPrefix(".") && name != ".gitignore" && name != ".env" { continue }
                    if self.skipDirs.contains(name) { continue }
                    let full = dir + "/" + name
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
                    if isDir.boolValue {
                        walk(full, depth + 1)
                    } else if name.lowercased().contains(q) {
                        results.append(FileNode(path: full, name: name, isDirectory: false))
                    }
                }
            }
            walk(self.root, 0)

            DispatchQueue.main.async {
                if gen == self.searchGen { self.searchResults = results }
            }
        }
    }
}

// MARK: - 编辑器模型

final class EditorModel: ObservableObject {

    @Published var currentPath: String?
    @Published var text: String = ""
    @Published private(set) var savedText: String = ""
    @Published var errorMessage: String?
    @Published var isBinary = false

    /// 未保存的草稿,切换文件时不丢修改
    private var drafts: [String: String] = [:]

    var isDirty: Bool {
        currentPath != nil && !isBinary && text != savedText
    }

    var fileName: String {
        currentPath.map { ($0 as NSString).lastPathComponent } ?? ""
    }

    var relativePath: String {
        guard let currentPath else { return "" }
        let parts = currentPath.components(separatedBy: "/")
        // 取最后三段,够识别
        return parts.suffix(3).joined(separator: "/")
    }

    /// 打开文件
    func open(_ path: String) {
        // 保存当前草稿
        if let current = currentPath, !isBinary {
            drafts[current] = text
        }

        errorMessage = nil
        isBinary = false
        currentPath = path

        if let draft = drafts[path] {
            text = draft
            savedText = (try? String(contentsOfFile: path, encoding: .utf8)) ?? draft
            return
        }

        let url = URL(fileURLWithPath: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int else {
            errorMessage = "无法读取文件"
            text = ""
            savedText = ""
            return
        }
        if size > 2_000_000 {
            errorMessage = "文件过大(\(size / 1024) KB),不支持编辑"
            text = ""
            savedText = ""
            return
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "无法以 UTF-8 文本打开,可能是二进制文件"
            isBinary = true
            text = ""
            savedText = ""
            return
        }
        text = content
        savedText = content
    }

    /// 记录草稿(编辑时调用)
    func markEdited() {
        guard let currentPath, !isBinary else { return }
        drafts[currentPath] = text
    }

    /// 保存
    @discardableResult
    func save() -> Bool {
        guard let path = currentPath, !isBinary else { return false }
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            savedText = text
            drafts[path] = nil
            return true
        } catch {
            errorMessage = "保存失败: \(error.localizedDescription)"
            return false
        }
    }

    func close() {
        if let current = currentPath, !isBinary {
            drafts[current] = text
        }
        currentPath = nil
        text = ""
        savedText = ""
        errorMessage = nil
        isBinary = false
    }
}

