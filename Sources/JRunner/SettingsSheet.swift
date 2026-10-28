import SwiftUI

// MARK: - 设置

struct SettingsSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var rootsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.jrTextPrimary)

            // 外观
            VStack(alignment: .leading, spacing: 7) {
                Text("外观")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.jrTextSecondary)

                Picker("", selection: $store.appearance) {
                    ForEach(AppearanceMode.allCases) { m in
                        Label(m.label, systemImage: m.icon).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)

                Text("选「跟随系统」时,外观随 macOS 的浅色 / 深色自动切换")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.jrTextTertiary)
            }

            // 扫描目录
            VStack(alignment: .leading, spacing: 7) {
                Text("扫描目录")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.jrTextSecondary)
                Text("每行一个目录,JRunner 会在其中递归查找 Gradle / Maven 项目(深度 3 层)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.jrTextTertiary)

                TextEditor(text: $rootsText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.jrTextPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(height: 110)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.jrCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7).stroke(Color.jrBorder, lineWidth: 0.5)
                    )
            }

            // JDK
            VStack(alignment: .leading, spacing: 7) {
                Text("已安装的 JDK (\(store.jdks.count))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.jrTextSecondary)

                VStack(spacing: 3) {
                    ForEach(store.jdks) { jdk in
                        HStack(spacing: 8) {
                            Image(systemName: jdk.isCurrent ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(jdk.isCurrent ? Color.jrSuccess : Color.jrTextTertiary)
                            Text("JDK \(jdk.fullVersion)")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color.jrTextPrimary)
                            Text(jdk.vendor)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.jrTextTertiary)
                            Spacer()
                            if jdk.isCurrent {
                                Badge(text: "默认", color: .jrSuccess, filled: true)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5).fill(Color.jrBg)
                        )
                    }
                }
            }

            Spacer()

            HStack {
                Button("重置 JDK 列表") {
                    store.refreshJDKs()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())

                Button("保存并重新扫描") {
                    let roots = rootsText.split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    store.scanRoots = roots
                    store.saveScanRoots()
                    store.scanProjects()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 560, height: 620)
        .background(Color.jrBg)
        .onAppear {
            rootsText = store.scanRoots.joined(separator: "\n")
        }
    }
}

// MARK: - 模块配置

struct ModuleConfigSheet: View {
    @ObservedObject var store: AppStore
    let project: Project
    let module: Module
    @Environment(\.dismiss) private var dismiss

    @State private var profile: String = ""
    @State private var javaVersion: Int = 0        // 0 = 跟随默认
    @State private var envText: String = ""
    @State private var extraArgs: String = ""

    /// 按主版本号去重(同一主版本可能装了多个小版本)
    private var uniqueJavaVersions: [Int] {
        Array(Set(store.jdks.map { $0.version })).sorted(by: >)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("模块配置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.jrTextPrimary)
                Text("\(project.name) · \(module.path)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.jrTextTertiary)
            }

            Form {
                // Profile
                VStack(alignment: .leading, spacing: 5) {
                    Text("Spring Profile").font(.system(size: 12, weight: .medium))
                    TextField("留空表示使用项目默认配置", text: $profile)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Text("启动时附加 --spring.profiles.active=<profile>")
                        .font(.system(size: 10.5)).foregroundStyle(Color.jrTextTertiary)
                }

                // JDK
                VStack(alignment: .leading, spacing: 5) {
                    Text("JDK 版本").font(.system(size: 12, weight: .medium))
                    Picker("JDK 版本", selection: $javaVersion) {
                        Text("跟随项目配置").tag(0)
                        ForEach(uniqueJavaVersions, id: \.self) { v in
                            Text("JDK \(v)").tag(v)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 环境变量
                VStack(alignment: .leading, spacing: 5) {
                    Text("环境变量").font(.system(size: 12, weight: .medium))
                    TextField("每行一个 KEY=VALUE", text: $envText, axis: .vertical)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                // 额外参数
                VStack(alignment: .leading, spacing: 5) {
                    Text("额外 Gradle 参数").font(.system(size: 12, weight: .medium))
                    TextField("--info --stacktrace", text: $extraArgs)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)

            Spacer()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("保存") {
                    var cfg = store.config.config(for: project.path, module: module.path)
                    cfg.profile = profile.isEmpty ? nil : profile
                    cfg.javaVersion = javaVersion == 0 ? nil : javaVersion
                    cfg.envVars = [:]
                    for line in envText.split(separator: "\n") {
                        let s = line.trimmingCharacters(in: .whitespaces)
                        guard !s.isEmpty, let idx = s.firstIndex(of: "=") else { continue }
                        let k = String(s[s.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
                        let v = String(s[s.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                        if !k.isEmpty { cfg.envVars[k] = v }
                    }
                    cfg.extraArgs = extraArgs.split(separator: " ")
                        .map { String($0) }
                        .filter { !$0.isEmpty }
                    store.updateConfig(project: project.path, module: module.path, config: cfg)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 520, height: 560)
        .background(Color.jrBg)
        .onAppear {
            let cfg = store.config.config(for: project.path, module: module.path)
            profile = cfg.profile ?? ""
            javaVersion = cfg.javaVersion ?? 0
            envText = cfg.envVars.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
            extraArgs = cfg.extraArgs.joined(separator: " ")
        }
    }
}
