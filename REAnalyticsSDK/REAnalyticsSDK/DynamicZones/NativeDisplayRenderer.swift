import Foundation

// MARK: - Display Style Enum
@objc public enum DisplayStyle: String, Codable, CaseIterable {
    case banner = "banner"
    case modal = "modal"
    case carousel = "carousel"
    case custom = "custom"
}

// MARK: - Condition Struct
public struct Condition: Codable, Equatable {
    public let key: String
    public let operator: String
    public let value: String
    public let type: ConditionType?
    
    public init(key: String, operator: String, value: String, type: ConditionType? = nil) {
        self.key = key
        self.operator = `operator`
        self.value = value
        self.type = type
    }
    
    private enum CodingKeys: String, CodingKey {
        case key
        case `operator` = "operator"
        case value
        case type
    }
}

// MARK: - Condition Type Enum
public enum ConditionType: String, Codable, CaseIterable {
    case userAttribute = "user_attribute"
    case eventProperty = "event_property"
    case sessionActivity = "session_activity"
    case temporal = "temporal"
    case location = "location"
    case appState = "app_state"
}

// MARK: - Dynamic Zone Config
public struct DynamicZoneConfig: Codable, Equatable {
    public let zoneId: String
    public let priority: Int
    public let conditions: [Condition]
    public let displayStyle: DisplayStyle
    public let enabled: Bool
    public let expiresAt: Date?
    public let metadata: [String: String]?
    
    public init(
        zoneId: String,
        priority: Int,
        conditions: [Condition],
        displayStyle: DisplayStyle,
        enabled: Bool = true,
        expiresAt: Date? = nil,
        metadata: [String: String]? = nil
    ) {
        self.zoneId = zoneId
        self.priority = priority
        self.conditions = conditions
        self.displayStyle = displayStyle
        self.enabled = enabled
        self.expiresAt = expiresAt
        self.metadata = metadata
    }
    
    private enum CodingKeys: String, CodingKey {
        case zoneId = "zone_id"
        case priority
        case conditions
        case displayStyle = "display_style"
        case enabled
        case expiresAt = "expires_at"
        case metadata
    }
}

// MARK: - Display Content
public struct DisplayContent: Codable, Equatable {
    public let contentId: String
    public let title: String?
    public let message: String?
    public let imageUrl: String?
    public let actionUrl: String?
    public let buttons: [ActionButton]?
    public let customData: [String: String]?
    
    public init(
        contentId: String,
        title: String? = nil,
        message: String? = nil,
        imageUrl: String? = nil,
        actionUrl: String? = nil,
        buttons: [ActionButton]? = nil,
        customData: [String: String]? = nil
    ) {
        self.contentId = contentId
        self.title = title
        self.message = message
        self.imageUrl = imageUrl
        self.actionUrl = actionUrl
        self.buttons = buttons
        self.customData = customData
    }
    
    private enum CodingKeys: String, CodingKey {
        case contentId = "content_id"
        case title
        case message
        case imageUrl = "image_url"
        case actionUrl = "action_url"
        case buttons
        case customData = "custom_data"
    }
}

// MARK: - Action Button
public struct ActionButton: Codable, Equatable {
    public let id: String
    public let title: String
    public let actionType: ActionType
    public let actionUrl: String?
    public let style: ButtonStyle?
    
    public init(
        id: String,
        title: String,
        actionType: ActionType,
        actionUrl: String? = nil,
        style: ButtonStyle? = nil
    ) {
        self.id = id
        self.title = title
        self.actionType = actionType
        self.actionUrl = actionUrl
        self.style = style
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case actionType = "action_type"
        case actionUrl = "action_url"
        case style
    }
}

// MARK: - Action Type Enum
public enum ActionType: String, Codable, CaseIterable {
    case dismiss = "dismiss"
    case openUrl = "open_url"
    case deepLink = "deep_link"
    case custom = "custom"
}

// MARK: - Button Style Enum
public enum ButtonStyle: String, Codable, CaseIterable {
    case primary = "primary"
    case secondary = "secondary"
    case tertiary = "tertiary"
}
