
import Foundation
import UIKit

class ManualEventTracker: NSObject {
    
    private let networkHandler: NetworkHandler
    private let storageHelper: StorageHelper
    private let sessionManager: SessionManager
    private let consentManager: ConsentManager
    private let deviceInfoCollector: DeviceInfoCollector
    
    private var eventQueue: [Event] = []
    private var batchTimer: Timer?
    private var isOnline = true
    
    init(networkHandler: NetworkHandler = NetworkHandler(),
         storageHelper: StorageHelper = StorageHelper(),
         sessionManager: SessionManager = SessionManager.shared,
         consentManager: ConsentManager = ConsentManager.shared,
         deviceInfoCollector: DeviceInfoCollector = DeviceInfoCollector()) {
        self.networkHandler = networkHandler
        self.storageHelper = storageHelper
        self.sessionManager = sessionManager
        self.consentManager = consentManager
        self.deviceInfoCollector = deviceInfoCollector
        super.init()
        
        setupBatchTimer()
        loadQueuedEvents()
        observeNetworkChanges()
    }
    
    deinit {
        batchTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func trackEvent(name: String, data: [String: Any] = [:]) {
        guard consentManager.hasConsent(for: .analytics) else {
            Logger.warning("User consent required for event tracking")
            return
        }
        
        guard validateEventName(name) else {
            Logger.error("Invalid event name: \(name)")
            return
        }
        
        guard validateEventData(data) else {
            Logger.error("Invalid event data for event: \(name)")
            return
        }
        
        let event = createEvent(name: name, properties: data)
        enqueueEvent(event)
        
        Logger.info("Event tracked: \(name)")
    }
    
    func trackConversion(eventName: String, value: Double, currency: String = "USD", data: [String: Any] = [:]) {
        var conversionData = data
        conversionData["conversion_value"] = value
        conversionData["currency"] = currency
        conversionData["conversion_timestamp"] = ISO8601DateFormatter().string(from: Date())
        
        trackEvent(name: eventName, data: conversionData)
    }
    
    func flushEvents() {
        guard !eventQueue.isEmpty else { return }
        
        processBatch()
    }
    
    func clearEventQueue() {
        eventQueue.removeAll()
        storageHelper.removeValue(forKey: "analytics_sdk_event_queue")
        Logger.info("Event queue cleared")
    }
    
    // MARK: - Private Methods
    
    private func createEvent(name: String, properties: [String: Any]) -> Event {
        var enrichedProperties = properties
        
        // Add automatic context
        enrichedProperties["sdk_version"] = Constants.sdkVersion
        enrichedProperties["event_timestamp"] = ISO8601DateFormatter().string(from: Date())
        enrichedProperties["session_id"] = sessionManager.getCurrentSessionId()
        enrichedProperties["app_version"] = deviceInfoCollector.getAppVersion()
        enrichedProperties["device_platform"] = deviceInfoCollector.getDevicePlatform()
        enrichedProperties["os_version"] = deviceInfoCollector.getOSVersion()
        
        // Add network context
        enrichedProperties["network_type"] = deviceInfoCollector.getNetworkType()
        
        let event = Event(name: name, properties: enrichedProperties)
        
        // Add device info
        event.deviceInfo = deviceInfoCollector.getCurrentDeviceInfo()
        
        // Add location info if available
        if let locationManager = LocationManager.shared,
           let location = locationManager.getCurrentLocation() {
            event.locationInfo = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "horizontal_accuracy": location.horizontalAccuracy,
                "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
            ]
        }
        
        return event
    }
    
    private func enqueueEvent(_ event: Event) {
        eventQueue.append(event)
        
        // Persist to storage for offline support
        saveEventQueue()
        
        // Check if we should process immediately
        if eventQueue.count >= Constants.Network.batchSize {
            processBatch()
        }
    }
    
    private func setupBatchTimer() {
        batchTimer = Timer.scheduledTimer(withTimeInterval: Constants.Events.eventBatchTimeout, repeats: true) { [weak self] _ in
            self?.processBatch()
        }
    }
    
    private func processBatch() {
        guard !eventQueue.isEmpty else { return }
        guard isOnline else {
            Logger.info("Offline - events will be sent when connection is restored")
            return
        }
        
        let eventsToSend = Array(eventQueue.prefix(Constants.Network.batchSize))
        
        networkHandler.sendEvents(eventsToSend) { [weak self] result in
            switch result {
            case .success:
                self?.removeProcessedEvents(eventsToSend)
                Logger.info("Sent \(eventsToSend.count) events successfully")
            case .failure(let error):
                Logger.error("Failed to send events: \(error)")
                self?.handleSendFailure(error)
            }
        }
    }
    
    private func removeProcessedEvents(_ sentEvents: [Event]) {
        let sentEventIds = Set(sentEvents.map { $0.eventId })
        eventQueue.removeAll { sentEventIds.contains($0.eventId) }
        saveEventQueue()
    }
    
    private func handleSendFailure(_ error: Error) {
        if let analyticsError = error as? AnalyticsError,
           !analyticsError.shouldRetry {
            // Remove events that shouldn't be retried
            eventQueue.removeAll()
            saveEventQueue()
        }
        // For retryable errors, keep events in queue for next attempt
    }
    
    private func saveEventQueue() {
        do {
            let data = try JSONEncoder().encode(eventQueue)
            storageHelper.setValue(data, forKey: "analytics_sdk_event_queue")
        } catch {
            Logger.error("Failed to save event queue: \(error)")
        }
    }
    
    private func loadQueuedEvents() {
        guard let data = storageHelper.getValue(forKey: "analytics_sdk_event_queue") as? Data else {
            return
        }
        
        do {
            eventQueue = try JSONDecoder().decode([Event].self, from: data)
            Logger.info("Loaded \(eventQueue.count) queued events")
        } catch {
            Logger.error("Failed to load queued events: \(error)")
            storageHelper.removeValue(forKey: "analytics_sdk_event_queue")
        }
    }
    
    private func observeNetworkChanges() {
        // Simple network reachability monitoring
        NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isOnline = true
            self?.processBatch()
        }
        
        NotificationCenter.default.addObserver(
            forName: .networkDidBecomeUnavailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isOnline = false
        }
    }
    
    // MARK: - Validation Methods
    
    private func validateEventName(_ name: String) -> Bool {
        // Check length
        guard name.count <= Constants.Events.maxEventNameLength else {
            return false
        }
        
        // Check for empty or whitespace-only names
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        // Check for valid characters (alphanumeric, underscore, hyphen)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard name.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return false
        }
        
        return true
    }
    
    private func validateEventData(_ data: [String: Any]) -> Bool {
        // Check total number of properties
        guard data.count <= Constants.Events.maxPropertiesCount else {
            Logger.error("Event has too many properties: \(data.count)")
            return false
        }
        
        // Validate each property
        for (key, value) in data {
            // Check key length
            guard key.count <= Constants.Events.maxPropertyKeyLength else {
                Logger.error("Property key too long: \(key)")
                return false
            }
            
            // Check value
            if let stringValue = value as? String,
               stringValue.count > Constants.Events.maxPropertyValueLength {
                Logger.error("Property value too long for key: \(key)")
                return false
            }
            
            // Check for supported types
            guard isValidPropertyValue(value) else {
                Logger.error("Unsupported property value type for key: \(key)")
                return false
            }
        }
        
        return true
    }
    
    private func isValidPropertyValue(_ value: Any) -> Bool {
        switch value {
        case is String, is Int, is Double, is Float, is Bool, is NSNumber:
            return true
        case is [String: Any]:
            return true
        case is [Any]:
            return true
        case is NSNull:
            return true
        default:
            return false
        }
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let networkDidBecomeAvailable = Notification.Name("networkDidBecomeAvailable")
    static let networkDidBecomeUnavailable = Notification.Name("networkDidBecomeUnavailable")
}

// MARK: - Event Schema Validation

extension ManualEventTracker {
    
    func validateEventSchema(name: String, data: [String: Any], schema: [String: Any]) -> Bool {
        // Basic schema validation implementation
        for (key, expectedType) in schema {
            guard let value = data[key] else {
                Logger.warning("Missing required property: \(key)")
                continue
            }
            
            if let expectedTypeString = expectedType as? String {
                if !validatePropertyType(value, expectedType: expectedTypeString) {
                    Logger.error("Property \(key) has incorrect type. Expected: \(expectedTypeString)")
                    return false
                }
            }
        }
        
        return true
    }
    
    private func validatePropertyType(_ value: Any, expectedType: String) -> Bool {
        switch expectedType.lowercased() {
        case "string":
            return value is String
        case "number", "int", "integer":
            return value is NSNumber
        case "boolean", "bool":
            return value is Bool
        case "array":
            return value is [Any]
        case "object":
            return value is [String: Any]
        default:
            return true
        }
    }
}
