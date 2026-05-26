import AppKit
import CoreServices
import SwiftUI

@main
struct MyClashDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra("MyClash", systemImage: appModel.menuSystemImage) {
            MenuBarContentView()
                .environmentObject(appModel)
                .onAppear {
                    appDelegate.appModel = appModel
                }
        }

        Window("MyClash", id: "main") {
            MainWindowView()
                .environmentObject(appModel)
                .frame(minWidth: 920, minHeight: 620)
                .onAppear {
                    appDelegate.appModel = appModel
                }
                .task {
                    await appModel.bootstrap()
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MyClash") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appModel: AppViewModel?
    private var isTerminating = false
    private let notificationCenterDelegate = NotificationCenterDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerBundleWithLaunchServices()
        if let iconURL = Bundle.main.url(forResource: "MyClash", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        UserNotificationService.configureCenter(delegate: notificationCenterDelegate)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else {
            return .terminateNow
        }

        isTerminating = true
        Task { @MainActor [weak self, weak sender] in
            await self?.appModel?.shutdownForTermination()
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func registerBundleWithLaunchServices() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return
        }
        _ = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
    }
}
