import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MyClash")
                    .font(.headline)
                Text(appModel.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(appModel.isCoreRunning ? "停止代理" : "启动代理") {
                appModel.isCoreRunning ? appModel.stopProxy() : appModel.startProxy()
            }

            Button(appModel.isSystemProxyEnabled ? "关闭系统代理" : "开启系统代理") {
                appModel.toggleSystemProxy()
            }

            Picker("模式", selection: $appModel.selectedMode) {
                Text("Rule").tag("rule")
                Text("Global").tag("global")
                Text("Direct").tag("direct")
            }
            .pickerStyle(.inline)

            Divider()

            Button("打开主窗口") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Button("刷新状态") {
                appModel.refreshOnce()
            }

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 240)
        .task {
            await appModel.bootstrap()
        }
    }
}
