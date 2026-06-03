# MyClash

MyClash 是一个基于 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) 的 macOS 原生代理桌面端。它使用 SwiftUI 构建桌面界面，通过 mihomo External Controller 管理代理内核，提供配置导入、订阅下载、节点展示、策略组切换、系统代理开关、连接查看、日志查看和基础诊断能力。

当前版本聚焦系统代理模式，不提供 TUN 模式。运行配置会剥离订阅中可能携带的 `tun` 顶层配置，避免应用在用户没有明确授权的情况下修改路由或 DNS。

## 核心能力

- 启动、停止和健康检查 mihomo sidecar 进程。
- mixed 代理端口固定为 `9809`。
- External Controller 固定监听 `127.0.0.1:9090`，controller secret 存入 Keychain。
- 支持从网络 URL 下载配置，也支持导入本地 YAML 配置文件。
- 配置会保存到 `~/Library/Application Support/MyClash/profiles/`，重启后默认恢复上次加载的配置。
- 节点页支持策略组、节点列表、节点类型、延迟缓存、手动测速和运行态刷新。
- 系统代理通过 macOS `networksetup` 控制，开启前会记录原始状态，关闭时尽量恢复。
- Geo 资源支持内置初始资源和后续同步，包括 `GEOIP.dat`、`GEOSITE.dat`、`GEOIP.metadb`、`ASN.mmdb`。
- core 日志只保留 `core.log` 单文件，超过 `2 MB` 后下一次写入会清空并从头写入，不保留归档日志。

## 项目结构

```text
.
├── Package.swift
├── Sources/
│   ├── MyClashApp/        # SwiftUI macOS App
│   ├── MyClashCLI/        # 开发和诊断 CLI
│   └── MyClashCore/       # core 管理、配置、系统代理、资源和诊断模块
├── Tests/
│   └── MyClashCoreTests/  # 核心模块 XCTest
├── Packaging/             # Info.plist、图标、签名权限和打包说明
├── scripts/
│   └── package-myclash.sh # App bundle 打包脚本
├── DEVELOPMENT_PLAN.md
└── MyClash-macOS-方案.md
```

## 本地数据目录

默认数据目录：

```text
~/Library/Application Support/MyClash/
├── core/       # mihomo core 二进制
├── profiles/   # 用户导入或下载的配置
├── runtime/    # 运行时 config.yaml、pid 和 Geo 资源
├── logs/       # core.log 和诊断输出
└── downloads/  # 下载暂存文件
```

常用路径：

- core 日志：`~/Library/Application Support/MyClash/logs/core.log`
- 运行配置：`~/Library/Application Support/MyClash/runtime/config.yaml`
- mihomo core：`~/Library/Application Support/MyClash/core/mihomo-darwin-arm64` 或 `mihomo-darwin-amd64`

开发时可通过 `MYCLASH_HOME` 指向临时目录，避免污染真实用户数据：

```sh
MYCLASH_HOME=/tmp/myclash-dev swift run myclash paths
```

## 构建和测试

要求：

- macOS 13 或更高版本
- Xcode / Swift 6 工具链

获取依赖并构建：

```sh
swift build
```

运行测试：

```sh
swift test
```

构建 release：

```sh
swift build -c release
```

打包 macOS `.app`：

```sh
scripts/package-myclash.sh
```

默认会生成：

- `dist/MyClash.app`
- `dist/MyClash-<version>-<build>.zip`

打包带拖拽安装界面的 `.dmg`：

```sh
scripts/package-dmg.sh
```

如果已经有 `dist/MyClash.app`，可以跳过重新构建 App：

```sh
MYCLASH_SKIP_APP_BUILD=1 scripts/package-dmg.sh
```

打包脚本默认使用 ad-hoc 签名。Developer ID 签名和公证参数见 [Packaging/README.md](Packaging/README.md)。

## GitHub Actions

仓库包含自动构建流水线：[.github/workflows/build.yml](.github/workflows/build.yml)。

- push 到 `release/*` 分支时会运行测试和打包。
- 构建成功后会自动创建 tag，例如 `v0.2.0-build.3`。
- `.zip` 和 `.dmg` 产物会上传到对应的 GitHub Release。
- Release note 会包含发布分支、版本号、构建号、提交和安装说明。
- CI 环境会跳过 Finder 窗口美化步骤，本地运行 `scripts/package-dmg.sh` 时仍会生成带拖拽引导的 DMG 安装界面。

## 开发 CLI

`myclash` 是开发辅助入口：

```sh
swift run myclash self-test
swift run myclash paths
swift run myclash init-config
swift run myclash core-info
swift run myclash prepare-runtime
swift run myclash diagnostics
```

常用环境变量：

- `MYCLASH_HOME`：覆盖 Application Support 目录。
- `MYCLASH_DEV_SECRET`：开发时覆盖 controller secret，避免写 Keychain。

## 配置处理模型

MyClash 不直接修改订阅原文。配置分层如下：

```text
raw.yaml
  + MyClash managed settings
  + user override
  = generated.yaml
```

运行时实际交给 mihomo 的文件是 `runtime/config.yaml`。MyClash 会管理以下关键项：

- `mixed-port: 9809`
- `external-controller: 127.0.0.1:9090`
- `secret`
- `allow-lan: false`
- `mode`
- Geo 资源路径和资源同步 URL
- 系统代理绕过规则对应的 DIRECT 规则
- 移除 `tun` 顶层配置

## 低耗能策略

MyClash 避免高频忙轮询：

- 概览流量由 mihomo `/connections` 的累计上下行字节差值计算。
- 托盘菜单不展示实时流量。
- UI 根据当前可见面板低频刷新。
- 日志页只读取 `core.log` 末尾内容。
- 节点测速按批次执行，避免一次性打满所有节点。
- core 输出由后台 utility task 写入日志文件。

## 注意事项

- 启用系统代理会修改 macOS 网络服务的 HTTP、HTTPS、SOCKS 代理配置。开发调试时如果同时运行 FlClash 或其他代理客户端，不要同时开启多个客户端的系统代理。
- 当前项目不是完整商业发行包，真实分发前仍需要 Developer ID 签名、公证和更完整的自动更新流程。
- Sparkle App 更新尚未完成；mihomo core 独立下载、校验和安装能力已落地。
