# MyClash macOS 代理桌面端方案

## 1. 项目目标

MyClash 是一个基于 MetaCubeX/mihomo 内核的 macOS 代理桌面端程序。应用目标是提供稳定、清晰、易维护的原生代理客户端体验，让用户可以完成订阅管理、节点切换、系统代理开关、流量观察、连接管理和日志查看等常见代理工作流。

首版重点不是堆叠功能，而是建立可靠的内核管理、配置生成和 macOS 网络接入基础。后续功能都应围绕这三件事演进。

## 2. 设计原则

1. 使用 mihomo 作为独立 sidecar 进程，不直接嵌入主程序。
2. App 通过 mihomo External Controller 的 REST 和 WebSocket API 管理内核。
3. 用户订阅配置和 App 生成配置分离，避免直接修改订阅原文。
4. 默认只监听本机地址，敏感凭据存入 Keychain。
5. 系统代理必须支持异常恢复。
6. UI 优先覆盖高频操作，复杂能力放入高级设置。
7. 产品名不直接使用 mihomo，避免与上游项目名称混淆。

## 3. 上游能力边界

mihomo 提供代理内核能力，包括但不限于：

- HTTP、SOCKS、mixed-port 等本地入站代理。
- rule、global、direct 等运行模式。
- proxy group 节点选择和延迟测试。
- rule provider、proxy provider、profile 持久化。
- External Controller REST API。
- traffic、logs、connections 等 WebSocket 实时数据。
- TUN 模式、DNS 劫持、自动路由等高级网络能力由 mihomo 支持，但 MyClash 当前版本不暴露这些能力。

MyClash 不重新实现代理协议，只负责：

- 下载、安装、启动、停止、升级 mihomo core。
- 管理配置、订阅和运行时参数。
- 调用 controller API 完成状态展示与操作。
- 管理 macOS 系统代理和网络恢复。
- 提供原生桌面交互体验。

## 4. 技术选型

### 4.1 客户端

- 语言：Swift
- UI：SwiftUI 为主，必要时使用 AppKit
- 菜单栏：MenuBarExtra 或 NSStatusItem
- 网络请求：URLSession
- WebSocket：URLSessionWebSocketTask
- YAML 解析：Yams
- 登录启动：ServiceManagement
- 自动更新：Sparkle

### 4.2 内核

- MetaCubeX/mihomo darwin arm64 和 amd64 二进制。
- App 按当前架构选择 core。
- core 作为子进程启动，stdout/stderr 写入 App 日志目录。
- core 配置文件由 App 生成，不直接使用用户订阅原文件作为运行文件。

## 5. 总体架构

```text
MyClash.app
├── UI Layer
│   ├── Menu Bar
│   ├── Main Window
│   ├── Notifications
│   └── Settings
├── Application Services
│   ├── CoreManager
│   ├── ProfileManager
│   ├── ProxyControllerClient
│   ├── SystemProxyManager
│   ├── UpdateManager
│   └── DiagnosticsService
├── Persistence
│   ├── AppSettings
│   ├── ProfileStore
│   ├── RuntimeStore
│   └── KeychainStore
└── mihomo sidecar process
    ├── REST Controller
    ├── WebSocket Streams
    └── Proxy Runtime
```

## 6. 模块设计

### 6.1 CoreManager

职责：

- 检测本机架构并选择 mihomo 二进制。
- 初始化 core 文件和运行目录。
- 生成运行配置文件。
- 启动、停止、重启 mihomo。
- 执行健康检查。
- 监听进程退出并记录崩溃原因。
- 支持 core 版本查询和升级。

关键状态：

- stopped
- starting
- running
- stopping
- failed

启动流程：

1. ProfileManager 生成最终配置。
2. CoreManager 写入 runtime/config.yaml。
3. CoreManager 启动 mihomo，传入工作目录和配置路径。
4. 等待 controller `/version` 或等价健康检查成功。
5. 启动 traffic、logs、connections WebSocket 订阅。
6. UI 进入 running 状态。

### 6.2 ProfileManager

职责：

- 添加订阅 URL。
- 导入本地 YAML 配置。
- 刷新订阅。
- 保存原始配置 raw.yaml。
- 应用用户覆盖配置 override.yaml。
- 生成最终运行配置 generated.yaml。
- 校验 YAML 格式和关键端口冲突。

配置分层：

```text
raw.yaml
  + app-defaults.yaml
  + user-override.yaml
  = generated.yaml
```

其中 raw.yaml 是订阅源，不直接修改；override.yaml 只保存用户在 App 内修改的部分，例如 mixed-port、mode、log-level、dns 和 external-controller。

### 6.3 ProxyControllerClient

职责：

- 封装 mihomo controller REST API。
- 统一添加 Authorization header。
- 获取运行配置、代理组、节点、连接、日志和版本。
- 切换策略组节点。
- 发起节点延迟测试。
- 关闭单个连接或全部连接。
- 订阅 WebSocket 实时数据。

主要能力：

- GET `/version`
- GET/PATCH `/configs`
- GET `/proxies`
- PUT `/proxies/{name}`
- GET `/group/{name}/delay`
- GET `/connections`
- DELETE `/connections/{id}`
- DELETE `/connections`
- WebSocket `/traffic`
- WebSocket `/logs`
- WebSocket `/connections`

### 6.4 SystemProxyManager

职责：

- 读取当前 macOS 网络服务列表。
- 记录开启代理前的系统代理状态。
- 开启 HTTP、HTTPS、SOCKS 或 mixed 代理。
- 关闭代理并恢复旧状态。
- 在 App 崩溃或 core 停止后尽量恢复系统代理。

默认代理端口：

- mixed-port: 7890
- controller: 127.0.0.1:9090

系统代理开关只处理 macOS 系统代理。MyClash 当前版本不提供 TUN 模式，运行配置生成时会剥离订阅中可能携带的 `tun` 顶层配置，避免绕过 UI 意外改变系统路由或 DNS。

### 6.5 UpdateManager

职责：

- App 更新。
- mihomo core 更新。
- Geo 数据和 provider 数据更新。
- 下载文件校验。
- 失败回滚。

更新策略：

- App 使用 Sparkle。
- core 更新独立于 App 更新。
- core 下载后先放入 staging 目录，校验通过后原子替换。

### 6.7 DiagnosticsService

职责：

- 收集 App 日志、core 日志、当前配置摘要和版本信息。
- 提供一键导出诊断包。
- 对敏感字段脱敏，例如 secret、订阅 URL token、代理密码。

## 7. 本地目录结构

```text
~/Library/Application Support/MyClash/
├── core/
│   ├── mihomo-darwin-arm64
│   └── mihomo-darwin-amd64
├── profiles/
│   └── <profile-id>/
│       ├── raw.yaml
│       ├── override.yaml
│       └── generated.yaml
├── runtime/
│   ├── config.yaml
│   ├── cache.db
│   └── mihomo.pid
├── geo/
├── logs/
│   ├── app.log
│   └── core.log
└── downloads/
```

## 8. 默认运行配置

基础配置：

```yaml
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090
secret: "<generated-secret>"
profile:
  store-selected: true
  store-fake-ip: true
```

安全要求：

- secret 由 App 首次启动时随机生成。
- secret 存储在 Keychain。
- runtime/config.yaml 文件权限设为 0600。
- external-controller 默认只绑定 127.0.0.1。
- allow-lan 默认关闭。

## 9. UI 信息架构

### 9.1 菜单栏

菜单栏是高频入口，应包含：

- 当前运行状态。
- 上传和下载实时速率。
- 一键开启或关闭代理。
- 当前模式切换：Rule、Global、Direct。
- 当前配置切换。
- 常用策略组快捷切换。
- 打开主窗口。
- 打开日志。
- 退出。

### 9.2 主窗口

主窗口建议分为以下页面：

1. 概览
   - 运行状态
   - 当前配置
   - 当前模式
   - 实时上传和下载
   - 活跃连接数
   - core 版本

2. 节点
   - 策略组列表
   - 节点列表
   - 当前选择
   - 延迟测试
   - 批量测速

3. 配置
   - 订阅列表
   - 本地导入
   - 刷新订阅
   - 切换配置
   - 配置校验结果

4. 连接
   - 活跃连接列表
   - 目标地址
   - 规则命中
   - 使用节点
   - 上传下载
   - 关闭连接

5. 日志
   - 实时日志流
   - 日志级别过滤
   - 搜索
   - 导出

6. 设置
   - 开机启动
   - 系统代理
   - 端口配置
   - 外部控制器
   - core 更新
   - 诊断导出

## 10. 关键用户流程

### 10.1 首次启动

1. App 检查 Application Support 目录。
2. App 初始化 core、runtime、profiles、logs。
3. App 生成 controller secret 并写入 Keychain。
4. App 引导用户添加订阅或导入配置。
5. App 校验配置。
6. App 启动 mihomo。
7. App 提示用户开启系统代理。

### 10.2 添加订阅

1. 用户输入订阅 URL。
2. App 下载配置。
3. App 校验 YAML。
4. App 保存 raw.yaml。
5. App 合并默认配置和覆盖配置。
6. App 生成 generated.yaml。
7. App 重启或热更新 mihomo。

### 10.3 切换节点

1. UI 获取 `/proxies`。
2. 用户选择策略组中的节点。
3. App 调用 PUT `/proxies/{name}`。
4. UI 刷新策略组状态。
5. App 可选展示延迟和连接变化。

### 10.4 开启系统代理

1. App 读取当前系统代理状态并保存快照。
2. App 将 HTTP、HTTPS、SOCKS 指向 127.0.0.1 和 mixed-port。
3. UI 展示系统代理已开启。
4. 关闭代理时恢复快照。

## 11. 异常处理

需要覆盖的异常场景：

- mihomo 启动失败。
- controller 端口被占用。
- mixed-port 被占用。
- 配置文件 YAML 解析失败。
- 订阅下载失败。
- 策略组切换失败。
- WebSocket 断开。
- 系统代理设置失败。
- App 崩溃后系统代理未恢复。

处理原则：

- 所有失败都应有用户可理解的错误信息。
- core 启动失败时展示 core stderr 摘要。
- 端口冲突时提示具体端口和建议动作。
- 系统代理变更失败必须尝试恢复旧快照。
- 诊断导出必须脱敏。

## 12. 安全与隐私

1. controller secret 存入 Keychain。
2. 不在日志中输出完整订阅 URL。
3. 不在日志中输出代理密码、token 和 secret。
4. external-controller 默认绑定 127.0.0.1。
5. allow-lan 默认关闭。
6. 诊断包导出前进行脱敏。
7. core 下载需要校验来源和文件完整性。

## 13. 开发里程碑

### 阶段一：工程基础

目标：

- 创建 macOS SwiftUI 工程。
- 实现菜单栏入口。
- 实现基础设置存储。
- 初始化 Application Support 目录。

验收：

- App 可启动。
- 菜单栏可显示。
- 主窗口可打开。
- 本地目录可自动创建。

### 阶段二：内核管理

目标：

- 集成 mihomo core。
- 实现 CoreManager。
- 生成基础 config.yaml。
- 启动、停止、重启 core。
- 调用 `/version` 完成健康检查。

验收：

- App 可启动 mihomo。
- core 停止后 UI 状态正确。
- 启动失败有明确错误。

### 阶段三：配置和订阅

目标：

- 实现订阅添加。
- 实现本地 YAML 导入。
- 实现配置合并。
- 实现配置切换。

验收：

- 用户可添加订阅并启动代理。
- 配置错误时不覆盖当前可用配置。
- raw.yaml 和 generated.yaml 分离保存。

### 阶段四：系统代理

目标：

- 实现 SystemProxyManager。
- 开启和关闭 macOS 系统代理。
- 保存和恢复原代理设置。

验收：

- 开启代理后系统流量可走 mixed-port。
- 关闭代理后恢复原系统设置。
- core 异常退出时有恢复机制。

### 阶段五：节点和运行状态

目标：

- 实现 `/proxies` 获取。
- 实现策略组切换。
- 实现节点延迟测试。
- 接入 `/traffic`、`/logs`、`/connections`。

验收：

- 用户可切换节点。
- 用户可看到实时速率。
- 用户可查看日志和连接列表。

### 阶段六：更新和发布

目标：

- 实现 App 更新。
- 实现 core 更新。
- 实现签名、公证和分发流程。
- 实现诊断导出。

验收：

- App 可被正常安装和启动。
- core 可独立升级。
- 诊断包不包含敏感明文。

## 14. 推荐首版范围

首个可用版本建议只包含：

- 菜单栏。
- 主窗口基础页面。
- mihomo core 启停。
- 订阅添加和刷新。
- 系统代理开关。
- 策略组切换。
- 节点测速。
- 实时流量。
- 日志查看。

暂缓内容：

- 局域网共享。
- Dashboard 内嵌。
- 复杂规则编辑器。
- 多用户配置同步。

MyClash 当前版本明确剔除 TUN 模式，只提供系统代理接入；订阅中的 `tun` 顶层配置会在生成运行配置时被移除。

## 15. 后续任务拆分建议

建议从以下任务开始落地：

1. 初始化 macOS SwiftUI 工程。
2. 建立 CoreManager 和 ProfileManager 的接口定义。
3. 添加 mihomo 二进制管理目录。
4. 实现最小 config.yaml 生成。
5. 启动 mihomo 并调用 `/version`。
6. 实现菜单栏开启和关闭。
7. 实现系统代理开关。
8. 实现订阅导入。
9. 实现节点页面。
10. 实现实时流量和日志。

## 16. 风险清单

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 配置合并错误 | core 无法启动 | raw 和 generated 分离，失败不覆盖 |
| controller secret 泄露 | 本机控制接口被滥用 | Keychain 存储，日志脱敏 |
| 端口冲突 | 代理无法启动 | 启动前检测端口，提供替代端口 |
| core 升级失败 | 应用不可用 | staging 下载，校验后替换 |
| 系统代理未恢复 | 用户网络异常 | 保存快照，退出和崩溃恢复 |

## 17. 文档与参考

- MetaCubeX/mihomo GitHub: https://github.com/MetaCubeX/mihomo
- mihomo API 文档: https://wiki.metacubex.one/api/
- mihomo 通用配置文档: https://wiki.metacubex.one/config/general/
