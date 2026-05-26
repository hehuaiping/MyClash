# AGENTS.md

本文件给后续在本仓库工作的代码代理和维护者使用。请先阅读本文件，再修改代码。

## 项目定位

MyClash 是一个 SwiftPM 管理的 macOS SwiftUI 桌面端，用于管理 MetaCubeX/mihomo sidecar 进程。项目目标是稳定、低耗能、可恢复的系统代理客户端。

当前重要产品边界：

- 只支持 macOS 系统代理模式。
- 不提供 TUN 模式，不应重新加入 TUN UI、privileged helper 或路由/DNS 修改逻辑。
- mixed 代理端口为 `9809`。
- controller 地址为 `127.0.0.1:9090`。
- controller secret 必须来自 Keychain 或开发环境变量，不要硬编码到代码或文档样例中。
- Geo 资源包括 `GEOIP.dat`、`GEOSITE.dat`、`GEOIP.metadb`、`ASN.mmdb`。

## 代码结构

```text
Sources/MyClashCore/
  AppPaths.swift              # Application Support 目录和文件路径
  CoreManager.swift           # mihomo 进程、日志和运行资源管理
  ProfileManager.swift        # profile 导入、下载、生成、安装
  RuntimeConfigBuilder.swift  # 运行配置构造
  ControllerClient.swift      # mihomo REST API 数据模型和请求
  SystemProxyManager.swift    # networksetup 系统代理操作
  GeoResourceManager.swift    # Geo 资源内置复制和同步
  NodeCatalog.swift           # 节点和策略组展示模型
  EnergyPolicy.swift          # 低耗能刷新策略

Sources/MyClashApp/
  MyClashApp.swift            # App 入口、通知中心代理、LaunchServices 注册
  AppViewModel.swift          # 主要 UI 状态和应用工作流
  MainWindowView.swift        # 主窗口 UI
  MenuBarContentView.swift    # 菜单栏弹出内容
  AppServices.swift           # 登录项、通知等 App 层服务

Sources/MyClashCLI/
  MyClashCLI.swift            # 开发 CLI

Tests/MyClashCoreTests/
  核心模块 XCTest
```

## 开发原则

- 优先保持低耗能：不要引入忙轮询、短间隔 timer 或无节流刷新。
- UI 刷新要服从 `EnergyPolicy`，不可见面板不要持续高频读取数据。
- 系统代理相关改动必须保证失败回滚和可恢复。
- 不直接修改订阅原文；生成运行配置时使用 managed settings 覆盖关键字段。
- 不记录 secret、订阅 token、代理密码等敏感信息；诊断导出必须脱敏。
- 代理配置解析要兼容真实订阅中的宽松 YAML 和 provider 格式，避免只按理想格式处理。
- 不要把 `dist/`、`.build/`、用户数据目录或下载产物当成源代码依赖。
- 手动编辑文件使用 `apply_patch`；大规模格式化或构建产物生成可使用命令。

## 系统代理安全要求

开发和验证时要特别小心系统代理：

- 不要在没有用户明确要求时启动 App 并点击“开启系统代理”。
- 不要在自动化测试中真实调用 macOS `networksetup` 修改当前机器代理。
- `SystemProxyManagerTests` 应继续使用 fake runner。
- 如果用户正在运行 FlClash 或其他代理客户端，不要替用户切换系统代理。

## 日志策略

core 日志路径：

```text
~/Library/Application Support/MyClash/logs/core.log
```

当前策略：

- 只保留一个 `core.log`。
- 文件超过 `2 MB` 后，下一次写入前直接清空并从头写。
- 不生成归档日志。
- 准备日志文件时会删除旧版本遗留的 `core.log.1`、`core.log.2` 等归档。

如需调整策略，请同步更新：

- `Sources/MyClashCore/CoreManager.swift`
- `Tests/MyClashCoreTests/CoreManagerTests.swift`
- `README.md`

## 常用命令

构建：

```sh
swift build
swift build -c release
```

测试：

```sh
swift test
```

在 Codex/受限环境中推荐使用项目内缓存：

```sh
env CLANG_MODULE_CACHE_PATH=/Users/huaiping/code/MyClash/.build/module-cache \
  swift test --cache-path /Users/huaiping/code/MyClash/.build/swiftpm-cache
```

打包：

```sh
scripts/package-myclash.sh
```

开发 CLI：

```sh
swift run myclash self-test
swift run myclash paths
swift run myclash init-config
swift run myclash prepare-runtime
swift run myclash diagnostics
```

隔离用户目录：

```sh
MYCLASH_HOME=/tmp/myclash-dev swift run myclash init-config
```

## 验证要求

修改核心逻辑后至少运行：

```sh
swift test
```

修改 App 入口、打包、图标、资源或 release 行为后再运行：

```sh
swift build -c release
scripts/package-myclash.sh
```

修改以下模块时建议补充或更新测试：

- `ProfileManager`
- `RuntimeConfigBuilder`
- `ControllerClient` 解码模型
- `SystemProxyManager`
- `GeoResourceManager`
- `CoreManager`
- `ProxyBypassRules`
- `NodeCatalog`

## 打包和图标

App 图标来源：

- 源图：`MyClash_icon.png`
- 清理图：`Packaging/MyClashIconClean.png`
- iconset：`Packaging/MyClash.iconset/`
- icns：`Packaging/MyClash.icns`

`Packaging/Info.plist` 中应保留：

- `CFBundleIconFile = MyClash.icns`
- `CFBundleIconName = MyClash`

通知中心图标来自 App bundle 的 LaunchServices 注册信息，不是 `UNMutableNotificationContent` 的字段。图标相关改动后需要重新打包并启动新的 `.app` 才能验证。

## 配置和节点功能注意事项

- 下载配置时要兼容服务端根据 User-Agent 返回降级配置的情况。
- 节点展示要优先使用 mihomo runtime `/proxies`，未运行时使用 profile 预览解析。
- provider 节点和策略组节点都应进入 UI 可见模型。
- 节点延迟结果应缓存，但不能把测速做成常驻高频任务。
- 用户选择的 profile、展开策略组、选中节点应尽量持久化。

## 已知未完成项

- Sparkle App 自动更新尚未完成。
- 真实 Developer ID 签名和 notarytool 公证需要本机证书与 keychain profile。

