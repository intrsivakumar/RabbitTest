// Adding docs
import Foundation
import UIKit

@objc public class ResumeData: NSObject, Codable {
    @objc public let sessionId: String
    @objc public let screenName: String
    @objc public let navigationStack: [String]
    @objc public let formData: [String: String]
    @objc public let eventQueue: [String]
    @objc public let timestamp: Date
    @objc public let consentStatus: String
    
    public init(sessionId: String, screenName: String, navigationStack: [String], formData: [String: String], eventQueue: [String], consentStatus: String) {
        self.sessionId = sessionId
        self.screenName = screenName
        self.navigationStack = navigationStack
        self.formData = formData
        self.eventQueue = eventQueue
        self.timestamp = Date()
        self.consentStatus = consentStatus
        super.init()
    }
}

@objc public protocol ResumeJourneyDelegate: AnyObject {
    @objc optional func shouldResumeJourney(_ resumeData: ResumeData) -> Bool
    @objc optional func willResumeJourney(_ resumeData: ResumeData)
    @objc optional func didResumeJourney(_ resumeData: ResumeData, success: Bool)
    @objc optional func resumeJourneyDidFail(_ error: Error)
}

class ResumeJourneyManager {
    
    private let storageHelper: StorageHelper
    private let eventTracker: ManualEventTracker
    private let consentManager: ConsentManager
    
    @objc public weak var delegate: ResumeJourneyDelegate?
    
    private var currentResumeData: ResumeData?
    private let resumeTimeout: TimeInterval = 86400 // 24 hours
    
    init(storageHelper: StorageHelper = StorageHelper(),
         eventTracker: ManualEventTracker = ManualEventTracker(),
         consentManager: ConsentManager = ConsentManager.shared) {
        self.storageHelper = storageHelper
        self.eventTracker = eventTracker
        self.consentManager = consentManager
        
        setupApplicationObservers()
        checkForResumeData()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    @objc public func isResumeAvailable() -> Bool {
        return currentResumeData != nil && isResumeDataValid(currentResumeData!)
    }
    
    @objc public func getResumeData() -> ResumeData? {
        return isResumeAvailable() ? currentResumeData : nil
    }
    
    @objc public func resumeJourney(overrides: [String: Any]? = nil) {
        guard let resumeData = getResumeData() else {
            Logger.warning("No valid resume data available")
            delegate?.resumeJourneyDidFail?(AnalyticsError.dataCorrupted)
            return
        }
        
        // Check delegate consent
        if delegate?.shouldResumeJourney?(resumeData) == false {
            Logger.info("Resume journey cancelled by delegate")
            discardResumeData()
            return
        }
        
        delegate?.willResumeJourney?(resumeData)
        
        // Perform resume logic
        performResume(resumeData, overrides: overrides) { [weak self] success in
            self?.delegate?.didResumeJourney?(resumeData, success: success)
            
            if success {
                self?.trackResumeSuccess(resumeData)
                self?.discardResumeData()
            } else {
                self?.trackResumeFailed(resumeData)
            }
        }
    }
    
    @objc public func discardResumeData() {
        if let resumeData = currentResumeData {
            trackResumeDiscarded(resumeData)
        }
        
        currentResumeData = nil
        storageHelper.removeValue(forKey: Constants.Storage.resumeData)
        Logger.info("Resume data discarded")
    }
    
    @objc public func captureCurrentState(screenName: String, navigationStack: [String], formData: [String: String] = [:]) {
        guard consentManager.hasConsent(for: .analytics) else {
            Logger.debug("Cannot capture resume state - no consent")
            return
        }
        
        let sessionId = SessionManager.shared.getCurrentSessionId() ?? ""
        let eventQueue = getPendingEvents()
        let consentStatus = consentManager.getConsentStatus().rawValue
        
        let resumeData = ResumeData(
            sessionId: sessionId,
            screenName: screenName,
            navigationStack: navigationStack,
            formData: formData,
            eventQueue: eventQueue,
            consentStatus: String(consentStatus)
        )
        
        saveResumeData(resumeData)
        Logger.debug("Resume state captured for screen: \(screenName)")
    }
    
    // MARK: - Private Methods
    
    private func setupApplicationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func applicationWillResignActive() {
        // Capture current state if needed
        if let topViewController = getTopViewController() {
            let screenName = String(describing: type(of: topViewController))
            captureCurrentState(screenName: screenName, navigationStack: [screenName])
        }
    }
    
    @objc private func applicationDidEnterBackground() {
        // Additional state capture on background
        // This could include more detailed form data if available
    }
    
    @objc private func applicationWillTerminate() {
        // Final state capture before termination
        if let topViewController = getTopViewController() {
            let screenName = String(describing: type(of: topViewController))
            captureCurrentState(screenName: screenName, navigationStack: [screenName])
        }
    }
    
    private func checkForResumeData() {
        guard let data = storageHelper.getEncrypted(forKey: Constants.Storage.resumeData) else {
            return
        }
        
        do {
            let resumeData = try JSONDecoder().decode(ResumeData.self, from: data)
            
            if isResumeDataValid(resumeData) {
                currentResumeData = resumeData
                Logger.info("Valid resume data found for session: \(resumeData.sessionId)")
                trackResumeDataFound(resumeData)
            } else {
                Logger.debug("Resume data expired or invalid")
                storageHelper.removeValue(forKey: Constants.Storage.resumeData)
            }
        } catch {
            Logger.error("Failed to decode resume data: \(error)")
            storageHelper.removeValue(forKey: Constants.Storage.resumeData)
        }
    }
    
    private func isResumeDataValid(_ resumeData: ResumeData) -> Bool {
        // Check if data is within timeout period
        let elapsed = Date().timeIntervalSince(resumeData.timestamp)
        guard elapsed < resumeTimeout else {
            Logger.debug("Resume data expired (age: \(elapsed)s)")
            return false
        }
        
        // Check if consent is still valid
        guard resumeData.consentStatus == String(consentManager.getConsentStatus().rawValue) else {
            Logger.debug("Resume data consent mismatch")
            return false
        }
        
        return true
    }
    
    private func saveResumeData(_ resumeData: ResumeData) {
        do {
            let data = try JSONEncoder().encode(resumeData)
            _ = storageHelper.storeEncrypted(data, forKey: Constants.Storage.resumeData)
            currentResumeData = resumeData
        } catch {
            Logger.error("Failed to save resume data: \(error)")
        }
    }
    
    private func performResume(_ resumeData: ResumeData, overrides: [String: Any]?, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            // Attempt to resume the user journey
            var success = false
            
            // Try to navigate to the last screen
            if let topVC = self.getTopViewController() {
                success = self.navigateToScreen(resumeData.screenName, from: topVC)
            }
            
            // Replay pending events if navigation successful
            if success {
                self.replayPendingEvents(resumeData.eventQueue)
            }
            
            completion(success)
        }
    }
    
    private func navigateToScreen(_ screenName: String, from viewController: UIViewController) -> Bool {
        // This is a simplified navigation logic
        // In a real implementation, this would need to be customized based on the app's navigation structure
        
        Logger.info("Attempting to navigate to screen: \(screenName)")
        
        // For demonstration, we'll consider navigation successful if we can identify the screen
        let success = !screenName.isEmpty
        
        if success {
            // Here you would implement actual navigation logic based on your app's structure
            // This might involve:
            // - Presenting view controllers
            // - Pushing to navigation stack
            // - Switching tabs
            // - Deep linking to specific screens
            
            Logger.info("Navigation to \(screenName) simulated successfully")
        }
        
        return success
    }
    
    private func replayPendingEvents(_ eventQueue: [String]) {
        for eventName in eventQueue {
            let eventData: [String: Any] = [
                "replayed": true,
                "original_session_id": currentResumeData?.sessionId ?? "",
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            
            eventTracker.trackEvent(name: eventName, data: eventData)
            Logger.debug("Replayed event: \(eventName)")
        }
    }
    
    private func getPendingEvents() -> [String] {
        // In a real implementation, this would return events that haven't been sent yet
        // For now, return empty array
        return []
    }
    
    private func getTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }
        
        var topController = window.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        return topController
    }
    
    // MARK: - Tracking Methods
    
    private func trackResumeDataFound(_ resumeData: ResumeData) {
        let foundData: [String: Any] = [
            "resume_session_id": resumeData.sessionId,
            "resume_screen": resumeData.screenName,
            "resume_age_seconds": Date().timeIntervalSince(resumeData.timestamp),
            "navigation_stack_depth": resumeData.navigationStack.count,
            "form_data_keys": resumeData.formData.count,
            "pending_events": resumeData.eventQueue.count,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        eventTracker.trackEvent(name: "resume_data_found", data: foundData)
    }
    
    private func trackResumeSuccess(_ resumeData: ResumeData) {
        let successData: [String: Any] = [
            "resume_session_id": resumeData.sessionId,
            "resume_screen": resumeData.screenName,
            "navigation_stack_depth": resumeData.navigationStack.count,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "resume_journey_success", data: successData)
    }
    
    private func trackResumeFailed(_ resumeData: ResumeData) {
        let failedData: [String: Any] = [
            "resume_session_id": resumeData.sessionId,
            "resume_screen": resumeData.screenName,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "resume_journey_failed", data: failedData)
    }
    
    private func trackResumeDiscarded(_ resumeData: ResumeData) {
        let discardData: [String: Any] = [
            "resume_session_id": resumeData.sessionId,
            "resume_screen": resumeData.screenName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        eventTracker.trackEvent(name: "resume_data_discarded", data: discardData)
    }
}
