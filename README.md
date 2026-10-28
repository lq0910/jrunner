# JRunner

> 未来轻量级 Java 服务启动器 —— 一个原生 macOS 小工具，替代笨重的 IDE 来跑 Spring Boot 老项目。

不想为了启动一个后端服务就开一个 2GB 的 IDE？JRunner 只做几件事：**一键启动、一键打包、看日志、改配置**，启动是秒级的。

![模块列表 + 调试日志](docs/modules-light.png)

## 特性

### 一键启动 / 打包

- 自动识别 Gradle / Maven 项目，列出所有子模块
- 启动走 `bootRun`，打包走 `jib`（镜像推送到仓库）
- 自动匹配项目 `gradle-wrapper.properties` 里声明的 Gradle 版本，避免版本不兼容
- 自动从 `application-*.yaml` 提取 Spring Profile，可在界面上直接切换（切数据库环境不用改文件）

### 实时日志

- 流式输出，ANSI 转义自动清理，按级别（错误 / 警告 / 信息 / 调试）过滤着色
- 启动失败时自动提取 `Caused by:` / `APPLICATION FAILED TO START` 段落置顶显示，不用在几千行里翻
- 从日志里自动识别端口，停止服务时精确回收（只杀自己启动的 java 进程）

### 文件树 + 代码编辑

- 内嵌文件树，直接改 `application-dev.yaml` 这类配置
- 带语法高亮（YAML / Properties / Java / Kotlin / XML / JSON / SQL / Markdown / Shell）和行号
- 高亮用 `NSLayoutManager` 临时属性实现，不污染文本、不影响撤销和查找

![文件树 + 代码编辑器](docs/files-light.png)

### Git 分支

- 标题栏常驻当前分支，侧边栏每个项目行尾显示各自分支
- 直接解析 `.git/HEAD`，不走 git 进程，切项目无感
- 支持游离 HEAD（显示短 SHA）、worktree、submodule；有未提交改动时显示圆点
- 切回前台自动刷新 —— 在终端 `git checkout` 完回来就是新分支

### 跟随系统的深色模式

所有配色都是动态色，系统切深浅色时界面和编辑器实时跟随，无需重启。

![深色模式](docs/modules-dark.png)

### 三栏联动

「模块列表 ↔ 调试日志」「文件树 ↔ 代码编辑器」成对切换，切换时中栏宽度自动调整到合适值。所有分栏都可以拖拽调宽。

## 快速开始

需要 macOS 13+ 和 Xcode 命令行工具。

```bash
git clone https://github.com/lq0910/jrunner.git
cd jrunner
./build.sh
open JRunner.app
```

`build.sh` 会做三件事：release 编译 → 组装 `.app` bundle（含图标）→ ad-hoc 签名。

首次打开会自动扫描 `~/Documents`、`~/Projects`、`~/IdeaProjects` 等常见目录下的项目；也可以点左下角「添加项目」指定路径。

## 环境要求

| 项目 | 说明 |
|---|---|
| macOS | 13.0+ |
| JDK | 通过 `/usr/libexec/java_home -V` 自动探测，支持多版本共存 |
| Gradle | 优先用项目自带的 wrapper，找不到时回退到 `~/.gradle/wrapper/dists` 里的版本 |
| Maven | 使用 `~/.m2` 本地仓库 |

## 目录结构

```
Sources/JRunner/
├── JRunnerApp.swift      # App 入口、菜单命令、AppDelegate
├── MainView.swift        # 三栏布局、工作区联动、标题栏
├── AppStore.swift        # 全局状态：项目、任务、配置
├── Models.swift          # Project / Module 模型与项目扫描器
├── TaskPlanner.swift     # 把模块翻译成 gradle / mvn 命令
├── ProcessTask.swift     # 子进程执行、日志流、端口探测
├── JDKResolver.swift     # JDK 探测与版本匹配
├── GitInfo.swift         # 分支读取与状态缓存
├── CodeEditor.swift      # 语法高亮 + 行号栏（NSTextView）
├── FileModels.swift      # 文件树 / 编辑器数据模型
├── FileBrowser.swift     # 文件树与编辑器视图
├── LogConsole.swift      # 日志控制台
├── ProjectSidebar.swift  # 项目侧边栏
├── ModuleDetailPanel.swift
├── SettingsSheet.swift
├── DesignSystem.swift    # 配色、按钮、徽章等基础组件
├── Shell.swift           # 登录 shell 环境变量恢复
└── AppConfig.swift       # 模块配置持久化
```

## 一些实现上的坑（给想改代码的人）

- **GUI 程序拿不到 `~/.zshrc` 的 PATH**：从 Finder 启动的 App，PATH 只有 `/usr/bin:/bin`，会找不到 gradle / mvn。所以启动子进程前会用 `zsh -lc env` 把用户环境捞回来。
- **不能对 Gradle 用 `waitUntilExit()`**：Gradle daemon 会继承 stdout 管道，进程永远不返回。改用 `terminationHandler`，并在结束时关闭读端。
- **Gradle 版本必须匹配**：用系统最新版 Gradle 跑老项目会报 `LenientConfiguration.getArtifacts` 之类的错，所以优先读 wrapper 声明的版本。
- **`NSSize(width: .greatestFiniteMagnitude)` 有歧义**：必须写 `CGFloat.greatestFiniteMagnitude`，否则编译器会在后面几百行报一堆无关的假错误。

## License

[MIT](LICENSE)
