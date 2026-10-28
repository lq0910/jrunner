import Foundation
import Combine

// MARK: - Git 状态

struct GitStatus: Equatable {
    /// 分支名;detached HEAD 时为短 SHA;空字符串表示不是 git 仓库
    var branch: String
    var isDetached: Bool
    var isDirty: Bool
    var changedCount: Int

    static let none = GitStatus(branch: "", isDetached: false, isDirty: false, changedCount: 0)

    var isRepo: Bool { !branch.isEmpty }

    var tooltip: String {
        guard isRepo else { return "不是 Git 仓库" }
        var s = isDetached ? "游离 HEAD:\(branch)" : "当前分支:\(branch)"
        if isDirty { s += "\n\(changedCount) 个文件有未提交修改" }
        return s
    }
}

// MARK: - 读取(不依赖 git 进程读分支,极快)

enum GitReader {

    /// 向上查找仓库根目录(项目可能只是仓库里的一个子目录)
    static func repoRoot(from path: String) -> String? {
        var cur = path
        var depth = 0
        while depth < 16 {
            if FileManager.default.fileExists(atPath: cur + "/.git") { return cur }
            let parent = (cur as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == cur { return nil }
            cur = parent
            depth += 1
        }
        return nil
    }

    /// 解析出真正的 .git 目录(兼容 worktree / submodule 的 .git 文件)
    static func gitDir(for repoPath: String) -> String? {
        guard let root = repoRoot(from: repoPath) else { return nil }
        let dotGit = root + "/.git"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return dotGit }

        guard let content = try? String(contentsOfFile: dotGit, encoding: .utf8) else { return nil }
        for line in content.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("gitdir:") else { continue }
            let p = String(s.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return nil }
            return p.hasPrefix("/") ? p : root + "/" + p
        }
        return nil
    }

    /// 读 .git/HEAD,返回 (显示名, 是否 detached)
    static func readHead(repoPath: String) -> (branch: String, detached: Bool)? {
        guard let dir = gitDir(for: repoPath),
              let head = try? String(contentsOfFile: dir + "/HEAD", encoding: .utf8) else { return nil }

        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref:") {
            let ref = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            let prefix = "refs/heads/"
            let name = ref.hasPrefix(prefix) ? String(ref.dropFirst(prefix.count)) : ref
            return (name, false)
        }
        // detached HEAD:HEAD 里直接是完整 SHA
        if trimmed.count >= 7 { return (String(trimmed.prefix(7)), true) }
        return nil
    }

    /// 工作区是否有改动(忽略未跟踪文件,避免 build/ 目录干扰)
    static func readWorkingTree(repoPath: String) -> (dirty: Bool, count: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repoPath, "status", "--porcelain",
                       "--untracked-files=no", "--ignore-submodules=dirty"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        p.environment = env

        do { try p.run() } catch { return (false, 0) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let out = String(data: data, encoding: .utf8) ?? ""
        let n = out.split(separator: "\n").filter { !$0.isEmpty }.count
        return (n > 0, n)
    }
}

// MARK: - 监听器

/// 按项目路径缓存 Git 状态。读分支走文件,极快;查改动才起 git 进程,放后台。
final class GitMonitor: ObservableObject {

    @Published private(set) var statuses: [String: GitStatus] = [:]

    private let queue = DispatchQueue(label: "jrunner.git", qos: .utility, attributes: .concurrent)
    private var inFlight = Set<String>()
    private var lastRun: [String: Date] = [:]
    private let lock = NSLock()

    func status(for path: String) -> GitStatus? {
        statuses[path]
    }

    /// 刷新某个项目的 Git 状态
    /// - Parameter force: false 时 2 秒内不重复起 git 进程(切项目时避免抖动)
    func refresh(path: String, force: Bool = false) {
        lock.lock()
        if inFlight.contains(path) { lock.unlock(); return }
        if !force, let t = lastRun[path], Date().timeIntervalSince(t) < 2 { lock.unlock(); return }
        inFlight.insert(path)
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }

            guard let head = GitReader.readHead(repoPath: path) else {
                DispatchQueue.main.async {
                    self.finish(path, GitStatus.none)
                }
                return
            }
            let wt = GitReader.readWorkingTree(repoPath: path)
            let st = GitStatus(branch: head.branch,
                               isDetached: head.detached,
                               isDirty: wt.dirty,
                               changedCount: wt.count)
            DispatchQueue.main.async {
                self.finish(path, st)
            }
        }
    }

    /// 批量刷新(只读分支,不查改动,开销极小)
    func refreshBranches(paths: [String]) {
        queue.async { [weak self] in
            guard let self else { return }
            var result: [String: GitStatus] = [:]
            for p in paths {
                if let head = GitReader.readHead(repoPath: p) {
                    let old = self.statuses[p]
                    result[p] = GitStatus(branch: head.branch,
                                          isDetached: head.detached,
                                          isDirty: old?.isDirty ?? false,
                                          changedCount: old?.changedCount ?? 0)
                } else {
                    result[p] = GitStatus.none
                }
            }
            DispatchQueue.main.async {
                for (k, v) in result where self.statuses[k] != v {
                    self.statuses[k] = v
                }
            }
        }
    }

    private func finish(_ path: String, _ st: GitStatus) {
        lock.lock()
        inFlight.remove(path)
        lastRun[path] = Date()
        lock.unlock()
        if statuses[path] != st { statuses[path] = st }
    }
}
