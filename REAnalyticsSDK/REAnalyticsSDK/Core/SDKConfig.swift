
import Foundation

@objc public class SDKConfig: NSObject {
    
    // Core Configuration
    @objc public var locationTrackingEnabled: Bool = false
    @objc public var screenTrackingEnabled: Bool = true
    @objc public var crashTrackingEnabled: Bool = false
    @objc public var sessionTimeout: TimeInterval = 1800 // 30 minutes
    
    // Privacy Configuration
    @objc public var requiresUserConsent: Bool = true
    @objc public var anonymizeData: Bool = false
    
    // Network Configuration
    @objc public var baseURL: String = "https://api.analytics-sdk.com"
    @objc public var maxRetries: Int = 3
    @objc public var requestTimeout: TimeInterval = 30
    
    // Location Configuration
    @objc public var locationAccuracy: LocationAccuracy = .hundredMeters
    @objc public var locationDistanceFilter: Double = 100
    
    // Notification Configuration
    @objc public var pushNotificationsEnabled: Bool = false
    @objc public var inAppNotificationsEnabled: Bool = true
    
    // Rule Engine Configuration
    @objc public var localRulesEnabled: Bool = true
    @objc public var rulesSyncInterval: TimeInterval = 3600 // 1 hour
    
    // Sensor Configuration
    @objc public var sensorDataEnabled: Bool = false
    @objc public var sensorSamplingRate: Double = 50.0 // Hz
    
    @objc public static let `default` = SDKConfig()
    
    private override init() {
        super.init()
    }
}

@objc public enum LocationAccuracy: Int {
    case best = 0
    case nearestTenMeters = 1
    case hundredMeters = 2
    case kilometer = 3
}

//Test
