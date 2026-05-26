import Foundation
import MyClashCore
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var statusText = "未启动"
    @Published private(set) var statusDetail = "等待初始化"
    @Published private(set) var isCoreRunning = false
    @Published private(set) var isSystemProxyEnabled = false
    @Published private(set) var uploadBytesPerSecond: UInt64 = 0
    @Published private(set) var downloadBytesPerSecond: UInt64 = 0
    @Published private(set) var activeConnections = 0
    @Published private(set) var coreVersion = "-"
    @Published private(set) var lastError: String?
    @Published private(set) var applicationSupportPath = "-"
    @Published private(set) var runtimeConfigPath = "-"
    @Published private(set) var proxyGroups: [ProxyGroupSnapshot] = []
    @Published private(set) var proxyProviderRows: [ProxyProviderSnapshot] = []
    @Published private(set) var proxyProviderStatus = "未刷新"
    @Published private(set) var nodeCatalogSourceText = "预览"
    @Published private(set) var preferredExpandedProxyGroupIDs: Set<String> = []
    @Published private(set) var connectionRows: [ConnectionSnapshot] = []
    @Published private(set) var profileRows: [ProfileSnapshot] = []
    @Published private(set) var recentLogs = ""
    @Published private(set) var cpuUsageText = "采样中"
    @Published private(set) var memoryUsageText = "-"
    @Published private(set) var loginItemStatusText = LoginItemStatus.disabled.title
    @Published private(set) var notificationStatusText = "未检查"
    @Published private(set) var corePath = "-"
    @Published private(set) var coreSHA256 = "-"
    @Published private(set) var coreInstallStatus = "未检查"
    @Published private(set) var coreDownloadURLText = "-"
    @Published private(set) var coreUpdateStatus = "未开始"
    @Published private(set) var profileImportStatus = "未开始"
    @Published private(set) var nodeDelayStatus = "未测速"
    @Published private(set) var selectedProfileID: String? {
        didSet {
            if let selectedProfileID {
                UserDefaults.standard.set(selectedProfileID, forKey: Self.selectedProfileIDDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedProfileIDDefaultsKey)
            }
        }
    }
    @Published private(set) var isProfileImportInProgress = false
    @Published private(set) var isCoreUpdateInProgress = false
    @Published private(set) var isDelayTesting = false
    @Published var coreDownloadVersion = "v1.19.24"
    @Published var coreExpectedSHA256 = ""
    @Published var profileImportName = ""
    @Published var profileDownloadURL = ""
    @Published var nodeSearchText = ""
    @Published var nodeTypeFilter = NodeTypeFilter.all
    @Published var nodeSortMode = NodeSortMode.original
    @Published var selectedProxyGroupID: String?
    @Published var proxyBypassText: String {
        didSet {
            UserDefaults.standard.set(proxyBypassText, forKey: Self.proxyBypassDefaultsKey)
        }
    }
    @Published var geoResourceURLTexts: [String: String] {
        didSet {
            UserDefaults.standard.set(geoResourceURLTexts, forKey: Self.geoResourceURLDefaultsKey)
        }
    }
    @Published var selectedMode = "rule"
    @Published var visiblePanel: AppPanel = .overview
    @Published private(set) var geoResourceRows: [GeoResourceSnapshot] = []
    @Published private(set) var geoResourceStatus = "未检查"
    @Published private(set) var syncingGeoResourceIDs: Set<String> = []

    let energyPolicy = EnergyPolicy.default

    private var paths: AppPaths?
    private var profileManager: ProfileManager?
    private var coreManager: CoreManager?
    private var controllerClient: ControllerClient?
    private var diagnosticsService: DiagnosticsService?
    private var coreBinaryManager: CoreBinaryManager?
    private var delayCacheStore: NodeDelayCacheStore?
    private let resourceMonitor = ResourceMonitor()
    private let loginItemService = LoginItemService()
    private let notificationService = UserNotificationService()
    private let nodeCatalogBuilder = NodeCatalogBuilder()
    private var systemProxyManager = SystemProxyManager()
    private var systemProxySnapshots: [NetworkServiceProxyState] = []
    private var trafficTask: Task<Void, Never>?
    private var lastTrafficSample: TrafficSample?
    private var lastAutomaticDelayRefreshDate: Date?
    private var bootstrapped = false
    private static let proxyBypassDefaultsKey = "proxyBypassText"
    private static let geoResourceURLDefaultsKey = "geoResourceURLTexts"
    private static let selectedProfileIDDefaultsKey = "selectedProfileID"

    init() {
        self.proxyBypassText = UserDefaults.standard.string(forKey: Self.proxyBypassDefaultsKey)
            ?? ProxyBypassRules.defaultText()
        let defaults = GeoResourceManager.defaultURLStrings()
        self.geoResourceURLTexts = defaults.merging(
            UserDefaults.standard.dictionary(forKey: Self.geoResourceURLDefaultsKey) as? [String: String] ?? [:],
            uniquingKeysWith: { _, custom in custom }
        )
        self.selectedProfileID = UserDefaults.standard.string(forKey: Self.selectedProfileIDDefaultsKey)
    }

    var menuSystemImage: String {
        isCoreRunning ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
    }

    var trafficText: String {
        "↑ \(Self.formatBytes(uploadBytesPerSecond))/s  ↓ \(Self.formatBytes(downloadBytesPerSecond))/s"
    }

    var terminalProxyCommand: String {
        "export http_proxy=http://127.0.0.1:9809 https_proxy=http://127.0.0.1:9809 all_proxy=socks5://127.0.0.1:9809"
    }

    func copyTerminalProxyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(terminalProxyCommand, forType: .string)
    }

    var proxyBypassEntries: [String] {
        ProxyBypassRules.normalize(proxyBypassText)
    }

    func resetProxyBypassEntries() {
        proxyBypassText = ProxyBypassRules.defaultText()
    }

    func geoResourceURLText(for id: String) -> String {
        geoResourceURLTexts[id] ?? GeoResourceManager.defaultURLStrings()[id] ?? ""
    }

    func setGeoResourceURLText(_ text: String, for id: String) {
        geoResourceURLTexts[id] = text
    }

    func resetGeoResourceURL(for id: String) {
        guard let defaultURL = GeoResourceManager.defaultURLStrings()[id] else {
            return
        }
        geoResourceURLTexts[id] = defaultURL
    }

    func bootstrap() async {
        guard !bootstrapped else {
            return
        }

        do {
            let paths = try AppPaths()
            try paths.createDirectories()
            self.paths = paths
            self.profileManager = ProfileManager(paths: paths)
            self.coreManager = CoreManager(paths: paths, energyPolicy: energyPolicy)
            self.diagnosticsService = DiagnosticsService(paths: paths, energyPolicy: energyPolicy)
            self.coreBinaryManager = CoreBinaryManager(paths: paths)
            self.delayCacheStore = NodeDelayCacheStore(fileURL: paths.baseDirectory.appendingPathComponent("node-delays.json"))
            self.applicationSupportPath = paths.baseDirectory.path
            self.runtimeConfigPath = paths.runtimeConfigURL.path
            try GeoResourceManager(paths: paths).ensureBundledResources()

            let secret = try KeychainSecretStore().loadOrCreateSecret(account: "controller")
            self.controllerClient = ControllerClient(endpoint: ControllerEndpoint(secret: secret))
            refreshLoginItemStatus()
            await refreshNotificationStatus()
            await refreshCoreInfo()
            await refreshGeoResources()
            await refreshProfiles()
            await refreshSelectedProfileProxyPreview()
            refreshCoreDownloadPreview()

            bootstrapped = true
            statusDetail = "初始化完成"
            lastError = nil
        } catch {
            setError(error)
        }
    }

    func refreshGeoResources() async {
        guard let paths else {
            geoResourceRows = GeoResourceManager.definitions.map { definition in
                GeoResourceSnapshot(
                    id: definition.id,
                    label: definition.label,
                    fileName: definition.fileName,
                    statusText: "未初始化",
                    detailText: definition.defaultURL.absoluteString,
                    urlText: geoResourceURLText(for: definition.id),
                    exists: false,
                    isSyncing: syncingGeoResourceIDs.contains(definition.id)
                )
            }
            return
        }

        do {
            let overrides = try GeoResourceManager.urlOverrides(from: geoResourceURLTexts)
            let rows = GeoResourceManager(paths: paths)
                .statuses(urlOverrides: overrides)
                .map { GeoResourceSnapshot(status: $0, isSyncing: syncingGeoResourceIDs.contains($0.id)) }
            geoResourceRows = rows
            let ready = rows.filter(\.exists).count
            geoResourceStatus = "\(ready)/\(rows.count) 已就绪"
            lastError = nil
        } catch {
            geoResourceStatus = error.localizedDescription
            setError(error)
        }
    }

    func syncGeoResource(id: String) {
        Task {
            await bootstrap()
            guard let paths else {
                return
            }
            guard let kind = GeoResourceKind(rawValue: id) else {
                return
            }

            do {
                let overrides = try GeoResourceManager.urlOverrides(from: geoResourceURLTexts)
                syncingGeoResourceIDs.insert(id)
                await refreshGeoResources()
                _ = try await GeoResourceManager(paths: paths).sync(kind: kind, url: overrides[kind])
                syncingGeoResourceIDs.remove(id)
                geoResourceStatus = "\(kind.label) 已同步"
                await refreshGeoResources()
                lastError = nil
            } catch {
                syncingGeoResourceIDs.remove(id)
                await refreshGeoResources()
                setError(error)
            }
        }
    }

    func startProxy() {
        Task {
            await bootstrap()
            await startProxyAsync()
        }
    }

    func stopProxy() {
        Task {
            await stopProxyAsync()
            await notificationService.notify(title: "MyClash 已停止", body: "mihomo core 已停止运行。")
        }
    }

    func shutdownForTermination() async {
        await stopProxyAsync()
    }

    func toggleSystemProxy() {
        Task {
            await bootstrap()
            do {
                if isSystemProxyEnabled {
                    if systemProxySnapshots.isEmpty {
                        let services = try await systemProxyManager.listConfigurableNetworkServices()
                        try await systemProxyManager.disableSystemProxy(services: services)
                    } else {
                        try await systemProxyManager.restore(systemProxySnapshots)
                        systemProxySnapshots = []
                    }
                    isSystemProxyEnabled = false
                    statusDetail = "系统代理已关闭"
                    await notificationService.notify(title: "系统代理已关闭", body: "macOS 系统代理已恢复为关闭状态。")
                } else {
                    guard isCoreRunning else {
                        throw AppViewModelError.startCoreBeforeSystemProxy
                    }
                    let services = try await systemProxyManager.listConfigurableNetworkServices()
                    systemProxySnapshots = try await systemProxyManager.enableSystemProxy(
                        services: services,
                        bypassDomains: proxyBypassEntries
                    )
                    isSystemProxyEnabled = true
                    statusDetail = "系统代理已开启：\(services.joined(separator: "、"))"
                    await notificationService.notify(title: "系统代理已开启", body: "HTTP、HTTPS 和 SOCKS 代理已指向 MyClash。")
                }
                lastError = nil
            } catch {
                setError(error)
            }
        }
    }

    func refreshOnce() {
        Task {
            await refreshVisiblePanel()
        }
    }

    func reportError(_ error: Error) {
        setError(error)
    }

    func toggleLoginItem() {
        Task {
            do {
                let current = loginItemService.status()
                let nextStatus = try loginItemService.setEnabled(current != .enabled)
                loginItemStatusText = nextStatus.title
                statusDetail = "开机启动：\(nextStatus.title)"
                lastError = nil
            } catch {
                setError(error)
            }
        }
    }

    func requestNotificationAuthorization() {
        Task {
            do {
                let granted = try await notificationService.requestAuthorization()
                notificationStatusText = granted ? "已授权" : "未授权"
                if granted {
                    await notificationService.notify(title: "MyClash 通知已开启", body: "后续关键状态变化会以低频通知提示。")
                }
            } catch {
                setError(error)
            }
        }
    }

    func refreshCoreInfo() async {
        guard let coreBinaryManager else {
            return
        }
        let info = await coreBinaryManager.installedInfo()
        corePath = info.url.path
        coreSHA256 = info.sha256 ?? "-"
        if info.isExecutable {
            coreInstallStatus = info.versionDescription ?? "已安装"
        } else if info.exists {
            coreInstallStatus = "文件存在但不可执行"
        } else {
            coreInstallStatus = "未安装"
        }
    }

    func refreshCoreDownloadPreview() {
        do {
            let manager = try coreBinaryManager ?? CoreBinaryManager(paths: AppPaths())
            coreDownloadURLText = try manager.releaseDownloadURL(version: coreDownloadVersion).absoluteString
            if !isCoreUpdateInProgress {
                coreUpdateStatus = "等待下载"
            }
            lastError = nil
        } catch {
            coreDownloadURLText = "-"
            coreUpdateStatus = error.localizedDescription
        }
    }

    func installCoreFromDownloadVersion() {
        Task {
            await bootstrap()
            guard let coreBinaryManager else {
                return
            }
            do {
                guard !isCoreRunning else {
                    throw AppViewModelError.stopCoreBeforeUpdating
                }
                refreshCoreDownloadPreview()
                let expectedSHA256 = coreExpectedSHA256.trimmingCharacters(in: .whitespacesAndNewlines)
                isCoreUpdateInProgress = true
                coreUpdateStatus = "正在下载 \(try CoreBinaryManager.normalizedReleaseVersion(coreDownloadVersion))"
                statusDetail = coreUpdateStatus
                let installedURL = try await coreBinaryManager.downloadAndInstall(
                    version: coreDownloadVersion,
                    expectedSHA256: expectedSHA256.isEmpty ? nil : expectedSHA256
                )
                coreUpdateStatus = "已安装"
                statusDetail = "core 已安装：\(installedURL.path)"
                await refreshCoreInfo()
                await notificationService.notify(title: "mihomo core 已安装", body: coreDownloadVersion)
                isCoreUpdateInProgress = false
            } catch {
                isCoreUpdateInProgress = false
                coreUpdateStatus = "更新失败"
                setError(error)
            }
        }
    }

    func importProfileFile(url: URL) {
        Task {
            await bootstrap()
            guard let profileManager else {
                return
            }

            do {
                guard !isCoreRunning else {
                    throw AppViewModelError.stopCoreBeforeLoadingProfile
                }

                isProfileImportInProgress = true
                profileImportStatus = "正在导入本地配置"
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let profile = try await profileManager.importProfile(
                    from: url,
                    name: profileImportName
                )
                try await activateProfile(profile, profileManager: profileManager)
                profileImportName = ""
                profileImportStatus = "已导入并加载：\(profile.name) · \(profile.metadata.qualityReport?.displayText ?? "未统计")"
                await refreshProfiles()
                visiblePanel = .nodes
                isProfileImportInProgress = false
            } catch {
                isProfileImportInProgress = false
                profileImportStatus = "导入失败"
                setError(error)
            }
        }
    }

    func downloadProfileFromURL() {
        Task {
            await bootstrap()
            guard let profileManager else {
                return
            }

            do {
                guard !isCoreRunning else {
                    throw AppViewModelError.stopCoreBeforeLoadingProfile
                }
                let url = try validatedProfileDownloadURL()
                isProfileImportInProgress = true
                profileImportStatus = "正在下载配置"

                let profile = try await profileManager.downloadProfile(
                    from: url,
                    name: profileImportName
                )
                try await activateProfile(profile, profileManager: profileManager)
                profileImportName = ""
                profileImportStatus = "已下载并加载：\(profile.name) · \(profile.metadata.qualityReport?.displayText ?? "未统计")"
                await refreshProfiles()
                visiblePanel = .nodes
                isProfileImportInProgress = false
            } catch {
                isProfileImportInProgress = false
                profileImportStatus = "下载失败"
                setError(error)
            }
        }
    }

    func loadProfile(id: String) {
        Task {
            await bootstrap()
            guard let profileManager else {
                return
            }

            do {
                guard !isCoreRunning else {
                    throw AppViewModelError.stopCoreBeforeLoadingProfile
                }
                let profile = try await profileManager.profile(id: id)
                try await activateProfile(profile, profileManager: profileManager)
                profileImportStatus = "已加载：\(profile.name)"
                await refreshProfiles()
                visiblePanel = .nodes
            } catch {
                setError(error)
            }
        }
    }

    func updateProfile(id: String) {
        Task {
            await bootstrap()
            guard let profileManager else {
                return
            }

            do {
                guard !isCoreRunning else {
                    throw AppViewModelError.stopCoreBeforeLoadingProfile
                }
                isProfileImportInProgress = true
                profileImportStatus = "正在同步配置"
                let profile = try await profileManager.updateProfile(id: id)
                try await activateProfile(profile, profileManager: profileManager)
                profileImportStatus = "已同步并加载：\(profile.name) · \(profile.metadata.qualityReport?.displayText ?? "未统计")"
                await refreshProfiles()
                visiblePanel = .nodes
                isProfileImportInProgress = false
            } catch {
                isProfileImportInProgress = false
                profileImportStatus = "同步失败"
                setError(error)
            }
        }
    }

    func updateAllURLProfiles() {
        Task {
            await bootstrap()
            guard let profileManager else {
                return
            }

            do {
                guard !isCoreRunning else {
                    throw AppViewModelError.stopCoreBeforeLoadingProfile
                }
                isProfileImportInProgress = true
                profileImportStatus = "正在批量同步 URL 配置"
                let profiles = try await profileManager.listProfiles()
                    .filter { $0.metadata.source == .url }
                guard !profiles.isEmpty else {
                    profileImportStatus = "没有可同步的 URL 配置"
                    isProfileImportInProgress = false
                    return
                }

                var successCount = 0
                var failedNames: [String] = []
                var activeProfile: Profile?
                for profile in profiles {
                    do {
                        let updated = try await profileManager.updateProfile(id: profile.id)
                        successCount += 1
                        if profile.id == selectedProfileID {
                            activeProfile = updated
                        }
                    } catch {
                        failedNames.append(profile.name)
                    }
                }

                if let activeProfile {
                    try await activateProfile(activeProfile, profileManager: profileManager)
                }
                await refreshProfiles()
                profileImportStatus = failedNames.isEmpty
                    ? "批量同步完成：\(successCount)/\(profiles.count) 成功"
                    : "批量同步完成：\(successCount)/\(profiles.count) 成功，失败：\(failedNames.joined(separator: "、"))"
                isProfileImportInProgress = false
            } catch {
                isProfileImportInProgress = false
                profileImportStatus = "批量同步失败"
                setError(error)
            }
        }
    }

    func deleteProfile(id: String) {
        Task {
            await bootstrap()
            guard let profileManager else {
                return
            }
            do {
                guard !isCoreRunning else {
                    throw AppViewModelError.stopCoreBeforeLoadingProfile
                }
                try await profileManager.deleteProfile(id: id)
                if selectedProfileID == id {
                    selectedProfileID = nil
                    proxyGroups = []
                    preferredExpandedProxyGroupIDs = []
                }
                profileImportStatus = "已删除配置"
                await refreshProfiles()
            } catch {
                setError(error)
            }
        }
    }

    func exportDiagnostics() {
        Task {
            do {
                let snapshot = diagnosticsService?.snapshot(coreStateDescription: statusText)
                if let snapshot {
                    let usage = await resourceMonitor.sample()
                    var enriched = snapshot
                    enriched.resourceUsage = usage
                    let result = try diagnosticsService?.exportPackage(snapshot: enriched)
                    statusDetail = "诊断包已导出：\(result?.directory.path ?? "-")"
                }
            } catch {
                setError(error)
            }
        }
    }

    private func startProxyAsync() async {
        guard let paths, let profileManager, let controllerClient, let coreManager else {
            statusDetail = "初始化未完成"
            return
        }

        do {
            statusText = "启动中"
            statusDetail = "生成运行配置"

            let secret = try KeychainSecretStore().loadOrCreateSecret(account: "controller")
            let profile = try await selectedOrDefaultProfile(profileManager: profileManager)
            try await updateProxyPreview(for: profile, profileManager: profileManager)
            let generated = try await profileManager.generateRuntimeConfig(
                for: profile,
                secret: secret,
                options: currentRuntimeConfigOptions()
            )
            try await profileManager.installRuntimeConfig(from: generated)

            statusDetail = "启动 mihomo core"
            try await coreManager.start(controller: controllerClient)

            let state = await coreManager.state
            if case let .running(version) = state {
                coreVersion = version ?? "-"
            }
            try await applyPersistedSelections(for: profile, controllerClient: controllerClient)
            isCoreRunning = true
            statusText = "运行中"
            statusDetail = "Controller 已连接"
            lastError = nil
            await refreshProxies()
            startLowEnergyTrafficLoop(paths: paths)
            await notificationService.notify(title: "MyClash 已启动", body: "mihomo core 已开始运行。")
        } catch {
            isCoreRunning = false
            setError(error)
        }
    }

    private func stopProxyAsync() async {
        trafficTask?.cancel()
        trafficTask = nil
        await coreManager?.stop()
        isCoreRunning = false
        statusText = "未启动"
        statusDetail = "mihomo 已停止"
        coreVersion = "-"
        uploadBytesPerSecond = 0
        downloadBytesPerSecond = 0
        lastTrafficSample = nil
        activeConnections = 0
        connectionRows = []
    }

    private func selectedOrDefaultProfile(profileManager: ProfileManager) async throws -> Profile {
        if let selectedProfileID,
           let profile = try? await profileManager.profile(id: selectedProfileID) {
            return profile
        }

        let profiles = try await profileManager.listProfiles()
        if let firstProfile = profiles.first {
            selectedProfileID = firstProfile.id
            return firstProfile
        }

        let id = ProfileManager.stableIdentifier(for: "default")
        if let profile = try? await profileManager.profile(id: id, name: "default") {
            selectedProfileID = profile.id
            return profile
        }

        let raw = """
        proxies: []
        proxy-groups: []
        rules:
          - MATCH,DIRECT
        """
        let profile = try await profileManager.createLocalProfile(name: "default", rawConfig: raw)
        selectedProfileID = profile.id
        return profile
    }

    private func refreshStatus() async {
        guard let controllerClient else {
            return
        }
        do {
            let version = try await controllerClient.version()
            let connections = try await controllerClient.connections()
            await refreshResourceUsage()
            updateTrafficRates(from: connections)
            coreVersion = version.version ?? "-"
            activeConnections = connections.connections.count
            connectionRows = connections.connections.map(ConnectionSnapshot.init)
            isCoreRunning = true
            statusText = "运行中"
            lastError = nil
        } catch {
            if isCoreRunning, let coreManager {
                let coreState = await coreManager.state
                switch coreState {
                case .stopped:
                    markCoreNotRunning(status: "未启动", detail: "mihomo 已停止")
                    return
                case let .failed(message):
                    let detail = latestCoreLogError() ?? message
                    markCoreNotRunning(status: "异常", detail: detail)
                    return
                case .starting, .running, .stopping:
                    break
                }
            }

            if isCoreRunning {
                setError(error)
            }
        }
    }

    func refreshResourceUsage() async {
        let usage = await resourceMonitor.sample()
        if let cpu = usage.cpuPercentSincePreviousSample {
            cpuUsageText = String(format: "%.1f%%", cpu)
        }
        memoryUsageText = Self.formatBytes(usage.maximumResidentSetSizeBytes)
    }

    func refreshLoginItemStatus() {
        loginItemStatusText = loginItemService.status().title
    }

    func refreshNotificationStatus() async {
        let status = await notificationService.authorizationStatus()
        switch status {
        case .authorized, .provisional:
            notificationStatusText = "已授权"
        case .denied:
            notificationStatusText = "已拒绝"
        case .notDetermined:
            notificationStatusText = "未请求"
        @unknown default:
            notificationStatusText = "未知"
        }
    }

    private func startLowEnergyTrafficLoop(paths: AppPaths) {
        trafficTask?.cancel()
        trafficTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                await self.refreshVisiblePanel()
                let interval = self.energyPolicy.trafficInterval(
                    upBytesPerSecond: self.uploadBytesPerSecond,
                    downBytesPerSecond: self.downloadBytesPerSecond,
                    isVisible: self.visiblePanel == .overview
                )
                try? await Task.sleep(for: interval)
            }
        }

        statusDetail = "低频状态刷新已启用：\(paths.runtimeDirectory.path)"
    }

    private func refreshVisiblePanel() async {
        switch visiblePanel {
        case .overview:
            await refreshStatus()
        case .nodes:
            await refreshProxies()
        case .profiles:
            await refreshProfiles()
        case .connections:
            await refreshConnections()
        case .logs:
            refreshRecentLogs()
        case .settings:
            break
        }
    }

    func refreshProxies() async {
        guard isCoreRunning else {
            await refreshSelectedProfileProxyPreview()
            return
        }

        guard let controllerClient else {
            return
        }
        do {
            let proxies = try await controllerClient.proxies()
            applyNodeCatalog(nodeCatalogBuilder.runtimeCatalog(collection: proxies), preferredExpandedIDs: preferredExpandedProxyGroupIDs)
            await applyCachedDelays()
            await refreshProxyProviderRuntimeState()
            scheduleAutomaticDelayRefreshIfNeeded()
            lastError = nil
        } catch {
            if isCoreRunning {
                setError(error)
            } else {
                await refreshSelectedProfileProxyPreview()
            }
        }
    }

    func selectProxy(groupName: String, proxyName: String) {
        Task {
            guard let controllerClient else {
                return
            }
            do {
                try await controllerClient.selectProxy(groupName: groupName, proxyName: proxyName)
                if let selectedProfileID, let profileManager {
                    _ = try await profileManager.saveSelectedProxy(
                        profileID: selectedProfileID,
                        groupName: groupName,
                        proxyName: proxyName
                    )
                }
                await refreshProxies()
            } catch {
                setError(error)
            }
        }
    }

    func testDelayForVisibleNodes() {
        Task {
            await bootstrap()
            guard isCoreRunning else {
                nodeDelayStatus = "请先启动代理后再测速"
                return
            }

            let proxyNames = Array(Set(proxyGroups.flatMap(\.nodes).map(\.name)))
                .filter { !$0.isEmpty && $0 != "-" }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            guard !proxyNames.isEmpty else {
                nodeDelayStatus = "暂无可测速节点"
                return
            }

            await performDelayTest(proxyNames: proxyNames, title: "测速")
        }
    }

    func refreshProxyProvider(name: String) {
        Task {
            await bootstrap()
            guard let controllerClient else {
                return
            }
            guard isCoreRunning else {
                proxyProviderStatus = "请先启动代理后再刷新 Provider"
                return
            }
            do {
                proxyProviderStatus = "正在刷新 \(name)"
                try await controllerClient.refreshProxyProvider(name: name)
                try await Task.sleep(for: .seconds(1))
                await refreshProxyProviderRuntimeState()
                proxyProviderStatus = "Provider 已刷新：\(name)"
            } catch {
                proxyProviderStatus = "Provider 刷新失败"
                setError(error)
            }
        }
    }

    var selectedProxyGroup: ProxyGroupSnapshot? {
        if let selectedProxyGroupID,
           let group = proxyGroups.first(where: { $0.id == selectedProxyGroupID }) {
            return group
        }
        return proxyGroups.first
    }

    var visibleNodeRows: [ProxyNodeSnapshot] {
        guard let selectedProxyGroup else {
            return []
        }

        let query = nodeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var nodes = selectedProxyGroup.nodes.filter { node in
            let matchesQuery = query.isEmpty
                || node.name.localizedCaseInsensitiveContains(query)
                || node.type.localizedCaseInsensitiveContains(query)
            return matchesQuery && nodeTypeFilter.matches(node)
        }

        switch nodeSortMode {
        case .original:
            return nodes
        case .delay:
            nodes.sort { left, right in
                let leftDelay = left.sortableDelay
                let rightDelay = right.sortableDelay
                if leftDelay == rightDelay {
                    return left.name.localizedStandardCompare(right.name) == .orderedAscending
                }
                return leftDelay < rightDelay
            }
        case .name:
            nodes.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .type:
            nodes.sort {
                if $0.type == $1.type {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.type.localizedStandardCompare($1.type) == .orderedAscending
            }
        }
        return nodes
    }

    func refreshConnections() async {
        guard let controllerClient else {
            return
        }
        do {
            let connections = try await controllerClient.connections()
            updateTrafficRates(from: connections)
            activeConnections = connections.connections.count
            connectionRows = connections.connections.map(ConnectionSnapshot.init)
            lastError = nil
        } catch {
            setError(error)
        }
    }

    func closeConnection(id: String) {
        Task {
            guard let controllerClient else {
                return
            }
            do {
                try await controllerClient.closeConnection(id: id)
                await refreshConnections()
            } catch {
                setError(error)
            }
        }
    }

    func closeAllConnections() {
        Task {
            guard let controllerClient else {
                return
            }
            do {
                try await controllerClient.closeAllConnections()
                await refreshConnections()
            } catch {
                setError(error)
            }
        }
    }

    func refreshProfiles() async {
        guard let profileManager else {
            return
        }
        do {
            profileRows = try await profileManager.listProfiles().map(ProfileSnapshot.init)
            if let selectedProfileID,
               !profileRows.contains(where: { $0.id == selectedProfileID }) {
                self.selectedProfileID = nil
            }
            lastError = nil
        } catch {
            setError(error)
        }
    }

    func saveExpandedProxyGroups(_ ids: Set<String>) {
        preferredExpandedProxyGroupIDs = ids
        Task {
            guard let selectedProfileID, let profileManager else {
                return
            }
            _ = try? await profileManager.saveUnfoldSet(profileID: selectedProfileID, unfoldSet: ids)
        }
    }

    func refreshRecentLogs() {
        guard let paths else {
            return
        }
        do {
            let url = paths.coreLogURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                recentLogs = "暂无 core 日志。"
                return
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }
            let fileSize = try handle.seekToEnd()
            let bytesToRead: UInt64 = min(fileSize, 24 * 1024)
            try handle.seek(toOffset: fileSize - bytesToRead)
            let data = handle.readDataToEndOfFile()
            recentLogs = String(data: data, encoding: .utf8) ?? "日志包含不可解码内容。"
        } catch {
            setError(error)
        }
    }

    private func updateTrafficRates(from connections: ConnectionCollection, now: Date = Date()) {
        guard let uploadTotal = connections.uploadTotal,
              let downloadTotal = connections.downloadTotal,
              uploadTotal >= 0,
              downloadTotal >= 0
        else {
            uploadBytesPerSecond = 0
            downloadBytesPerSecond = 0
            lastTrafficSample = nil
            return
        }

        let current = TrafficSample(
            uploadTotal: UInt64(uploadTotal),
            downloadTotal: UInt64(downloadTotal),
            date: now
        )
        defer {
            lastTrafficSample = current
        }

        guard let previous = lastTrafficSample else {
            uploadBytesPerSecond = 0
            downloadBytesPerSecond = 0
            return
        }

        if current.uploadTotal < previous.uploadTotal || current.downloadTotal < previous.downloadTotal {
            uploadBytesPerSecond = 0
            downloadBytesPerSecond = 0
            return
        }

        let elapsed = max(current.date.timeIntervalSince(previous.date), 0.001)
        uploadBytesPerSecond = UInt64(Double(current.uploadTotal - previous.uploadTotal) / elapsed)
        downloadBytesPerSecond = UInt64(Double(current.downloadTotal - previous.downloadTotal) / elapsed)
    }

    private func setError(_ error: Error) {
        lastError = error.localizedDescription
        statusText = "异常"
        statusDetail = error.localizedDescription
        Task {
            await notificationService.notifyError(title: "MyClash 异常", body: error.localizedDescription)
        }
    }

    private func activateProfile(_ profile: Profile, profileManager: ProfileManager) async throws {
        let secret = try KeychainSecretStore().loadOrCreateSecret(account: "controller")
        let generated = try await profileManager.generateRuntimeConfig(
            for: profile,
            secret: secret,
            options: currentRuntimeConfigOptions()
        )
        try await profileManager.installRuntimeConfig(from: generated)
        selectedProfileID = profile.id
        try await updateProxyPreview(for: profile, profileManager: profileManager)
        statusDetail = "已加载配置：\(profile.name)"
        lastError = nil
    }

    private func currentRuntimeConfigOptions() throws -> RuntimeConfigOptions {
        RuntimeConfigOptions(
            mode: selectedMode,
            bypassEntries: proxyBypassEntries,
            geoResourceURLs: try GeoResourceManager.urlOverrides(from: geoResourceURLTexts)
        )
    }

    private func refreshSelectedProfileProxyPreview() async {
        guard let profileManager, let selectedProfileID else {
            return
        }

        do {
            let profile = try await profileManager.profile(id: selectedProfileID)
            try await updateProxyPreview(for: profile, profileManager: profileManager)
            lastError = nil
        } catch {
            setError(error)
        }
    }

    private func updateProxyPreview(for profile: Profile, profileManager: ProfileManager) async throws {
        let preview = try await profileManager.proxyPreview(for: profile)
        proxyProviderRows = try await profileManager.proxyProviders(for: profile).map(ProxyProviderSnapshot.init)
        applyNodeCatalog(
            nodeCatalogBuilder.previewCatalog(groups: preview),
            preferredExpandedIDs: profile.metadata.unfoldSet
        )
        await applyCachedDelays()
    }

    private func applyNodeCatalog(_ catalog: NodeCatalog, preferredExpandedIDs: Set<String>) {
        proxyGroups = catalog.groups.map(ProxyGroupSnapshot.init)
        nodeCatalogSourceText = catalog.source == .runtime ? "运行时" : "预览"
        if let selectedProxyGroupID,
           proxyGroups.contains(where: { $0.id == selectedProxyGroupID }) {
        } else {
            selectedProxyGroupID = proxyGroups.first?.id
        }
        if preferredExpandedIDs.isEmpty {
            preferredExpandedProxyGroupIDs = Set(proxyGroups.map(\.id))
        } else {
            preferredExpandedProxyGroupIDs = preferredExpandedIDs
        }
    }

    private func applyDelayResults(_ delays: [String: Int]) {
        proxyGroups = proxyGroups.map { group in
            group.updatingDelays(delays)
        }
    }

    private func applyCachedDelays(maxAge: TimeInterval = 7 * 24 * 60 * 60) async {
        guard let delayCacheStore else {
            return
        }
        let delays = await delayCacheStore.delays(maxAge: maxAge)
        guard !delays.isEmpty else {
            return
        }
        applyDelayResults(delays)
    }

    private func performDelayTest(proxyNames: [String], title: String) async {
        guard let controllerClient else {
            return
        }
        guard !isDelayTesting else {
            return
        }

        isDelayTesting = true
        nodeDelayStatus = "\(title)中 \(proxyNames.count) 个节点"

        var delayResults: [String: Int] = [:]
        for batch in proxyNames.chunked(into: 16) {
            await withTaskGroup(of: (String, Int?).self) { group in
                for proxyName in batch {
                    group.addTask {
                        do {
                            let delay = try await controllerClient.proxyDelay(proxyName: proxyName)
                            return (proxyName, delay.delay)
                        } catch {
                            return (proxyName, -1)
                        }
                    }
                }

                for await (proxyName, delay) in group {
                    if let delay {
                        delayResults[proxyName] = delay
                    }
                }
            }
            applyDelayResults(delayResults)
        }

        if !delayResults.isEmpty {
            try? await delayCacheStore?.upsert(delayResults)
        }
        isDelayTesting = false
        let okCount = delayResults.values.filter { $0 > 0 }.count
        nodeDelayStatus = "\(title)完成：\(okCount)/\(proxyNames.count) 可用"
    }

    private func scheduleAutomaticDelayRefreshIfNeeded() {
        guard isCoreRunning,
              visiblePanel == .nodes,
              !isDelayTesting
        else {
            return
        }

        let now = Date()
        if let lastAutomaticDelayRefreshDate,
           now.timeIntervalSince(lastAutomaticDelayRefreshDate) < 10 * 60 {
            return
        }

        let proxyNames = Array(Set(visibleNodeRows.prefix(48).map(\.name)))
            .filter { !$0.isEmpty && $0 != "-" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !proxyNames.isEmpty else {
            return
        }

        lastAutomaticDelayRefreshDate = now
        Task {
            await performDelayTest(proxyNames: proxyNames, title: "自动测速")
        }
    }

    private func refreshProxyProviderRuntimeState() async {
        guard let controllerClient, isCoreRunning else {
            return
        }
        do {
            let runtimeProviders = try await controllerClient.proxyProviders().providers
            proxyProviderRows = proxyProviderRows.map { provider in
                provider.withRuntime(runtimeProviders[provider.name])
            }
            proxyProviderStatus = runtimeProviders.isEmpty ? "Provider 运行态为空" : "Provider 已刷新"
        } catch {
            proxyProviderStatus = "Provider 运行态读取失败"
        }
    }

    private func applyPersistedSelections(for profile: Profile, controllerClient: ControllerClient) async throws {
        for (groupName, proxyName) in profile.metadata.selectedMap {
            try? await controllerClient.selectProxy(groupName: groupName, proxyName: proxyName)
        }
    }

    private func validatedProfileDownloadURL() throws -> URL {
        let trimmed = profileDownloadURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else {
            throw AppViewModelError.invalidProfileURL
        }
        return url
    }

    private func markCoreNotRunning(status: String, detail: String) {
        trafficTask?.cancel()
        trafficTask = nil
        isCoreRunning = false
        statusText = status
        statusDetail = detail
        lastError = status == "异常" ? detail : nil
        uploadBytesPerSecond = 0
        downloadBytesPerSecond = 0
        lastTrafficSample = nil
        activeConnections = 0
        connectionRows = []
    }

    private func latestCoreLogError() -> String? {
        guard let paths,
              let logText = try? String(contentsOf: paths.coreLogURL, encoding: .utf8)
        else {
            return nil
        }

        return logText
            .split(separator: "\n")
            .reversed()
            .first { $0.contains("level=error") }
            .map(String.init)
    }

    nonisolated static func formatBytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var number = Double(value)
        var index = 0
        while number >= 1024, index < units.count - 1 {
            number /= 1024
            index += 1
        }
        return String(format: "%.1f %@", number, units[index])
    }
}

private struct TrafficSample {
    let uploadTotal: UInt64
    let downloadTotal: UInt64
    let date: Date
}

private enum AppViewModelError: Error, LocalizedError {
    case stopCoreBeforeUpdating
    case stopCoreBeforeLoadingProfile
    case startCoreBeforeSystemProxy
    case invalidProfileURL
    case profileDownloadFailed(String)
    case profileTooLarge
    case invalidProfileText

    var errorDescription: String? {
        switch self {
        case .stopCoreBeforeUpdating:
            return "请先停止 mihomo core，再更新二进制文件。"
        case .stopCoreBeforeLoadingProfile:
            return "请先停止 mihomo core，再导入或加载配置。"
        case .startCoreBeforeSystemProxy:
            return "请先启动 mihomo core，再开启系统代理。"
        case .invalidProfileURL:
            return "请输入有效的 HTTP 或 HTTPS 配置 URL。"
        case let .profileDownloadFailed(message):
            return "配置下载失败：\(message)"
        case .profileTooLarge:
            return "配置文件超过 16 MB，请检查订阅内容。"
        case .invalidProfileText:
            return "配置内容不是有效的 UTF-8 文本。"
        }
    }
}

struct ProxyGroupSnapshot: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let type: String
    let now: String
    let nodes: [ProxyNodeSnapshot]
    var all: [String] { nodes.map(\.name) }

    init(item: ProxyItem) {
        self.name = item.name ?? "-"
        self.type = item.type ?? "-"
        self.now = item.now ?? "-"
        self.nodes = (item.all ?? []).map { ProxyNodeSnapshot(name: $0, type: "-", delayMilliseconds: nil, isSelected: $0 == (item.now ?? "-")) }
    }

    init(item: ProfileProxyGroup) {
        self.name = item.name
        self.type = item.type
        self.now = item.now
        self.nodes = item.all.map { ProxyNodeSnapshot(name: $0, type: "-", delayMilliseconds: nil, isSelected: $0 == item.now) }
    }

    init(item: NodeGroup) {
        self.name = item.name
        self.type = item.type
        self.now = item.now
        self.nodes = item.nodes.map(ProxyNodeSnapshot.init)
    }

    private init(name: String, type: String, now: String, nodes: [ProxyNodeSnapshot]) {
        self.name = name
        self.type = type
        self.now = now
        self.nodes = nodes
    }

    func updatingDelays(_ delays: [String: Int]) -> ProxyGroupSnapshot {
        ProxyGroupSnapshot(
            name: name,
            type: type,
            now: now,
            nodes: nodes.map { node in
                guard let delay = delays[node.name] else {
                    return node
                }
                return node.updatingDelay(delay)
            }
        )
    }
}

struct GeoResourceSnapshot: Identifiable, Equatable {
    let id: String
    let label: String
    let fileName: String
    let statusText: String
    let detailText: String
    let urlText: String
    let exists: Bool
    let isSyncing: Bool

    init(
        id: String,
        label: String,
        fileName: String,
        statusText: String,
        detailText: String,
        urlText: String,
        exists: Bool,
        isSyncing: Bool
    ) {
        self.id = id
        self.label = label
        self.fileName = fileName
        self.statusText = statusText
        self.detailText = detailText
        self.urlText = urlText
        self.exists = exists
        self.isSyncing = isSyncing
    }

    init(status: GeoResourceStatus, isSyncing: Bool) {
        let modifiedText = status.lastModified.map {
            DateFormatter.geoResourceFormatter.string(from: $0)
        } ?? "-"
        self.init(
            id: status.id,
            label: status.definition.label,
            fileName: status.definition.fileName,
            statusText: status.exists ? "\(AppViewModel.formatBytes(status.size)) · \(modifiedText)" : "缺失",
            detailText: status.fileURL.path,
            urlText: status.sourceURL.absoluteString,
            exists: status.exists,
            isSyncing: isSyncing
        )
    }
}

private extension DateFormatter {
    static let geoResourceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

struct ProxyNodeSnapshot: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let type: String
    let delayMilliseconds: Int?
    let isSelected: Bool

    var delayText: String? {
        guard let delayMilliseconds else {
            return nil
        }
        if delayMilliseconds == 0 {
            return "测速中"
        }
        if delayMilliseconds > 0 {
            return "\(delayMilliseconds) ms"
        }
        return "超时"
    }

    var delayColor: Color {
        guard let delayMilliseconds else {
            return .secondary
        }
        if delayMilliseconds == 0 {
            return .secondary
        }
        if delayMilliseconds < 0 {
            return .red
        }
        if delayMilliseconds <= 150 {
            return .green
        }
        if delayMilliseconds <= 400 {
            return .orange
        }
        return .red
    }

    var sortableDelay: Int {
        guard let delayMilliseconds else {
            return Int.max - 1
        }
        return delayMilliseconds > 0 ? delayMilliseconds : Int.max
    }

    init(name: String, type: String, delayMilliseconds: Int?, isSelected: Bool) {
        self.name = name
        self.type = type
        self.delayMilliseconds = delayMilliseconds
        self.isSelected = isSelected
    }

    init(item: NodeItem) {
        self.name = item.name
        self.type = item.type
        self.delayMilliseconds = item.delayMilliseconds
        self.isSelected = item.isSelected
    }

    func updatingDelay(_ delay: Int) -> ProxyNodeSnapshot {
        ProxyNodeSnapshot(name: name, type: type, delayMilliseconds: delay, isSelected: isSelected)
    }
}

enum NodeTypeFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case reachable = "可用"
    case selected = "已选"
    case hysteria2 = "Hysteria2"
    case anyTLS = "AnyTLS"
    case other = "其他"

    var id: String { rawValue }

    func matches(_ node: ProxyNodeSnapshot) -> Bool {
        switch self {
        case .all:
            return true
        case .reachable:
            return (node.delayMilliseconds ?? -1) > 0
        case .selected:
            return node.isSelected
        case .hysteria2:
            return node.type.localizedCaseInsensitiveContains("hysteria2")
        case .anyTLS:
            return node.type.localizedCaseInsensitiveContains("anytls")
        case .other:
            return !node.type.localizedCaseInsensitiveContains("hysteria2")
                && !node.type.localizedCaseInsensitiveContains("anytls")
        }
    }
}

enum NodeSortMode: String, CaseIterable, Identifiable {
    case original = "原始"
    case delay = "延迟"
    case name = "名称"
    case type = "类型"

    var id: String { rawValue }
}

struct ConnectionSnapshot: Identifiable, Equatable {
    let id: String
    let rule: String
    let chains: String
    let upload: String
    let download: String

    init(item: ConnectionItem) {
        self.id = item.id
        self.rule = item.rulePayload.map { "\(item.rule ?? "-") / \($0)" } ?? (item.rule ?? "-")
        self.chains = (item.chains ?? []).joined(separator: " / ")
        self.upload = AppViewModel.formatBytes(UInt64(max(0, item.upload ?? 0)))
        self.download = AppViewModel.formatBytes(UInt64(max(0, item.download ?? 0)))
    }
}

struct ProxyProviderSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    let path: String
    let urlHost: String
    let intervalText: String
    let healthCheckText: String
    let runtimeText: String
    let nodeCountText: String

    init(item: ProfileProxyProvider) {
        self.id = item.id
        self.name = item.name
        self.type = item.type
        self.path = item.path ?? "-"
        if let url = item.url, let host = URL(string: url)?.host {
            self.urlHost = host
        } else if let url = item.url, !url.isEmpty {
            self.urlHost = url
        } else {
            self.urlHost = "-"
        }
        if let interval = item.interval, interval > 0 {
            self.intervalText = "\(interval / 60) 分钟"
        } else {
            self.intervalText = "-"
        }
        self.healthCheckText = item.healthCheckEnabled ? "健康检查" : "未启用"
        self.runtimeText = "预览"
        self.nodeCountText = "-"
    }

    private init(
        id: String,
        name: String,
        type: String,
        path: String,
        urlHost: String,
        intervalText: String,
        healthCheckText: String,
        runtimeText: String,
        nodeCountText: String
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
        self.urlHost = urlHost
        self.intervalText = intervalText
        self.healthCheckText = healthCheckText
        self.runtimeText = runtimeText
        self.nodeCountText = nodeCountText
    }

    func withRuntime(_ runtime: RuntimeProxyProvider?) -> ProxyProviderSnapshot {
        guard let runtime else {
            return self
        }
        let runtimeType = [runtime.vehicleType, runtime.type]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        let nodeCount = runtime.proxies?.count ?? 0
        return ProxyProviderSnapshot(
            id: id,
            name: name,
            type: type,
            path: path,
            urlHost: urlHost,
            intervalText: intervalText,
            healthCheckText: healthCheckText,
            runtimeText: runtimeType.isEmpty ? "运行时" : runtimeType,
            nodeCountText: "\(nodeCount) 节点"
        )
    }
}

struct ProfileSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let rawConfigPath: String
    let overrideConfigPath: String
    let generatedConfigPath: String
    let sourceDetail: String
    let updatedText: String
    let subscriptionText: String?
    let qualityText: String?
    let isURLProfile: Bool

    init(profile: Profile) {
        self.id = profile.id
        self.name = profile.name
        self.rawConfigPath = profile.rawConfigURL.path
        self.overrideConfigPath = profile.overrideConfigURL.path
        self.generatedConfigPath = profile.generatedConfigURL.path
        let source = profile.metadata.source == .url ? "URL" : "本地"
        let selectedCount = profile.metadata.selectedMap.count
        self.isURLProfile = profile.metadata.source == .url
        if let sourceURL = profile.metadata.sourceURL, !sourceURL.isEmpty {
            self.sourceDetail = "\(source)：\(sourceURL) · 已记录 \(selectedCount) 个选择"
        } else {
            self.sourceDetail = "\(source) · 已记录 \(selectedCount) 个选择"
        }
        if let lastUpdateDate = profile.metadata.lastUpdateDate {
            self.updatedText = Self.formatDate(lastUpdateDate)
        } else {
            self.updatedText = "未更新"
        }
        self.subscriptionText = profile.metadata.subscriptionInfo.map { info in
            let used = info.upload + info.download
            let total = info.total
            guard total > 0 else {
                return "订阅流量：-"
            }
            return "订阅流量：\(AppViewModel.formatBytes(UInt64(max(0, used)))) / \(AppViewModel.formatBytes(UInt64(total)))"
        }
        self.qualityText = profile.metadata.qualityReport?.displayText
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

enum AppPanel: String, CaseIterable, Identifiable {
    case overview = "概览"
    case nodes = "节点"
    case profiles = "配置"
    case connections = "连接"
    case logs = "日志"
    case settings = "设置"

    var id: String { rawValue }
}
