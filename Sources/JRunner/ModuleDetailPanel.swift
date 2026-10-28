import SwiftUI

// MARK: - 模块详情面板

struct ModuleDetailPanel: View {
    @ObservedObject var store: AppStore
    @State private var showConfig = false

    private var project: Project? { store.selectedProject }
    private var module: Module? { store.selectedModule }

    var body: some View {
        VStack(spacing: 0) {
            if let project, let module {
                header(project: project, module: module)
                Divider().overlay(Color.jrBorder.opacity(0.6))
                moduleList(project: project)
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up.slash",
                    title: "未选择项目",
                    subtitle: "从左侧选择一个项目开始\n支持 Gradle / Maven 的 Java、Kotlin 项目"
                )
            }
        }
        .background(Color.jrBg)
    }

    // MARK: Header

    private func header(project: Project, module: Module) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.jrTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(project.path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.jrTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer()

                // 项目级操作
                Button {
                    store.scanProjects()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .help("重新扫描项目")

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .help("在 Finder 中打开")
            }

            // 当前模块操作条
            HStack(spacing: 8) {
                modulePicker(project: project, module: module)

                if module.isSpringBoot {
                    profilePicker(project: project, module: module)
                }

                Spacer(minLength: 8)

                actionButtons(module: module)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.jrCard)
    }

    private func modulePicker(project: Project, module: Module) -> some View {
        Menu {
            ForEach(project.modules) { m in
                Button {
                    store.selectedModule = m
                } label: {
                    HStack {
                        Text(m.displayPath)
                        if store.isRunning(module: m) {
                            Image(systemName: "play.circle.fill")
                        }
                    }
                }
            }
        } label: {
            Text(module.displayPath)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.jrPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.jrPrimary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.jrPrimary.opacity(0.22), lineWidth: 0.6)
        )
        .help(module.displayPath)
    }

    private func profilePicker(project: Project, module: Module) -> some View {
        let current = store.effectiveProfile(project: project, module: module)
        let isOverridden = store.config.config(for: project.path, module: module.path).profile != nil

        return Menu {
            Button {
                store.setProfile(nil, project: project, module: module)
            } label: {
                Text("跟随项目配置" + (module.defaultProfile.map { "(\($0))" } ?? ""))
            }

            if !module.availableProfiles.isEmpty {
                Divider()
                ForEach(module.availableProfiles, id: \.self) { p in
                    Button {
                        store.setProfile(p, project: project, module: module)
                    } label: {
                        Text(p)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "leaf")
                    .font(.system(size: 9))
                Text(current ?? "profile")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isOverridden ? Color.jrSuccess : Color.jrTextSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOverridden ? Color.jrSuccess.opacity(0.12) : Color.jrBorder.opacity(0.35))
        )
        .help("Spring Profile(影响数据库等环境配置)")
    }

    private func actionButtons(module: Module) -> some View {
        HStack(spacing: 6) {
            let running = store.isRunning(module: module)

            if running {
                Button {
                    store.stop(module: module)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(PrimaryButtonStyle(tint: .jrDanger, compact: true))
                .help("停止服务")
            } else {
                Button {
                    store.run(module: module)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .help("启动服务 (⇧⌘R)")

                Button {
                    store.build(module: module)
                } label: {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(SecondaryButtonStyle(tint: .jrTextPrimary, compact: true))
                .help("打包推送镜像 (⌘B)")
            }

            Button {
                showConfig = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
            .help("模块配置")
        }
        .fixedSize()
    }

    // MARK: Module list

    private func moduleList(project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("模块 (\(project.modules.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.jrTextSecondary)
                    .padding(.top, 4)

                LazyVStack(spacing: 6) {
                    ForEach(project.modules) { m in
                        ModuleRow(
                            module: m,
                            isSelected: store.selectedModule?.id == m.id,
                            task: store.task(for: project, module: m),
                            onSelect: { store.selectedModule = m },
                            onRun: { store.run(module: m) },
                            onBuild: { store.build(module: m) },
                            onStop: { store.stop(module: m) }
                        )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showConfig) {
            if let module {
                ModuleConfigSheet(store: store, project: project, module: module)
            }
        }
    }
}

// MARK: - 模块行

private struct ModuleRow: View {
    let module: Module
    let isSelected: Bool
    let task: ProcessTask?
    let onSelect: () -> Void
    let onRun: () -> Void
    let onBuild: () -> Void
    let onStop: () -> Void

    var body: some View {
        if let task {
            // 有任务时订阅其状态变化
            ModuleRowLive(module: module, isSelected: isSelected, task: task,
                          onSelect: onSelect, onRun: onRun, onBuild: onBuild, onStop: onStop)
        } else {
            ModuleRowContent(module: module, isSelected: isSelected, state: .idle, port: nil,
                             onSelect: onSelect, onRun: onRun, onBuild: onBuild, onStop: onStop)
        }
    }
}

private struct ModuleRowLive: View {
    let module: Module
    let isSelected: Bool
    @ObservedObject var task: ProcessTask
    let onSelect: () -> Void
    let onRun: () -> Void
    let onBuild: () -> Void
    let onStop: () -> Void

    var body: some View {
        ModuleRowContent(module: module, isSelected: isSelected, state: task.state, port: task.detectedPort,
                         onSelect: onSelect, onRun: onRun, onBuild: onBuild, onStop: onStop)
    }
}

private struct ModuleRowContent: View {
    let module: Module
    let isSelected: Bool
    let state: TaskState
    let port: Int?
    let onSelect: () -> Void
    let onRun: () -> Void
    let onBuild: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(state: state)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color.jrTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    Text(module.language)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.jrTextTertiary)
                        .fixedSize()
                    if module.isSpringBoot {
                        Badge(text: "SpringBoot", color: .jrSuccess)
                    }
                    if module.hasJib {
                        Badge(text: "jib", color: .jrPurple)
                    }
                    if let port, state.isActive {
                        Badge(text: ":\(port)", color: .jrPrimary, filled: true)
                    }
                    if let jv = module.javaVersion {
                        Text("JDK \(jv)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.jrTextTertiary)
                            .fixedSize()
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.isActive {
                Button(action: onStop) {
                    Image(systemName: "stop.fill").font(.system(size: 10))
                }
                .buttonStyle(SecondaryButtonStyle(tint: .jrDanger, compact: true))
                .help("停止")
            } else {
                Button(action: onRun) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                }
                .buttonStyle(SecondaryButtonStyle(tint: .jrSuccess, compact: true))
                .help("启动")

                Button(action: onBuild) {
                    Image(systemName: "shippingbox.fill").font(.system(size: 10))
                }
                .buttonStyle(SecondaryButtonStyle(tint: .jrTextSecondary, compact: true))
                .help("打包")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.jrPrimaryLight : Color.jrCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.jrPrimary.opacity(0.45) : Color.jrBorder.opacity(0.6),
                        lineWidth: isSelected ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
