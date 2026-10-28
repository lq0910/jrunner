import SwiftUI

// MARK: - 主界面

/// 工作区模式:模块列表 ↔ 调试日志、文件树 ↔ 代码编辑器,成对联动
enum Workspace: Int, Equatable {
    case modules = 0
    case files = 1

    /// 中栏推荐宽度:模块行要放下名称 + 语言 + 徽章 + JDK;文件树只需放下路径
    var preferredMiddleWidth: CGFloat {
        switch self {
        case .modules: return 430
        case .files:   return 300
        }
    }
}

struct MainView: View {
    @ObservedObject var store: AppStore

    @State private var workspace: Workspace
    @State private var sidebarWidth: CGFloat = 268
    @State private var middleWidth: CGFloat

    private let sidebarMin: CGFloat = 220
    private let sidebarMax: CGFloat = 380
    private let middleMin: CGFloat = 260
    private let rightMin: CGFloat = 360

    init(store: AppStore, initialWorkspace: Workspace = .modules) {
        self.store = store
        _workspace = State(initialValue: initialWorkspace)
        _middleWidth = State(initialValue: initialWorkspace.preferredMiddleWidth)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                titleBar

                Divider().overlay(Color.jrBorder.opacity(0.6))

                HStack(spacing: 0) {
                    ProjectSidebar(store: store)
                        .frame(width: sidebarWidth)

                    SplitHandle(width: $sidebarWidth, minValue: sidebarMin, maxValue: sidebarMax)

                    middlePanel
                        .frame(width: middleWidth)

                    SplitHandle(width: $middleWidth,
                                minValue: middleMin,
                                maxValue: maxMiddleWidth(total: geo.size.width))

                    rightPanel
                        .frame(maxWidth: .infinity)
                }

                statusBar
            }
            .background(Color.jrBg)
            .onAppear {
                middleWidth = clampMiddle(workspace.preferredMiddleWidth, total: geo.size.width)
            }
            .onChange(of: workspace) { newValue in
                withAnimation(.easeInOut(duration: 0.18)) {
                    middleWidth = clampMiddle(newValue.preferredMiddleWidth, total: geo.size.width)
                }
            }
            .onChange(of: geo.size.width) { w in
                // 窗口变窄时先保证右侧主区域可用,再收回中栏
                if sidebarWidth > max(sidebarMin, w - middleMin - rightMin) {
                    sidebarWidth = max(sidebarMin, w - middleMin - rightMin)
                }
                if middleWidth > maxMiddleWidth(total: w) {
                    middleWidth = max(middleMin, maxMiddleWidth(total: w))
                }
            }
        }
        .frame(minWidth: 1080, minHeight: 640)
        .sheet(isPresented: $store.showSettings) {
            SettingsSheet(store: store)
        }
    }

    private func maxMiddleWidth(total: CGFloat) -> CGFloat {
        max(middleMin, total - sidebarWidth - rightMin - 14)
    }

    private func clampMiddle(_ value: CGFloat, total: CGFloat) -> CGFloat {
        min(max(middleMin, value), maxMiddleWidth(total: total))
    }

    // MARK: 中栏

    @ViewBuilder
    private var middlePanel: some View {
        switch workspace {
        case .files:
            if let project = store.selectedProject {
                FileTreeView(project: project) { path in
                    store.editor.open(path)
                    workspace = .files
                }
            } else {
                EmptyStateView(icon: "folder", title: "未选择项目", subtitle: "从左侧选择项目后浏览文件")
            }
        case .modules:
            ModuleDetailPanel(store: store)
        }
    }

    // MARK: 右栏

    @ViewBuilder
    private var rightPanel: some View {
        switch workspace {
        case .files:
            FileEditorView(editor: store.editor, store: store)
        case .modules:
            LogConsole(store: store)
        }
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            // Logo
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.36),
                                                  Color(red: 0.91, green: 0.41, blue: 0.15)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 26)
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("JRunner")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.jrTextPrimary)
                Text("Java / Kotlin 服务启动器")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.jrTextTertiary)
            }

            // 当前分支(跟随选中项目)
            if let project = store.selectedProject {
                Rectangle()
                    .fill(Color.jrBorder)
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 2)

                GitBranchBadge(monitor: store.git, path: project.path)

                Text(project.name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.jrTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .leading)
            }

            Spacer()

            // 工作区切换(两组联动)
            Picker("", selection: Binding(
                get: { workspace == .files },
                set: { workspace = $0 ? .files : .modules }
            )) {
                Image(systemName: "square.stack.3d.up").tag(false)
                Image(systemName: "folder").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 82)
            .help("模块列表(配调试日志)/ 文件树(配代码编辑器)")

            Picker("", selection: Binding(
                get: { workspace.rawValue },
                set: { workspace = Workspace(rawValue: $0) ?? .modules }
            )) {
                Image(systemName: "terminal").tag(0)
                Image(systemName: "doc.text").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 82)
            .help("调试日志 / 代码编辑器(与中栏自动联动)")

            // 快捷操作
            if let module = store.selectedModule {
                let running = store.isRunning(module: module)
                if running {
                    Button {
                        store.stop(module: module)
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: .jrDanger, compact: true))
                } else {
                    Button {
                        store.run(module: module)
                    } label: {
                        Label("启动服务", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                    Button {
                        store.build(module: module)
                    } label: {
                        Label("打包", systemImage: "shippingbox.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: .jrTextPrimary, compact: true))
                    .keyboardShortcut("b", modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.jrCard)
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            if store.isScanning {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }

            Text(store.statusMessage)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.jrTextSecondary)

            Spacer()

            if let project = store.selectedProject {
                HStack(spacing: 4) {
                    Image(systemName: "cube.box")
                        .font(.system(size: 9.5))
                    Text(project.tool.displayName)
                        .font(.system(size: 10.5))
                    Text("·")
                    Text(project.modules.count > 0 ? "\(project.modules.count) 模块" : "")
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(Color.jrTextTertiary)
            }

            if let project = store.selectedProject, let module = store.selectedModule,
               let task = store.task(for: project, module: module) {
                HStack(spacing: 4) {
                    StatusDot(state: task.state)
                    Text(statusText(task.state))
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(Color.jrTextTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color.jrBg)
        .overlay(alignment: .top) {
            Divider().overlay(Color.jrBorder.opacity(0.6))
        }
    }

    private func statusText(_ state: TaskState) -> String {
        switch state {
        case .idle: return "空闲"
        case .starting: return "启动中"
        case .running: return "运行中"
        case .stopping: return "停止中"
        case .success: return "已完成"
        case .failed: return "失败"
        }
    }
}
