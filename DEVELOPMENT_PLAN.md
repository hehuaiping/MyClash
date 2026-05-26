# MyClash 开发计划

## 目标

实现一个基于 MetaCubeX/mihomo 的 macOS 代理桌面端。开发顺序以核心功能优先：先保证 mihomo 能被稳定启动、配置可控、系统代理可恢复，再进入 SwiftUI 菜单栏和主窗口，最后补更新和发布。

低耗能是硬性要求。运行时不得使用忙轮询；实时数据使用 WebSocket 或低频采样；健康检查、测速、日志刷新都必须有节流和退避策略。

## 阶段 0：当前已落地

- [x] 建立 Swift Package 工程。
- [x] 建立 `MyClashCore` 核心模块。
- [x] 建立 `myclash` CLI 验证入口。
- [x] 建立开发计划文档。
- [x] 建立低耗能策略模型。
- [x] 使用 Xcode 26.5 验证 Swift Package schemes、Debug/Release 构建和 XCTest。

## 阶段 1：核心运行层

- [x] 应用目录管理：`Application Support/MyClash`、profiles、runtime、logs、core。
- [x] Keychain secret 读写封装。
- [x] profile 原始配置保存。
- [x] generated config 生成。
- [x] mihomo 进程启动、停止、重启。
- [x] controller 健康检查。

验收标准：

- CLI 可以生成运行配置。
- CoreManager 可以按指定路径启动 mihomo。
- core 停止后不会留下忙等任务。

## 阶段 2：Controller 与系统代理

- [x] 封装 controller REST API。
- [x] 封装 traffic、logs、connections WebSocket URL。
- [x] 封装 macOS `networksetup` 系统代理操作。
- [x] 保存和恢复系统代理快照。

验收标准：

- 可以获取 `/version`、`/configs`、`/proxies`、`/connections`。
- 可以切换策略组节点。
- 可以开启和关闭系统 HTTP、HTTPS、SOCKS 代理。
- 系统代理恢复逻辑独立于 UI。

## 阶段 3：低耗能运行策略

- [x] 定义统一 EnergyPolicy。
- [x] 空闲状态降低采样频率。
- [x] 健康检查采用最低间隔限制。
- [x] 批量测速设置并发上限。
- [x] 在 SwiftUI/AppKit 层接入低频可见性刷新策略。
- [x] 增加运行时 CPU 占用观测和诊断导出。
- [x] 添加 XCTest 覆盖低耗能策略和资源监视基础行为。

验收标准：

- 无 while/sleep 式忙轮询。
- 流量采样空闲时自动降频。
- 节点测速不会一次性打满所有节点。

## 阶段 4：macOS App 壳

- [x] 创建 SwiftUI macOS App target。
- [x] 菜单栏状态和开关。
- [x] 主窗口：概览、节点、配置、连接、日志、设置。
- [x] 节点页接入 `/proxies` 和策略组切换。
- [x] 连接页接入 `/connections` 和关闭连接。
- [x] 日志页只在可见时读取 core 日志尾部。
- [x] 登录启动。
- [x] 通知和错误提示。

验收标准：

- App 可从菜单栏完成启动和停止代理。
- 主窗口可查看实时流量、日志和连接。
- UI 刷新频率受 EnergyPolicy 控制。

## 阶段 5：TUN 模式剔除

- [x] 移除 App 内 TUN 设置入口。
- [x] 移除 CLI TUN/helper 命令。
- [x] 移除 privileged helper target 和协议脚手架。
- [x] 移除 TUN 配置模型、运行时验证和相关测试。
- [x] 生成运行配置时剥离订阅自带的 `tun` 顶层配置。

验收标准：

- App 只提供 macOS 系统代理接入。
- 运行配置不会因为订阅自带 `tun` 块而启用 TUN。

## 阶段 6：更新、签名和发布

- [ ] Sparkle App 更新。
- [x] mihomo core 下载 URL 生成。
- [x] mihomo core 本地安装。
- [x] mihomo core gzip 解压安装。
- [x] mihomo core sha256 校验和 staging 替换。
- [x] mihomo core 版本探测。
- [x] mihomo core 独立更新 UI 流程完善。
- [x] App bundle 打包和 ad-hoc 签名验证。
- [x] Developer ID 签名和 notarytool 公证脚本入口。
- [ ] 使用真实 Developer ID 证书完成公证验证。
- [x] 诊断包导出并脱敏。

验收标准：

- App 可打包分发。
- core 升级失败可回滚。
- 诊断包不包含 secret、订阅 token 或代理密码。

## 能耗约束

1. 不做 100ms 级别常驻刷新。
2. 实时流量优先使用 WebSocket；WebSocket 断开后才低频重连。
3. 空闲状态 UI 刷新不高于 0.2Hz。
4. 活跃状态 UI 刷新不高于 1Hz。
5. 健康检查最小间隔 10 秒，失败时指数退避，最大 60 秒。
6. 节点批量测速并发不超过 4。
7. 日志视图不可见时不解析和渲染日志流。
8. 连接列表视图不可见时暂停高频连接刷新。
9. 子进程输出写文件，不在主线程持续解析。
10. App 进入后台后降低非必要任务频率。
