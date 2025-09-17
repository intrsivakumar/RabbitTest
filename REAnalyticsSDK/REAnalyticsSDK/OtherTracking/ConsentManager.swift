import Foundation
import UIKit
import AppTrackingTransparency



@objc public enum ConsentType: Int, CaseIterable, Codable {
    case analytics = 0
    case advertising = 1
    case functional = 2
    case performance = 3
    case gdpr = 4
    case ccpa = 5
    case appTrackingTransparency = 6
}


@objc public protocol ConsentManagerDelegate: AnyObject {
    @objc optional func consentManager(_ manager: ConsentManager, didUpdateConsent type: ConsentType, status: ConsentStatus)
    @objc optional func consentManagerDidRequestPermission(_ manager: ConsentManager, type: ConsentType)
    @objc optional func consentManager(_ manager: ConsentManager, didFailWithError error: Error)
}

@objc public class ConsentManager: NSObject {
    
    @objc public static let shared = ConsentManager()
    
    @objc public weak var delegate: ConsentManagerDelegate?
    
    private let storageHelper: StorageHelper
    private let eventTracker: ManualEventTracker
    
    private var consentStatuses: [ConsentType: ConsentStatus] = [:]
    private var consentTimestamps: [ConsentType: Date] = [:]
    private var consentExpirationInterval: TimeInterval = 31536000 // 1 year
    
    private override init() {
        self.storageHelper = StorageHelper()
        self.eventTracker = ManualEventTracker()
        super.init()
        
        loadStoredConsents()
        setupNotificationObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    @objc public func requestConsent(for type: ConsentType, completion: @escaping (ConsentStatus, Error?) -> Void) {
        delegate?.consentManagerDidRequestPermission?(self, type: type)
        
        switch type {
        case .appTrackingTransparency:
            requestAppTrackingTransparencyConsent(completion: completion)
        case .analytics, .advertising, .functional, .performance:
            // These require custom UI implementation by the host app
            completion(.unknown, AnalyticsError.consentRequired)
        case .gdpr:
            requestGDPRConsent(completion: completion)
        case .ccpa:
            requestCCPAConsent(completion: completion)
        }
    }
    
    @objc public func setConsent(_ status: ConsentStatus, for type: ConsentType) {
        let previousStatus = consentStatuses[type] ?? .unknown
        
        consentStatuses[type] = status
        consentTimestamps[type] = Date()
        
        saveConsent(type: type, status: status)
        trackConsentChange(type: type, status: status, previousStatus: previousStatus)
        
        delegate?.consentManager?(self, didUpdateConsent: type, status: status)
        
        // Post notification for SDK components
        NotificationCenter.default.post(
            name: .consentStatusChanged,
            object: self,
            userInfo: [
                "type": type.rawValue,
                "status": status.rawValue,
                "previousStatus": previousStatus.rawValue
            ]
        )
    }
    
    @objc public func getConsentStatus(for type: ConsentType) -> ConsentStatus {
        // Check if consent has expired
        if let timestamp = consentTimestamps[type],
           Date().timeIntervalSince(timestamp) > consentExpirationInterval {
            setConsent(.unknown, for: type)
            return .unknown
        }
        
        return consentStatuses[type] ?? .unknown
    }
    
    @objc public func hasConsent(for type: ConsentType) -> Bool {
        return getConsentStatus(for: type) == .granted
    }
    
    @objc public func hasAnyConsent() -> Bool {
        return ConsentType.allCases.contains { hasConsent(for: $0) }
    }
    
    @objc public func revokeConsent(for type: ConsentType) {
        setConsent(.denied, for: type)
    }
    
    @objc public func revokeAllConsents() {
        for type in ConsentType.allCases {
            setConsent(.denied, for: type)
        }
    }
    
    @objc public func getConsentString() -> String? {
        // Return IAB TCF consent string if available
        return storageHelper.getValue(forKey: "IAB_TCFAPI_CmpSdkVersion") as? String
    }
    
    @objc public func setConsentString(_ consentString: String) {
        storageHelper.setValue(consentString, forKey: "consent_string")
        
        // Parse consent string and update individual consents
        parseConsentString(consentString)
    }
    
    @objc public func isGDPRApplicable() -> Bool {
        // Check if GDPR applies based on user location or configuration
        let locale = Locale.current
        let gdprCountries = ["AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"]
        
        return gdprCountries.contains(locale.regionCode ?? "")
    }
    
    @objc public func isCCPAApplicable() -> Bool {
        // Check if CCPA applies based on user location
        let locale = Locale.current
        return locale.regionCode == "US" // Simplified - could be more specific to California
    }
    
    @objc public func exportConsentData() -> [String: Any] {
        var exportData: [String: Any] = [:]
        
        for type in ConsentType.allCases {
            let key = consentTypeToString(type)
            exportData[key] = [
                "status": getConsentStatus(for: type).rawValue,
                "timestamp": consentTimestamps[type]?.timeIntervalSince1970 ?? 0
            ]
        }
        
        exportData["export_timestamp"] = Date().timeIntervalSince1970
        return exportData
    }
    
    @objc public func importConsentData(_ data: [String: Any]) throws {
        guard let exportTimestamp = data["export_timestamp"] as? TimeInterval else {
            throw AnalyticsError.invalidData
        }
        
        // Only import if data is recent (within last 30 days)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        guard Date(timeIntervalSince1970: exportTimestamp) > thirtyDaysAgo else {
            throw AnalyticsError.dataExpired
        }
        
        for type in ConsentType.allCases {
            let key = consentTypeToString(type)
            if let consentData = data[key] as? [String: Any],
               let statusRaw = consentData["status"] as? Int,
               let status = ConsentStatus(rawValue: statusRaw) {
                setConsent(status, for: type)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func applicationDidBecomeActive() {
        // Check for expired consents
        for type in ConsentType.allCases {
            _ = getConsentStatus(for: type) // This will automatically handle expiration
        }
    }
    
    private func requestAppTrackingTransparencyConsent(completion: @escaping (ConsentStatus, Error?) -> Void) {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                let consentStatus: ConsentStatus
                switch status {
                case .authorized:
                    consentStatus = .granted
                case .denied, .restricted:
                    consentStatus = .denied
                case .notDetermined:
                    consentStatus = .unknown
                @unknown default:
                    consentStatus = .unknown
                }
                
                DispatchQueue.main.async {
                    self.setConsent(consentStatus, for: .appTrackingTransparency)
                    completion(consentStatus, nil)
                }
            }
        } else {
            // For iOS versions before 14, assume consent is granted
            setConsent(.granted, for: .appTrackingTransparency)
            completion(.granted, nil)
        }
    }
    
    private func requestGDPRConsent(completion: @escaping (ConsentStatus, Error?) -> Void) {
        // This would typically show a GDPR consent dialog
        // For now, we'll return unknown and let the app handle it
        completion(.unknown, AnalyticsError.consentRequired)
    }
    
    private func requestCCPAConsent(completion: @escaping (ConsentStatus, Error?) -> Void) {
        // This would typically show a CCPA consent dialog
        // For now, we'll return unknown and let the app handle it
        completion(.unknown, AnalyticsError.consentRequired)
    }
    
    private func loadStoredConsents() {
        for type in ConsentType.allCases {
            let statusKey = "consent_status_\(type.rawValue)"
            let timestampKey = "consent_timestamp_\(type.rawValue)"
            
            if let statusRaw = storageHelper.getValue(forKey: statusKey) as? Int,
               let status = ConsentStatus(rawValue: statusRaw) {
                consentStatuses[type] = status
            }
            
            if let timestamp = storageHelper.getValue(forKey: timestampKey) as? Date {
                consentTimestamps[type] = timestamp
            }
        }
    }
    
    private func saveConsent(type: ConsentType, status: ConsentStatus) {
        let statusKey = "consent_status_\(type.rawValue)"
        let timestampKey = "consent_timestamp_\(type.rawValue)"
        
        storageHelper.setValue(status.rawValue, forKey: statusKey)
        storageHelper.setValue(Date(), forKey: timestampKey)
    }
    
    private func parseConsentString(_ consentString: String) {
        // This would parse IAB TCF consent string
        // Implementation would depend on the specific consent string format
        Logger.debug("Parsing consent string: \(consentString.prefix(20))...")
    }
    
    private func trackConsentChange(type: ConsentType, status: ConsentStatus, previousStatus: ConsentStatus) {
        let consentData: [String: Any] = [
            "consent_type": consentTypeToString(type),
            "new_status": consentStatusToString(status),
            "previous_status": consentStatusToString(previousStatus),
            "is_gdpr_applicable": isGDPRApplicable(),
            "is_ccpa_applicable": isCCPAApplicable(),
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "consent_changed", data: consentData)
        Logger.info("Consent changed: \(consentTypeToString(type)) -> \(consentStatusToString(status))")
    }
    
    private func consentTypeToString(_ type: ConsentType) -> String {
        switch type {
        case .analytics:
            return "analytics"
        case .advertising:
            return "advertising"
        case .functional:
            return "functional"
        case .performance:
            return "performance"
        case .gdpr:
            return "gdpr"
        case .ccpa:
            return "ccpa"
        case .appTrackingTransparency:
            return "app_tracking_transparency"
        }
    }
    
    private func consentStatusToString(_ status: ConsentStatus) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .notRequired:
            return "not_required"
        case .notDetermined:
            return "not_determinded"
        case .restricted:
            return "restricted"
        }
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let consentStatusChanged = Notification.Name("ConsentStatusChangedNotification")
}

extension ConsentManager {
    
    @objc public func canTrackAnalytics() -> Bool {
        return hasConsent(for: .analytics) || (!isGDPRApplicable() && !isCCPAApplicable())
    }
    
    @objc public func canTrackAdvertising() -> Bool {
        let hasATTConsent = hasConsent(for: .appTrackingTransparency)
        let hasAdConsent = hasConsent(for: .advertising)
        
        if #available(iOS 14, *) {
            return hasATTConsent && hasAdConsent
        } else {
            return hasAdConsent
        }
    }
    
    @objc public func shouldRequestConsent() -> Bool {
        // Determine if we need to show consent UI
        if isGDPRApplicable() {
            return getConsentStatus(for: .gdpr) == .unknown
        }
        
        if isCCPAApplicable() {
            return getConsentStatus(for: .ccpa) == .unknown
        }
        
        if #available(iOS 14, *) {
            return getConsentStatus(for: .appTrackingTransparency) == .unknown
        }
        
        return false
    }
}

// MARK: - Error Types

extension AnalyticsError {
//    static let consentRequired = NSError(
//        domain: "AnalyticsSDK",
//        code: 1001,
//        userInfo: [NSLocalizedDescriptionKey: "User consent is required"]
//    )
    
    static let invalidData = NSError(
        domain: "AnalyticsSDK",
        code: 1002,
        userInfo: [NSLocalizedDescriptionKey: "Invalid consent data"]
    )
    
    static let dataExpired = NSError(
        domain: "AnalyticsSDK",
        code: 1003,
        userInfo: [NSLocalizedDescriptionKey: "Consent data has expired"]
    )
}
