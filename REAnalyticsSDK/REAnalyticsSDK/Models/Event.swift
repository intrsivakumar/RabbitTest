
import Foundation

@objc public class Event: NSObject, Codable {
    @objc public let eventId: String
    @objc public let name: String
    @objc public let timestamp: Date
    @objc public let sessionId: String?
    @objc public let userId: String?
    @objc public var properties: [String: Any]
    @objc public var deviceInfo: [String: Any]?
    @objc public var locationInfo: [String: Any]?
    
    @objc public init(name: String, properties: [String: Any] = [:]) {
        self.eventId = UUID().uuidString
        self.name = name
        self.timestamp = Date()
        self.sessionId = SessionManager.shared.getCurrentSessionId()
        self.userId = StorageHelper.getUserId()
        self.properties = properties
        super.init()
        
        // Auto-attach device info
        self.deviceInfo = DeviceInfoCollector.getCurrentDeviceInfo()
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case eventId, name, timestamp, sessionId, userId
        case properties, deviceInfo, locationInfo
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try container.decode(String.self, forKey: .eventId)
        name = try container.decode(String.self, forKey: .name)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        properties = try container.decode([String: Any].self, forKey: .properties)
        deviceInfo = try container.decodeIfPresent([String: Any].self, forKey: .deviceInfo)
        locationInfo = try container.decodeIfPresent([String: Any].self, forKey: .locationInfo)
        super.init()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventId, forKey: .eventId)
        try container.encode(name, forKey: .name)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(properties, forKey: .properties)
        try container.encodeIfPresent(deviceInfo, forKey: .deviceInfo)
        try container.encodeIfPresent(locationInfo, forKey: .locationInfo)
    }
}

// MARK: - Event Types

@objc public enum AutoEventType: Int {
    case appInstall = 0
    case appLaunch = 1
    case sessionStart = 2
    case sessionEnd = 3
    case screenView = 4
    case appForeground = 5
    case appBackground = 6
    case appCrash = 7
    
    public var eventName: String {
        switch self {
        case .appInstall: return "app_install"
        case .appLaunch: return "app_launch"
        case .sessionStart: return "session_start"
        case .sessionEnd: return "session_end"
        case .screenView: return "screen_view"
        case .appForeground: return "app_foreground"
        case .appBackground: return "app_background"
        case .appCrash: return "app_crash"
        }
    }
}

