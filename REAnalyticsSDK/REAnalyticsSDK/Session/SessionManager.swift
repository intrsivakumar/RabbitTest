
import Foundation
import UIKit

@objc public class Session: NSObject, Codable {
    @objc public let sessionId: String
    @objc public let startTimestamp: Date
    @objc public var endTimestamp: Date?
    @objc public var duration: TimeInterval = 0
    @objc public var screenCount: Int = 0
    @objc public var eventCount: Int = 0
    @objc public var interactionCount: Int = 0
    @objc public var maxScrollDepth: Double = 0
    @objc public var screensViewed: [String] = []
    @objc public var sessionSource: String = ""
    @objc public var interruptionCount: Int = 0
    @objc public var networkConditions: String = ""
    
    public init(sessionId: String = UUID().uuidString, sessionSource: String = "") {
        self.sessionId = sessionId
        self.startTimestamp = Date()
        self.sessionSource = sessionSource
        super.init()
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case sessionId, startTimestamp, endTimestamp, duration
        case screenCount, eventCount, interactionCount, maxScrollDepth
        case screensViewed, sessionSource, interruptionCount, networkConditions
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        startTimestamp = try container.decode(Date.self, forKey: .startTimestamp)
        endTimestamp = try container.decodeIfPresent(Date.self, forKey: .endTimestamp)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        screenCount = try container.decode(Int.self, forKey: .screenCount)
        eventCount = try container.decode(Int.self, forKey: .eventCount)
        interactionCount = try container.decode(Int.self, forKey: .interactionCount)
        maxScrollDepth = try container.decode(Double.self, forKey: .maxScrollDepth)
        screensViewed = try container.decode([String].self, forKey: .screensViewed)
        sessionSource = try container.decode(String.self, forKey: .sessionSource)
        interruptionCount = try container.decode(Int.self, forKey: .interruptionCount)
        networkConditions = try container.decode(String.self, forKey: .networkConditions)
        super.init()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(startTimestamp, forKey: .startTimestamp)
        try container.encodeIfPresent(endTimestamp, forKey: .endTimestamp)
        try container.encode(duration, forKey: .duration)
        try container.encode(screenCount, forKey: .screenCount)
        try container.encode(eventCount, forKey: .eventCount)
        try container.encode(interactionCount, forKey: .interactionCount)
        try container.encode(maxScrollDepth, forKey: .maxScrollDepth)
        try container.encode(screensViewed, forKey: .screensViewed)
        try container.encode(sessionSource, forKey: .sessionSource)
        try container.encode(interruptionCount, forKey: .interruptionCount)
        try container.encode(networkConditions, forKey: .networkConditions)
    }
}

class SessionManager: NSObject {
    
    static let shared = SessionManager()
    
    private let eventTracker: ManualEventTracker
    private let networkHandler: NetworkHandler
    private let storageHelper: StorageHelper
    private let deviceInfoCollector: DeviceInfoCollector
    
    private var currentSession: Session?
    private var sessionTimeout: TimeInterval = Constants.Session.defaultTimeout
    private var sessionTimer: Timer?
    private var lastActivityTime: Date = Date()
    
     override init() {
        self.eventTracker = ManualEventTracker()
        self.networkHandler = NetworkHandler()
        self.storageHelper = StorageHelper()
        self.deviceInfoCollector = DeviceInfoCollector()
        super.init()
        
        setupApplicationObservers()
        loadStoredSession()
    }
    
    deinit {
        sessionTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    func startSession(source: String = "app_launch") {
        endCurrentSession()
        
        let session = Session(sessionSource: source)
        session.networkConditions = deviceInfoCollector.getNetworkType()
        
        currentSession = session
        lastActivityTime = Date()
        
        // Store session
        storeCurrentSession()
        
        // Track session start event
        trackSessionStart(session)
        
        // Start session timeout timer
        startSessionTimer()
        
        Logger.info("Session started: \(session.sessionId)")
    }
    
    func endSession() {
        endCurrentSession()
    }
    
    func getCurrentSessionId() -> String? {
        return currentSession?.sessionId
    }
    
    func getCurrentSession() -> Session? {
        return currentSession
    }
    
    func updateActivity() {
        lastActivityTime = Date()
        currentSession?.interactionCount += 1
    }
    
    func addScreenView(_ screenName: String) {
        guard let session = currentSession else { return }
        
        if !session.screensViewed.contains(screenName) {
            session.screenCount += 1
        }
        session.screensViewed.append(screenName)
        
        storeCurrentSession()
    }
    
    func addEvent() {
        currentSession?.eventCount += 1
        updateActivity()
        storeCurrentSession()
    }
    
    func updateScrollDepth(_ depth: Double) {
        if let session = currentSession {
            session.maxScrollDepth = max(session.maxScrollDepth, depth)
            storeCurrentSession()
        }
    }
    
    func addInterruption() {
        currentSession?.interruptionCount += 1
        storeCurrentSession()
    }
    
    // MARK: - Private Methods
    
    private func setupApplicationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
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
    
    @objc private func applicationDidBecomeActive() {
        if let session = currentSession {
            let backgroundDuration = Date().timeIntervalSince(lastActivityTime)
            
            if backgroundDuration > sessionTimeout {
                // Start new session if timeout exceeded
                startSession(source: "foreground_timeout")
            } else {
                // Resume existing session
                lastActivityTime = Date()
                startSessionTimer()
                Logger.debug("Session resumed: \(session.sessionId)")
            }
        } else {
            // Start new session
            startSession(source: "app_foreground")
        }
    }
    
    @objc private func applicationWillResignActive() {
        sessionTimer?.invalidate()
        addInterruption()
    }
    
    @objc private func applicationDidEnterBackground() {
        lastActivityTime = Date()
        storeCurrentSession()
    }
    
    @objc private func applicationWillTerminate() {
        endCurrentSession()
    }
    
    private func endCurrentSession() {
        guard let session = currentSession else { return }
        
        sessionTimer?.invalidate()
        
        session.endTimestamp = Date()
        session.duration = session.endTimestamp!.timeIntervalSince(session.startTimestamp)
        
        // Track session end event
        trackSessionEnd(session)
        
        // Send session data to server
        sendSessionToServer(session)
        
        // Clear stored session
        storageHelper.removeValue(forKey: Constants.Storage.sessionId)
        
        currentSession = nil
        
        Logger.info("Session ended: \(session.sessionId), duration: \(session.duration)s")
    }
    
    private func startSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: sessionTimeout, repeats: false) { [weak self] _ in
            self?.endCurrentSession()
        }
    }
    
    private func trackSessionStart(_ session: Session) {
        let sessionData: [String: Any] = [
            "session_id": session.sessionId,
            "session_start_timestamp": ISO8601DateFormatter().string(from: session.startTimestamp),
            "session_source": session.sessionSource,
            "network_conditions": session.networkConditions,
            "device_id": deviceInfoCollector.getDeviceId(),
            "app_version": deviceInfoCollector.getAppVersion(),
            "os_version": deviceInfoCollector.getOSVersion(),
            "device_platform": deviceInfoCollector.getDevicePlatform()
        ]
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.sessionStart, data: sessionData)
    }
    
    private func trackSessionEnd(_ session: Session) {
        let sessionData: [String: Any] = [
            "session_id": session.sessionId,
            "session_start_timestamp": ISO8601DateFormatter().string(from: session.startTimestamp),
            "session_end_timestamp": ISO8601DateFormatter().string(from: session.endTimestamp ?? Date()),
            "session_duration": session.duration,
            "screen_count": session.screenCount,
            "event_count": session.eventCount,
            "interaction_count": session.interactionCount,
            "screens_viewed": session.screensViewed,
            "max_scroll_depth": session.maxScrollDepth,
            "interruption_count": session.interruptionCount,
            "session_source": session.sessionSource,
            "network_conditions": session.networkConditions
        ]
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.sessionEnd, data: sessionData)
    }
    
    private func storeCurrentSession() {
        guard let session = currentSession else { return }
        
        do {
            let data = try JSONEncoder().encode(session)
            storageHelper.setValue(data, forKey: Constants.Storage.sessionId)
        } catch {
            Logger.error("Failed to store current session: \(error)")
        }
    }
    
    private func loadStoredSession() {
        guard let data = storageHelper.getValue(forKey: Constants.Storage.sessionId) as? Data else {
            return
        }
        
        do {
            let session = try JSONDecoder().decode(Session.self, from: data)
            
            // Check if session is still valid (not expired)
            let timeSinceStart = Date().timeIntervalSince(session.startTimestamp)
            if timeSinceStart < sessionTimeout {
                currentSession = session
                lastActivityTime = session.startTimestamp
                startSessionTimer()
                Logger.info("Restored session: \(session.sessionId)")
            } else {
                // Session expired, remove it
                storageHelper.removeValue(forKey: Constants.Storage.sessionId)
                Logger.debug("Stored session expired, removed")
            }
        } catch {
            Logger.error("Failed to restore session: \(error)")
            storageHelper.removeValue(forKey: Constants.Storage.sessionId)
        }
    }
    
    private func sendSessionToServer(_ session: Session) {
        networkHandler.sendSession(session) { result in
            switch result {
            case .success:
                Logger.debug("Session sent to server successfully")
            case .failure(let error):
                Logger.error("Failed to send session to server: \(error)")
            }
        }
    }
}
