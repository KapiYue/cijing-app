import UIKit
import UserNotifications

enum DailyReminderScheduleResult {
    case scheduled
    case permissionDenied
    case permissionNotRequested
    case failed(String)
}

enum DailyReminderScheduler {
    static let notificationIdentifier = "cijing.daily-learning-reminder"

    static func setEnabled(_ enabled: Bool, requestAuthorization: Bool) async -> DailyReminderScheduleResult {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        guard enabled else { return .scheduled }

        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, requestAuthorization {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                settings = await center.notificationSettings()
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            let content = UNMutableNotificationContent()
            content.title = "今天的词，等你再遇见"
            content.body = "花几分钟复习一下，让记忆继续生长。"
            content.sound = .default

            var components = DateComponents()
            components.hour = 20
            components.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
                return .scheduled
            } catch {
                return .failed(error.localizedDescription)
            }
        case .denied:
            return .permissionDenied
        case .notDetermined:
            return .permissionNotRequested
        @unknown default:
            return .failed("系统返回了未知的通知权限状态。")
        }
    }
}

enum LearningHaptic {
    case answerCorrect
    case answerIncorrect
    case step
    case completion
}

@MainActor
enum LearningHapticFeedback {
    static func play(_ event: LearningHaptic) {
        switch event {
        case .answerCorrect:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        case .answerIncorrect:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        case .step:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        case .completion:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }
}
