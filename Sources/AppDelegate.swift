import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusController: StatusMenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 只挂菜单栏，不占 Dock
        NSApp.setActivationPolicy(.accessory)

        Store.shared.load()
        statusController = StatusMenuController()

        // 启动时主动请求通知权限（首次弹授权框，后续静默检查）
        Self.requestNotificationPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.save()
    }

    /// 请求/检查通知权限：authorized 直接用；notDetermined 弹授权框；denied 提示去系统设置
    static func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    break
                case .notDetermined:
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                case .denied:
                    // 静默记录状态，设置窗口会展示并引导去系统设置
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    /// 当前通知权限状态（供设置窗口展示）
    static func notificationStatus(completion: @escaping (String, Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .ephemeral:
                    completion("已授权 ✓", true)
                case .provisional:
                    completion("已授权（临时）✓", true)
                case .denied:
                    completion("未授权（系统设置中已关闭）", false)
                case .notDetermined:
                    completion("未请求过", false)
                @unknown default:
                    completion("未知", false)
                }
            }
        }
    }
}
