import Foundation
import ServiceManagement
@preconcurrency import UserNotifications

enum LoginItemStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var title: String {
        switch self {
        case .enabled:
            return "已开启"
        case .disabled:
            return "未开启"
        case .requiresApproval:
            return "需要在系统设置中批准"
        case .unavailable:
            return "当前运行形态不可用"
        }
    }
}

struct LoginItemService: Sendable {
    func status() -> LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .disabled
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws -> LoginItemStatus {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return status()
    }
}

final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

actor UserNotificationService {
    private var lastErrorNotificationDate: Date?
    private let minimumErrorNotificationInterval: TimeInterval = 30

    nonisolated static func configureCenter(delegate: NotificationCenterDelegate) {
        UNUserNotificationCenter.current().delegate = delegate
        let category = UNNotificationCategory(
            identifier: "MYCLASH_STATUS",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func notify(title: String, body: String) async {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.categoryIdentifier = "MYCLASH_STATUS"

        let request = UNNotificationRequest(
            identifier: "myclash-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func notifyError(title: String, body: String) async {
        let now = Date()
        if let lastErrorNotificationDate, now.timeIntervalSince(lastErrorNotificationDate) < minimumErrorNotificationInterval {
            return
        }
        lastErrorNotificationDate = now
        await notify(title: title, body: body)
    }
}
