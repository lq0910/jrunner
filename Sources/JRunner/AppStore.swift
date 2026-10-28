import Foundation
import Combine
import SwiftUI

/// 应用主状态
final class AppStore: ObservableObject {

    /// 供 AppDelegate 在退出时清理子进程
    static weak var shared: AppStore?

    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    @Published var selectedModule: Module?

    /// 任务表,key 为 "项目路径||模块路径",避免不同项目的同名模块互相覆盖
    @Published var tasks: [String: ProcessTask] = [:]
    @Published var activeTaskID: UUID?

    @Published var jdks: [JDK] = []
    @Published var config = AppConfig.load()

    /// 文件编辑器(供文件树打开文件)
    let editor = EditorModel()

    /// Git 分支状态(按项目路径缓存)
    let git = GitMonitor()

    @Published var searchText: String = ""
    @Published var isScanning = false
    @Published var statusMessage: String = ""
    @Published var showSettings = false

    /// 扫描根目录列表
    @Published var scanRoots: [String] = []
    /// 用户手动添加的项目路径(持久化)
    @Published var manualProjects: [String] = []

    private let defaults = UserDefaults.standard
    private static let manualKey = "manualProjectPaths"
    private static let rootsKey = "scanRoots"

    init() {
        AppStore.shared = self
        loadScanRoots()
        manualProjects = defaults.stringArray(forKey: AppStore.manualKey) ?? []
        refreshJDKs()
    }

    // MARK: - 任务 key

    static func taskKey(project: String, module: String) -> String {
        project + "||" + module
    }

    func task(for project: Project, module: Module) -> ProcessTask? {
        tasks[AppStore.taskKey(project: project.path, module: module.path)]
    }

    // MARK: - Roots

    func loadScanRoots() {
        if let roots = defaults.stringArray(forKey: AppStore.rootsKey), !roots.isEmpty {
            scanRoots = roots
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let candidates = [
                "Documents/code", "Documents/codeyd", "Documents/app",
                "Documents/Projects", "Documents/workspace", "Documents/code-workspace",
                "Documents", "Projects", "workspace", "IdeaProjects", "work", "code", "dev"
            ]
            .map { home.appendingPathComponent($0).path }
            .filter { FileManager.default.fileExists(atPath: $0) }
            scanRoots = candidates
        }
    }

    func saveScanRoots() {
        defaults.set(scanRoots, forKey: AppStore.rootsKey)
    }

    // MARK: - JDK

    func refreshJDKs() {
        DispatchQueue.global(qos: .userInitiated).async {
            let list = JDKResolver.installedJDKs(forceRefresh: true)
            DispatchQueue.main.async { self.jdks = list }
        }
    }

    // MARK: - 扫描

    func scanProjects() {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "正在扫描..."
        let roots = scanRoots
        let manual = manualProjects
        let lastOpened = config.lastOpenedProject

        DispatchQueue.global(qos: .userInitiated).async {
            var found: [Project] = []
            let lock = NSLock()

            // 1. 各根目录并行扫描
            DispatchQueue.concurrentPerform(iterations: roots.count) { i in
                var localBudget = 4000
                let list = self.discoverProjects(at: roots[i], depth: 5, budget: &localBudget)
                lock.lock()
                found.append(contentsOf: list)
                lock.unlock()
            }

            // 2. 手动添加的项目优先保留
            for path in manual {
                if found.contains(where: { $0.path == path }) { continue }
                if let p = ProjectScanner.scan(at: path) { found.append(p) }
            }

            // 按路径去重
            var seen = Set<String>()
            var unique: [Project] = []
            for p in found where !seen.contains(p.path) {
                seen.insert(p.path)
                unique.append(p)
            }
            unique.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                self.projects = unique
                self.isScanning = false
                self.statusMessage = unique.isEmpty
                    ? "未发现项目,点击左下角「添加项目」"
                    : "发现 \(unique.count) 个项目"

                // 恢复上次选中的项目
                if let lastOpened, let p = unique.first(where: { $0.path == lastOpened }) {
                    self.select(project: p)
                } else if let first = unique.first, self.selectedProject == nil {
                    self.select(project: first)
                }

                // 侧边栏各项目的分支(只读 HEAD,开销极小)
                self.refreshAllBranches()
            }
        }
    }

    /// 递归查找项目(限制深度与遍历预算)
    private func discoverProjects(at dir: String, depth: Int, budget: inout Int) -> [Project] {
        guard depth > 0, budget > 0 else { return [] }
        budget -= 1
        var results: [Project] = []

        if let p = ProjectScanner.scan(at: dir) {
            results.append(p)
            // 已是多模块项目,不再深入,避免重复
            if p.modules.count > 1 { return results }
        }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return results }

        let skip: Set<String> = [".git", ".idea", "node_modules", "build", "target", "out",
                                 ".gradle", ".mvn", "bin", "obj", "Pods", ".workbuddy-ai",
                                 "Library", "Applications", "Music", "Movies", "Pictures"]
        for e in entries.sorted() {
            if e.hasPrefix(".") || skip.contains(e) { continue }
            let sub = dir + "/" + e
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sub, isDirectory: &isDir), isDir.boolValue else { continue }
            results.append(contentsOf: discoverProjects(at: sub, depth: depth - 1, budget: &budget))
        }
        return results
    }

    /// 添加单个项目目录
    func addProject(at path: String) {
        let normalized = (path as NSString).expandingTildeInPath
        statusMessage = "正在识别 \(((normalized as NSString).lastPathComponent))..."

        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = ProjectScanner.scan(at: normalized)
            DispatchQueue.main.async {
                guard let p = scanned else {
                    self.statusMessage = "该目录不是 Gradle / Maven 项目"
                    return
                }
                if !self.projects.contains(where: { $0.path == p.path }) {
                    self.projects.append(p)
                    self.projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                }
                // 持久化手动添加的路径
                if !self.manualProjects.contains(p.path) {
                    self.manualProjects.append(p.path)
                    self.defaults.set(self.manualProjects, forKey: AppStore.manualKey)
                }
                self.select(project: p)
                self.statusMessage = "已添加 \(p.name) · \(p.modules.count) 个模块"
            }
        }
    }

    /// 移除项目
    func removeProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        manualProjects.removeAll { $0 == project.path }
        defaults.set(manualProjects, forKey: AppStore.manualKey)
        // 清理该项目的任务
        let prefix = project.path + "||"
        for key in tasks.keys where key.hasPrefix(prefix) {
            tasks[key]?.stop()
            tasks.removeValue(forKey: key)
        }
        if selectedProject?.id == project.id {
            selectedProject = projects.first
            selectedModule = selectedProject?.modules.first
        }
    }

    // MARK: - 选择

    func select(project: Project) {
        selectedProject = project
        selectedModule = project.modules.first
        config.lastOpenedProject = project.path
        config.save()
        git.refresh(path: project.path)
    }

    /// 刷新 Git 分支状态(应用回到前台、保存文件后调用)
    func refreshGit(force: Bool = true) {
        guard let project = selectedProject else { return }
        git.refresh(path: project.path, force: force)
    }

    /// 仅重新读分支(轻量,扫描完成后批量更新侧边栏)
    func refreshAllBranches() {
        git.refreshBranches(paths: projects.map(\.path))
    }

    // MARK: - 执行

    /// 启动模块
    func run(module: Module) {
        guard let project = selectedProject else { return }
        let key = AppStore.taskKey(project: project.path, module: module.path)

        if let existing = tasks[key], existing.state.isActive {
            activeTaskID = existing.id
            return
        }

        let cfg = config.config(for: project.path, module: module.path)
        let jdk = JDKResolver.resolve(version: cfg.javaVersion ?? module.javaVersion ?? project.requiredJava)

        guard var cmd = TaskPlanner.runCommand(project: project, module: module, profile: cfg.profile, jdk: jdk) else {
            statusMessage = "无法构造启动命令:未找到 gradlew / mvnw / gradle / mvn"
            return
        }
        for (k, v) in cfg.envVars { cmd.environment[k] = v }
        cmd.arguments.append(contentsOf: cfg.extraArgs)

        let task = ProcessTask(command: cmd, title: "启动 \(module.name)", subtitle: cmd.displayCommand)
        tasks[key] = task
        activeTaskID = task.id
        task.start()
        statusMessage = "正在启动 \(module.name)..."
    }

    /// 打包模块
    func build(module: Module) {
        guard let project = selectedProject else { return }
        let key = AppStore.taskKey(project: project.path, module: module.path)

        if let existing = tasks[key], existing.state.isActive {
            activeTaskID = existing.id
            return
        }

        let cfg = config.config(for: project.path, module: module.path)
        let jdk = JDKResolver.resolve(version: cfg.javaVersion ?? module.javaVersion ?? project.requiredJava)

        guard var cmd = TaskPlanner.buildCommand(project: project, module: module, profile: cfg.profile, jdk: jdk) else {
            statusMessage = "无法构造打包命令:未找到 gradlew / mvnw / gradle / mvn"
            return
        }
        for (k, v) in cfg.envVars { cmd.environment[k] = v }
        cmd.arguments.append(contentsOf: cfg.extraArgs)

        let task = ProcessTask(command: cmd, title: "打包 \(module.name)", subtitle: cmd.displayCommand)
        tasks[key] = task
        activeTaskID = task.id
        task.start()
        statusMessage = "正在打包 \(module.name)..."
    }

    func stop(module: Module) {
        guard let project = selectedProject else { return }
        tasks[AppStore.taskKey(project: project.path, module: module.path)]?.stop()
    }

    func isRunning(module: Module) -> Bool {
        guard let project = selectedProject else { return false }
        return tasks[AppStore.taskKey(project: project.path, module: module.path)]?.state.isActive ?? false
    }

    func isRunning(module: Module, in project: Project) -> Bool {
        tasks[AppStore.taskKey(project: project.path, module: module.path)]?.state.isActive ?? false
    }

    /// 退出前停掉所有子进程
    func stopAll() {
        for t in tasks.values where t.state.isActive {
            t.stop()
        }
    }

    // MARK: - 配置

    func updateConfig(project: String, module: String, config: ModuleConfig) {
        self.config.setConfig(config, for: project, module: module)
        self.config.save()
    }

    /// 当前生效的 profile:用户设置优先,否则用项目声明
    func effectiveProfile(project: Project, module: Module) -> String? {
        config.config(for: project.path, module: module.path).profile ?? module.defaultProfile
    }

    /// 切换模块的 Spring profile
    func setProfile(_ profile: String?, project: Project, module: Module) {
        var cfg = config.config(for: project.path, module: module.path)
        cfg.profile = profile
        updateConfig(project: project.path, module: module.path, config: cfg)
    }
}
