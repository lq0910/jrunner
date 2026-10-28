import SwiftUI

// MARK: - 项目侧边栏

struct ProjectSidebar: View {
    @ObservedObject var store: AppStore
    @State private var showAddSheet = false

    /// 重名项目需要显示父目录加以区分
    /// 重名项目需要显示父目录加以区分
    private var duplicatedNames: Set<String> {
        var counts: [String: Int] = [:]
        for p in store.projects { counts[p.name, default: 0] += 1 }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    private var filteredProjects: [Project] {
        let q = store.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.projects }
        return store.projects.filter { p in
            if p.name.lowercased().contains(q) { return true }
            if p.path.lowercased().contains(q) { return true }
            return p.modules.contains { $0.name.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：搜索 + 刷新
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.jrTextTertiary)
                    .frame(width: 14)

                TextField("搜索项目或模块", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.jrTextPrimary)
                    .layoutPriority(1)

                // 固定占位,避免出现/消失时挤压刷新按钮造成"飘动"
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.jrTextTertiary)
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
                .opacity(store.searchText.isEmpty ? 0 : 1)
                .disabled(store.searchText.isEmpty)
                .help("清空搜索")

                Button {
                    store.scanProjects()
                } label: {
                    SpinningIcon(systemName: "arrow.clockwise",
                                 isSpinning: store.isScanning,
                                 size: 11,
                                 weight: .semibold,
                                 color: store.isScanning ? .jrTextTertiary : .jrPrimary)
                }
                .buttonStyle(.plain)
                .disabled(store.isScanning)
                .help(store.isScanning ? "正在扫描…" : "重新扫描")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.jrBg)

            Divider().overlay(Color.jrBorder.opacity(0.6))

            // 项目列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if filteredProjects.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: store.projects.isEmpty ? "folder.badge.questionmark" : "magnifyingglass")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(Color.jrTextTertiary)
                            Text(store.projects.isEmpty ? "未发现项目" : "无匹配结果")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.jrTextSecondary)
                            if store.projects.isEmpty {
                                Text("点击 + 添加项目目录")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.jrTextTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }

                    ForEach(filteredProjects) { project in
                        ProjectRow(
                            project: project,
                            isSelected: store.selectedProject?.id == project.id,
                            isRunning: project.modules.contains { store.isRunning(module: $0, in: project) },
                            showParent: duplicatedNames.contains(project.name),
                            git: store.git
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { store.select(project: project) }
                        .contextMenu {
                            Button("在 Finder 中打开") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
                            }
                            Button("重新识别该项目") {
                                store.addProject(at: project.path)
                            }
                            Divider()
                            Button("移除项目") {
                                store.removeProject(project)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Divider().overlay(Color.jrBorder.opacity(0.6))

            // 底部：添加 + 设置
            HStack(spacing: 6) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加项目", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))

                Spacer()

                Button {
                    store.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.jrTextSecondary)
                }
                .buttonStyle(.plain)
                .help("设置")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.jrBg)
        }
        .background(Color.jrCard)
        .sheet(isPresented: $showAddSheet) {
            AddProjectSheet(store: store)
        }
    }
}

// MARK: - 项目行

private struct ProjectRow: View {
    let project: Project
    let isSelected: Bool
    let isRunning: Bool
    let showParent: Bool
    @ObservedObject var git: GitMonitor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.tool == .gradle ? "cube.box" : "hexagon")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.jrPrimary : Color.jrTextTertiary)
                .frame(width: 16)

            if isRunning {
                Circle().fill(Color.jrSuccess).frame(width: 5, height: 5)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.jrTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitleText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.jrTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 行尾显示当前分支,一眼看出各项目在哪个分支
            GitBranchBadge(monitor: git, path: project.path, style: .subtle, maxWidth: 90)
                .layoutPriority(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.jrPrimaryLight : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.jrPrimary)
                    .frame(width: 2.5)
                    .padding(.vertical, 5)
            }
        }
    }

    /// 副标题拼成一行,避免多个 Text 在窄栏里被挤散
    private var subtitleText: String {
        var parts: [String] = []
        if showParent {
            let parent = (project.path as NSString).deletingLastPathComponent
            let last = parent.components(separatedBy: "/").last ?? ""
            if !last.isEmpty { parts.append(last) }
        }
        parts.append(project.language.rawValue)
        if let jv = project.requiredJava { parts.append("JDK \(jv)") }
        parts.append("\(project.modules.count) 模块")
        return parts.joined(separator: " · ")
    }
}

// MARK: - 添加项目

struct AddProjectSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var isScanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("添加项目")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.jrTextPrimary)
                Text("输入项目的绝对路径,例如 /Users/you/IdeaProjects/community-backend")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.jrTextSecondary)
            }

            HStack(spacing: 8) {
                TextField("/path/to/project", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { add() }

                Button("选择…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        path = url.path
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            HStack {
                if isScanning {
                    ProgressView().controlSize(.small)
                    Text("正在识别…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.jrTextSecondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("添加") { add() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(path.isEmpty || isScanning)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Color.jrBg)
    }

    private func add() {
        let p = path.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        isScanning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            store.addProject(at: p)
            isScanning = false
            dismiss()
        }
    }
}
