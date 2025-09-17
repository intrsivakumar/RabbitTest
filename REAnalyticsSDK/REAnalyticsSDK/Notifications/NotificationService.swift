
import Foundation
import UserNotifications

@objc public class NotificationPayload: NSObject, Codable {
    @objc public var title: String = ""
    @objc public var body: String = ""
    @objc public var subtitle: String?
    @objc public var badge: NSNumber?
    @objc public var sound: String?
    @objc public var category: String?
    @objc public var threadId: String?
    @objc public var campaignId: String?
    @objc public var customData: [String: Any]?
    @objc public var mediaAttachments: [MediaAttachment] = []
    @objc public var actions: [NotificationAction] = []
    
    private enum CodingKeys: String, CodingKey {
        case title, body, subtitle, badge, sound, category
        case threadId, campaignId, customData, mediaAttachments, actions
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        badge = try container.decodeIfPresent(NSNumber.self, forKey: .badge)
        sound = try container.decodeIfPresent(String.self, forKey: .sound)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
        campaignId = try container.decodeIfPresent(String.self, forKey: .campaignId)
        customData = try container.decodeIfPresent([String: Any].self, forKey: .customData)
        mediaAttachments = try container.decode([MediaAttachment].self, forKey: .mediaAttachments)
        actions = try container.decode([NotificationAction].self, forKey: .actions)
        super.init()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(badge, forKey: .badge)
        try container.encodeIfPresent(sound, forKey: .sound)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(threadId, forKey: .threadId)
        try container.encodeIfPresent(campaignId, forKey: .campaignId)
        try container.encodeIfPresent(customData, forKey: .customData)
        try container.encode(mediaAttachments, forKey: .mediaAttachments)
        try container.encode(actions, forKey: .actions)
    }
}

@objc public class MediaAttachment: NSObject, Codable {
    @objc public var url: String
    @objc public var type: String // image, video, audio
    @objc public var identifier: String
    
    public init(url: String, type: String, identifier: String) {
        self.url = url
        self.type = type
        self.identifier = identifier
        super.init()
    }
}

@objc public class NotificationAction: NSObject, Codable {
    @objc public var identifier: String
    @objc public var title: String
    @objc public var options: UInt
    @objc public var textInputButtonTitle: String?
    @objc public var textInputPlaceholder: String?
    
    public init(identifier: String, title: String, options: UInt = 0) {
        self.identifier = identifier
        self.title = title
        self.options = options
        super.init()
    }
}

class NotificationService: NSObject {
    
    private let eventTracker: ManualEventTracker
    private let userTrackingManager: UserTrackingManager
    private let storageHelper: StorageHelper
    
    init(eventTracker: ManualEventTracker = ManualEventTracker(),
         userTrackingManager: UserTrackingManager = UserTrackingManager(),
         storageHelper: StorageHelper = StorageHelper()) {
        self.eventTracker = eventTracker
        self.userTrackingManager = userTrackingManager
        self.storageHelper = storageHelper
        super.init()
        
        setupNotificationCategories()
    }
    
    // MARK: - Public Methods
    
    func requestPermission(completion: @escaping (Bool, Error?) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                completion(granted, error)
            }
            
            // Track permission response
            var permissionData: [String: Any] = [
                "permission_granted": granted,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            
            if let error = error {
                permissionData["error"] = error.localizedDescription
            }
            
            self.eventTracker.trackEvent(name: "push_permission_response", data: permissionData)
        }
    }
    
    func getAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }
    
    func processNotificationPayload(_ payload: NotificationPayload) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        
        // Basic content
        content.title = personalizeText(payload.title)
        content.body = personalizeText(payload.body)
        
        if let subtitle = payload.subtitle {
            content.subtitle = personalizeText(subtitle)
        }
        
        if let badge = payload.badge {
            content.badge = badge
        }
        
        if let sound = payload.sound {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
        } else {
            content.sound = .default
        }
        
        if let category = payload.category {
            content.categoryIdentifier = category
        }
        
        if let threadId = payload.threadId {
            content.threadIdentifier = threadId
        }
        
        // Custom data
        var userInfo: [AnyHashable: Any] = [:]
        if let customData = payload.customData {
            userInfo.merge(customData) { _, new in new }
        }
        
        if let campaignId = payload.campaignId {
            userInfo["campaign_id"] = campaignId
        }
        
        content.userInfo = userInfo
        
        return content
    }
    
    func handleNotificationReceived(_ payload: NotificationPayload) {
        let notificationData: [String: Any] = [
            "campaign_id": payload.campaignId ?? "",
            "notification_title": payload.title,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.notificationReceived, data: notificationData)
        Logger.info("Notification received: \(payload.campaignId ?? "unknown")")
    }
    
    func handleNotificationTapped(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        var notificationData: [String: Any] = [
            "campaign_id": userInfo["campaign_id"] as? String ?? "",
            "action_identifier": response.actionIdentifier,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        // Add text input if available
        if let textResponse = response as? UNTextInputNotificationResponse {
            notificationData["user_text"] = textResponse.userText
        }
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.notificationTapped, data: notificationData)
        Logger.info("Notification tapped: \(userInfo["campaign_id"] as? String ?? "unknown")")
    }
    
    func handleNotificationDismissed(_ notification: UNNotification) {
        let userInfo = notification.request.content.userInfo
        
        let notificationData: [String: Any] = [
            "campaign_id": userInfo["campaign_id"] as? String ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.notificationDismissed, data: notificationData)
        Logger.info("Notification dismissed: \(userInfo["campaign_id"] as? String ?? "unknown")")
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationCategories() {
        let categories = createNotificationCategories()
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }
    
    private func createNotificationCategories() -> Set<UNNotificationCategory> {
        var categories = Set<UNNotificationCategory>()
        
        // Default category with basic actions
        let defaultActions = [
            UNNotificationAction(identifier: "view", title: "View", options: [.foreground]),
            UNNotificationAction(identifier: "dismiss", title: "Dismiss", options: [])
        ]
        
        let defaultCategory = UNNotificationCategory(
            identifier: "default",
            actions: defaultActions,
            intentIdentifiers: [],
            options: []
        )
        categories.insert(defaultCategory)
        
        // Interactive category with text input
        let replyAction = UNTextInputNotificationAction(
            identifier: "reply",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type your message..."
        )
        
        let interactiveCategory = UNNotificationCategory(
            identifier: "interactive",
            actions: [replyAction, defaultActions[1]],
            intentIdentifiers: [],
            options: []
        )
        categories.insert(interactiveCategory)
        
        return categories
    }
    
    private func personalizeText(_ text: String) -> String {
        guard let userProfile = userTrackingManager.getUserDetails() else {
            return text
        }
        
        var personalizedText = text
        
        // Replace placeholders with user data
        let replacements: [String: String] = [
            "{{user.first_name}}": extractFirstName(from: userProfile.name),
            "{{user.name}}": userProfile.name ?? "",
            "{{user.email}}": userProfile.email ?? "",
            "{{user.country}}": userProfile.country ?? "",
            "{{user.city}}": userProfile.city ?? ""
        ]
        
        for (placeholder, value) in replacements {
            personalizedText = personalizedText.replacingOccurrences(of: placeholder, with: value)
        }
        
        return personalizedText
    }
    
    private func extractFirstName(from fullName: String?) -> String {
        guard let fullName = fullName else { return "" }
        return fullName.components(separatedBy: " ").first ?? fullName
    }
}
