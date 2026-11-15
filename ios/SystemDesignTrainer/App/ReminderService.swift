import Foundation
import Observation
import TrainerCore
import UserNotifications

/// Schedules the daily study reminder as a local notification. Local notifications are
/// delivered by iOS itself, so they arrive while the app is closed and without a network.
@MainActor
@Observable
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    enum Permission: String {
        case notAsked = "Not asked yet"
        case allowed = "Allowed"
        case denied = "Turned off in iOS Settings"
        case provisional = "Delivered quietly"
    }

    private(set) var permission: Permission = .notAsked
    /// Next fire time of the pending daily reminder, as reported by the system.
    private(set) var nextFire: Date?
    private var center: UNUserNotificationCenter { .current() }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral: permission = .allowed
        case .provisional: permission = .provisional
        case .denied: permission = .denied
        default: permission = .notAsked
        }
        let pending = await center.pendingNotificationRequests()
        nextFire = pending.first { $0.identifier == ReminderPlan.identifier }
            .flatMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
    }

    /// Asks iOS for permission (shows the system prompt the first time). Returns whether it was granted.
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        return granted
    }

    /// Makes the pending notifications match the plan: nil removes the reminder. The request
    /// uses one fixed identifier, so calling this any number of times leaves exactly one.
    func apply(_ plan: ReminderPlan?) async {
        center.removePendingNotificationRequests(withIdentifiers: [ReminderPlan.identifier])
        guard let plan else { await refreshStatus(); return }
        await refreshStatus()
        guard permission == .allowed || permission == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        // Hour and minute only: fires at that wall-clock time every day in the phone's current time zone.
        var when = DateComponents()
        when.hour = plan.hour
        when.minute = plan.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: ReminderPlan.identifier, content: content, trigger: trigger))
        await refreshStatus()
    }

    /// Fires a real notification a few seconds from now so delivery can be checked with the app in the background.
    func sendTest(after seconds: TimeInterval = 5) async -> Bool {
        if permission == .notAsked { await requestPermission() }
        guard permission == .allowed || permission == .provisional else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Test reminder"
        content.body = "Reminders are working. Your daily reminder will look like this."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: ReminderPlan.testIdentifier, content: content, trigger: trigger))
            return true
        } catch { return false }
    }

    // Show the banner even if the app happens to be open when the reminder fires.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
