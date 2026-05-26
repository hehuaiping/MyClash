import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            List(AppPanel.allCases, selection: $appModel.visiblePanel) { panel in
                Label(panel.rawValue, systemImage: icon(for: panel))
                    .tag(panel)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Group {
                switch appModel.visiblePanel {
                case .overview:
                    OverviewView()
                case .nodes:
                    NodesView()
                case .profiles:
                    ProfilesView()
                case .connections:
                    ConnectionsView()
                case .logs:
                    LogsView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationTitle(appModel.visiblePanel.rawValue)
        }
    }

    private func icon(for panel: AppPanel) -> String {
        switch panel {
        case .overview:
            return "gauge.with.dots.needle.67percent"
        case .nodes:
            return "point.3.connected.trianglepath.dotted"
        case .profiles:
            return "doc.text"
        case .connections:
            return "link"
        case .logs:
            return "text.alignleft"
        case .settings:
            return "gearshape"
        }
    }
}

struct NodesView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var expandedProxyGroupIDs: Set<String> = []
    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("策略组")
                    .font(.headline)
                Text(appModel.nodeCatalogSourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.45), in: Capsule())
                Spacer()
                if appModel.isCoreRunning {
                    Button {
                        appModel.testDelayForVisibleNodes()
                    } label: {
                        Label(appModel.isDelayTesting ? "测速中" : "延迟测试", systemImage: "network")
                    }
                    .disabled(appModel.isDelayTesting || appModel.proxyGroups.isEmpty)
                }
                Button {
                    Task { await appModel.refreshProxies() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            Text(appModel.nodeDelayStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            if appModel.proxyGroups.isEmpty {
                PlaceholderPanelView(title: "暂无节点数据", systemImage: "point.3.connected.trianglepath.dotted", detail: "导入或加载配置后会显示节点预览；启动 mihomo 后会同步运行时节点状态。")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    groupTabs
                    nodeToolbar
                    if let group = appModel.selectedProxyGroup {
                        Text("\(group.type) · \(group.now)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(appModel.visibleNodeRows) { proxy in
                                nodeCard(proxy)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .overlay {
                        if appModel.visibleNodeRows.isEmpty {
                            PlaceholderPanelView(title: "无匹配节点", systemImage: "magnifyingglass", detail: "调整搜索、类型或排序条件后再查看。")
                        }
                    }

                    if !appModel.proxyProviderRows.isEmpty {
                        Divider()
                        providerSection
                    }
                }
            }
        }
        .padding(24)
        .task {
            await appModel.refreshProxies()
        }
        .onAppear {
            applyPreferredExpandedGroups()
        }
        .onChange(of: appModel.proxyGroups) { groups in
            applyPreferredExpandedGroups(groups: groups)
        }
        .onChange(of: appModel.preferredExpandedProxyGroupIDs) { _ in
            applyPreferredExpandedGroups()
        }
    }

    private var groupTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appModel.proxyGroups) { group in
                    Button {
                        appModel.selectedProxyGroupID = group.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(group.name)
                                .lineLimit(1)
                            Text("\(group.all.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(appModel.selectedProxyGroupID == group.id ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var nodeToolbar: some View {
        HStack(spacing: 10) {
            TextField("搜索节点", text: $appModel.nodeSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 280)
            Picker("类型", selection: $appModel.nodeTypeFilter) {
                ForEach(NodeTypeFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            Picker("排序", selection: $appModel.nodeSortMode) {
                ForEach(NodeSortMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            Spacer()
            Text("\(appModel.visibleNodeRows.count) / \(appModel.selectedProxyGroup?.nodes.count ?? 0)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func nodeCard(_ proxy: ProxyNodeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(proxy.name)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(proxy.type == "-" ? "Unknown" : proxy.type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if proxy.isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            HStack {
                if let delayText = proxy.delayText {
                    Label(delayText, systemImage: "speedometer")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(proxy.delayColor)
                } else {
                    Label("未测速", systemImage: "speedometer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !proxy.isSelected, appModel.isCoreRunning, let group = appModel.selectedProxyGroup {
                    Button {
                        appModel.selectProxy(groupName: group.name, proxyName: proxy.name)
                    } label: {
                        Label("选择", systemImage: "arrow.right.circle")
                    }
                    .labelStyle(.iconOnly)
                    .help("选择节点")
                }
            }
        }
        .padding(12)
        .frame(minHeight: 118, alignment: .topLeading)
        .background(.quaternary.opacity(proxy.isSelected ? 0.55 : 0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(proxy.isSelected ? Color.green.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Provider")
                    .font(.headline)
                Text("\(appModel.proxyProviderRows.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.45), in: Capsule())
                Text(appModel.proxyProviderStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(appModel.proxyProviderRows) { provider in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(provider.name)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(provider.type)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(provider.urlHost)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("\(provider.intervalText) · \(provider.healthCheckText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(provider.runtimeText) · \(provider.nodeCountText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if appModel.isCoreRunning {
                                Button {
                                    appModel.refreshProxyProvider(name: provider.name)
                                } label: {
                                    Label("刷新 Provider", systemImage: "arrow.clockwise")
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .frame(width: 240, alignment: .leading)
                        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding {
            expandedProxyGroupIDs.contains(id)
        } set: { isExpanded in
            if isExpanded {
                expandedProxyGroupIDs.insert(id)
            } else {
                expandedProxyGroupIDs.remove(id)
            }
            appModel.saveExpandedProxyGroups(expandedProxyGroupIDs)
        }
    }

    private func applyPreferredExpandedGroups(groups: [ProxyGroupSnapshot]? = nil) {
        let currentGroups = groups ?? appModel.proxyGroups
        if appModel.preferredExpandedProxyGroupIDs.isEmpty {
            expandedProxyGroupIDs.formUnion(currentGroups.map(\.id))
        } else {
            expandedProxyGroupIDs = appModel.preferredExpandedProxyGroupIDs
        }
    }
}

struct ProfilesView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var isImportingProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("配置")
                    .font(.headline)
                Spacer()
                Button {
                    appModel.updateAllURLProfiles()
                } label: {
                    Label("同步全部", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(appModel.isProfileImportInProgress || appModel.isCoreRunning)
                Button {
                    isImportingProfile = true
                } label: {
                    Label("导入本地", systemImage: "square.and.arrow.down")
                }
                .disabled(appModel.isProfileImportInProgress || appModel.isCoreRunning)
                Button {
                    Task { await appModel.refreshProfiles() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("配置名称（可选）", text: $appModel.profileImportName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    TextField("https://example.com/config.yaml", text: $appModel.profileDownloadURL)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        appModel.downloadProfileFromURL()
                    } label: {
                        Label("下载并加载", systemImage: "arrow.down.doc")
                    }
                    .disabled(appModel.isProfileImportInProgress || appModel.isCoreRunning || appModel.profileDownloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text(appModel.profileImportStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appModel.profileRows.isEmpty {
                PlaceholderPanelView(title: "暂无配置", systemImage: "doc.text", detail: "可导入本地 YAML 配置，或填写订阅 URL 下载配置。")
            } else {
                List(appModel.profileRows) { profile in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(profile.name)
                                    .fontWeight(.medium)
                                if appModel.selectedProfileID == profile.id {
                                    Label("当前", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(profile.rawConfigPath)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .textSelection(.enabled)
                            Text(profile.overrideConfigPath)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .textSelection(.enabled)
                            Text(profile.generatedConfigPath)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .textSelection(.enabled)
                            Text(profile.sourceDetail)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text("更新时间：\(profile.updatedText)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            if let subscriptionText = profile.subscriptionText {
                                Text(subscriptionText)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            if let qualityText = profile.qualityText {
                                Text(qualityText)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        Spacer()
                        if profile.isURLProfile {
                            Button {
                                appModel.updateProfile(id: profile.id)
                            } label: {
                                Label("同步", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .labelStyle(.iconOnly)
                            .disabled(appModel.isProfileImportInProgress || appModel.isCoreRunning)
                        }
                        Button {
                            appModel.loadProfile(id: profile.id)
                        } label: {
                            Label("加载", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(appModel.isProfileImportInProgress || appModel.isCoreRunning || appModel.selectedProfileID == profile.id)
                        Button(role: .destructive) {
                            appModel.deleteProfile(id: profile.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(appModel.isProfileImportInProgress || appModel.isCoreRunning)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
        .fileImporter(
            isPresented: $isImportingProfile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    appModel.importProfileFile(url: url)
                }
            case let .failure(error):
                appModel.reportError(error)
            }
        }
        .task {
            await appModel.refreshProfiles()
        }
    }
}

struct ConnectionsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("活跃连接")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    appModel.closeAllConnections()
                } label: {
                    Label("关闭全部", systemImage: "xmark.circle")
                }
                Button {
                    Task { await appModel.refreshConnections() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            if appModel.connectionRows.isEmpty {
                PlaceholderPanelView(title: "暂无连接", systemImage: "link", detail: "连接数据只在本页面可见时刷新，避免隐藏页面持续占用 CPU。")
            } else {
                List(appModel.connectionRows) { connection in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.rule)
                                .fontWeight(.medium)
                            Text(connection.chains.isEmpty ? "-" : connection.chains)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("↑ \(connection.upload)")
                            .monospacedDigit()
                        Text("↓ \(connection.download)")
                            .monospacedDigit()
                        Button(role: .destructive) {
                            appModel.closeConnection(id: connection.id)
                        } label: {
                            Label("关闭", systemImage: "xmark")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(24)
        .task {
            await appModel.refreshConnections()
        }
    }
}

struct LogsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Core 日志")
                    .font(.headline)
                Spacer()
                Button {
                    appModel.refreshRecentLogs()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            ScrollView {
                Text(appModel.recentLogs.isEmpty ? "暂无日志。" : appModel.recentLogs)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(24)
        .task {
            appModel.refreshRecentLogs()
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button {
                    appModel.isCoreRunning ? appModel.stopProxy() : appModel.startProxy()
                } label: {
                    Label(appModel.isCoreRunning ? "停止代理" : "启动代理", systemImage: appModel.isCoreRunning ? "stop.fill" : "play.fill")
                }
                .controlSize(.large)

                Button {
                    appModel.toggleSystemProxy()
                } label: {
                    Label(appModel.isSystemProxyEnabled ? "关闭系统代理" : "开启系统代理", systemImage: "network")
                }
                .controlSize(.large)

                Button {
                    appModel.refreshOnce()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                MetricTile(title: "状态", value: appModel.statusText, systemImage: "bolt.horizontal.circle")
                MetricTile(title: "流量", value: appModel.trafficText, systemImage: "arrow.up.arrow.down")
                MetricTile(title: "连接", value: "\(appModel.activeConnections)", systemImage: "link")
                MetricTile(title: "Core", value: appModel.coreVersion, systemImage: "cpu")
                MetricTile(title: "CPU", value: appModel.cpuUsageText, systemImage: "speedometer")
                MetricTile(title: "内存", value: appModel.memoryUsageText, systemImage: "memorychip")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("运行详情")
                    .font(.headline)
                Text(appModel.statusDetail)
                    .foregroundStyle(.secondary)
                if let lastError = appModel.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(24)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        Form {
            Picker("代理模式", selection: $appModel.selectedMode) {
                Text("Rule").tag("rule")
                Text("Global").tag("global")
                Text("Direct").tag("direct")
            }
            .pickerStyle(.segmented)

            LabeledContent("绕过代理") {
                VStack(alignment: .trailing, spacing: 8) {
                    TextEditor(text: $appModel.proxyBypassText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Text("\(appModel.proxyBypassEntries.count) 条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            appModel.resetProxyBypassEntries()
                        } label: {
                            Label("恢复默认", systemImage: "arrow.counterclockwise")
                        }
                    }
                    Text("每行一个域名、IP 或 CIDR。默认包含 localhost、local、私有网段和链路本地地址。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            LabeledContent("Application Support") {
                Text(appModel.applicationSupportPath)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("运行配置") {
                Text(appModel.runtimeConfigPath)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("规则资源") {
                VStack(alignment: .trailing, spacing: 10) {
                    HStack {
                        Text(appModel.geoResourceStatus)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await appModel.refreshGeoResources() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    ForEach(appModel.geoResourceRows, id: \.id) { row in
                        GeoResourceRowView(row: row)
                    }
                }
            }

            LabeledContent("mihomo core") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(appModel.coreInstallStatus)
                        .foregroundStyle(.secondary)
                    Text(appModel.corePath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            LabeledContent("core SHA256") {
                Text(appModel.coreSHA256)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            LabeledContent("下载 core") {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack {
                        TextField("版本", text: $appModel.coreDownloadVersion)
                            .frame(width: 110)
                            .onChange(of: appModel.coreDownloadVersion) { _ in
                                appModel.refreshCoreDownloadPreview()
                            }
                        Button {
                            appModel.installCoreFromDownloadVersion()
                        } label: {
                            Label("下载并安装", systemImage: "arrow.down.circle")
                        }
                        .disabled(appModel.isCoreUpdateInProgress || appModel.isCoreRunning)
                        Button {
                            Task { await appModel.refreshCoreInfo() }
                            appModel.refreshCoreDownloadPreview()
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    TextField("可选 SHA256 校验值", text: $appModel.coreExpectedSHA256)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                    Text(appModel.coreDownloadURLText)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                    Text(appModel.coreUpdateStatus)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            LabeledContent("UI 刷新策略") {
                Text("可见 1Hz，空闲 0.2Hz")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("CPU") {
                Text(appModel.cpuUsageText)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("内存峰值") {
                Text(appModel.memoryUsageText)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("开机启动") {
                HStack {
                    Text(appModel.loginItemStatusText)
                        .foregroundStyle(.secondary)
                    Button {
                        appModel.toggleLoginItem()
                    } label: {
                        Label("切换", systemImage: "power")
                    }
                }
            }

            LabeledContent("通知权限") {
                HStack {
                    Text(appModel.notificationStatusText)
                        .foregroundStyle(.secondary)
                    Button {
                        appModel.requestNotificationAuthorization()
                    } label: {
                        Label("请求权限", systemImage: "bell")
                    }
                }
            }

            Button {
                appModel.exportDiagnostics()
            } label: {
                Label("导出诊断包", systemImage: "archivebox")
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .task {
            appModel.refreshLoginItemStatus()
            await appModel.refreshNotificationStatus()
            await appModel.refreshGeoResources()
        }
    }
}

struct GeoResourceRowView: View {
    @EnvironmentObject private var appModel: AppViewModel
    let row: GeoResourceSnapshot

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .fontWeight(.semibold)
                    Text(row.statusText)
                        .font(.caption)
                        .foregroundStyle(row.exists ? Color.secondary : Color.red)
                }
                Spacer()
                if row.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    appModel.resetGeoResourceURL(for: row.id)
                } label: {
                    Label("默认", systemImage: "arrow.counterclockwise")
                }
                .disabled(row.isSyncing)
                Button {
                    appModel.syncGeoResource(id: row.id)
                } label: {
                    Label("同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(row.isSyncing)
            }
            TextField(
                "\(row.label) URL",
                text: Binding(
                    get: { appModel.geoResourceURLText(for: row.id) },
                    set: { appModel.setGeoResourceURLText($0, for: row.id) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            Text(row.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PlaceholderPanelView: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}
