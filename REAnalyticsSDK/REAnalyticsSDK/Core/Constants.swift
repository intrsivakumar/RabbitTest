
import Foundation
import UIKit
import CoreLocation
import CommonCrypto
import CryptoKit

struct Constants {
    
    // MARK: - SDK Information
    static let sdkVersion = "1.7.0"
    static let sdkName = "AnalyticsSDK"
    
    // MARK: - Storage Keys
    struct Storage {
        static let appId = "analytics_sdk_app_id"
        static let deviceId = "analytics_sdk_device_id"
        static let userId = "analytics_sdk_user_id"
        static let authToken = "analytics_sdk_auth_token"
        static let sessionId = "analytics_sdk_session_id"
        static let userProfile = "analytics_sdk_user_profile"
        static let pushTokenAPNS = "analytics_sdk_push_token_apns"
        static let pushTokenFCM = "analytics_sdk_push_token_fcm"
        static let locationPermissionRequested = "analytics_sdk_location_permission_requested"
        static let consentStatus = "analytics_sdk_consent_status"
        static let resumeData = "analytics_sdk_resume_data"
        static let geofenceData = "analytics_sdk_geofence_data"
        static let ruleEngineData = "analytics_sdk_rule_engine_data"
        static let utmData = "analytics_sdk_utm_data"
    }
    
    // MARK: - Network
    struct Network {
        static let defaultBaseURL = "https://api.analytics-sdk.com"
        static let defaultTimeout: TimeInterval = 30
        static let maxRetries = 3
        static let batchSize = 50
        static let compressionThreshold = 1024 // bytes
        
        struct Headers {
            static let contentType = "Content-Type"
            static let authorization = "Authorization"
            static let appId = "X-App-ID"
            static let deviceId = "X-Device-ID"
            static let signature = "X-Signature"
            static let sdkVersion = "X-SDK-Version"
            static let platform = "X-Platform"
        }
        
        struct Endpoints {
            static let events = "events"
            static let users = "users"
            static let sessions = "sessions"
            static let geofences = "geofences"
            static let rules = "rules"
            static let tokens = "tokens"
            static let notifications = "notifications"
        }
    }
    
    // MARK: - Session
    struct Session {
        static let defaultTimeout: TimeInterval = 1800 // 30 minutes
        static let minDuration: TimeInterval = 1 // 1 second
        static let maxDuration: TimeInterval = 86400 // 24 hours
    }
    
    // MARK: - Location
    struct Location {
        static let defaultDistanceFilter: CLLocationDistance = 100 // meters
        static let minGeofenceRadius: CLLocationDistance = 100 // meters
        static let maxGeofenceRadius: CLLocationDistance = 100000 // 100 km
        static let maxMonitoredRegions = 20
        static let locationCacheTimeout: TimeInterval = 300 // 5 minutes
    }
    
    // MARK: - Events
    struct Events {
        static let maxEventNameLength = 100
        static let maxPropertyKeyLength = 50
        static let maxPropertyValueLength = 500
        static let maxPropertiesCount = 50
        static let eventBatchTimeout: TimeInterval = 60 // 1 minute
        
        // Auto Event Names
        struct AutoEvents {
            static let appInstall = "app_install"
            static let appLaunch = "app_launch"
            static let sessionStart = "session_start"
            static let sessionEnd = "session_end"
            static let screenView = "screen_view"
            static let appForeground = "app_foreground"
            static let appBackground = "app_background"
            static let appCrash = "app_crash"
            static let geofenceEntered = "geofence_entered"
            static let geofenceExited = "geofence_exited"
            static let notificationReceived = "notification_received"
            static let notificationTapped = "notification_tapped"
            static let notificationDismissed = "notification_dismissed"
        }
    }
    
    // MARK: - Notifications
    struct Notifications {
        static let maxTitleLength = 100
        static let maxBodyLength = 500
        static let maxActionTitleLength = 50
        static let maxActionsCount = 4
        static let defaultBadge = 0
        static let templateTimeout: TimeInterval = 10
    }
    
    // MARK: - Sensors
    struct Sensors {
        static let defaultSamplingRate: Double = 50.0 // Hz
        static let minSamplingRate: Double = 1.0
        static let maxSamplingRate: Double = 100.0
        static let dataRetentionTimeout: TimeInterval = 3600 // 1 hour
    }
    
    // MARK: - Security
    struct Security {
        static let encryptionKeySize = kCCKeySizeAES256
        static let hmacKeySize = "kCCKeySizeSHA256"
        static let ivSize = kCCBlockSizeAES128
        static let saltSize = 32
    }
    
    // MARK: - Bounce Tracking
    struct Bounce {
        static let defaultTimeout: TimeInterval = 30 // seconds
        static let minInteractionCount = 1
    }
    
    // MARK: - Device Info
    struct DeviceInfo {
        static let refreshInterval: TimeInterval = 3600 // 1 hour
        static let batteryLevelThreshold: Float = 0.05 // 5% change threshold
    }
    
    // MARK: - Resume Journey
    struct ResumeJourney {
        static let dataRetentionTimeout: TimeInterval = 86400 // 24 hours
        static let maxNavigationStackSize = 50
        static let maxFormDataSize = 10240 // 10KB
    }
}

// MARK: - Enumerations

@objc public enum AnalyticsLogLevel: Int {
    case none = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4
    case verbose = 5
}

@objc public enum ConsentStatus: Int {
    case notDetermined = 0
    case granted = 1
    case denied = 2
    case restricted = 3
    case unknown = 4
    case notRequired = 5

}

@objc public enum NetworkReachability: Int {
    case notReachable = 0
    case wifi = 1
    case cellular = 2
}

@objc public enum PushProvider: Int {
    case apns = 0
    case fcm = 1
}

@objc public enum SensorType: Int {
    case accelerometer = 0
    case gyroscope = 1
    case magnetometer = 2
    case barometer = 3
    case proximity = 4
}

@objc public enum DisplayStyle: Int {
    case banner = 0
    case modal = 1
    case carousel = 2
    case fullScreen = 3
    case custom = 4
}

extension Constants {
    struct API {
        static let baseURL = "https://your-analytics-api.com/api/v1"
        // Add other API endpoints as needed
    }
}

extension Notification.Name {
    static let userDeletionFailed = Notification.Name("UserDeletionFailedNotification")
    static let userDeletionSucceeded = Notification.Name("UserDeletionSucceededNotification")
}
