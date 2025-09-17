
import Foundation
import UIKit

struct Rule: Codable {
    let id: String
    let name: String
    let conditions: [Condition]
    let actions: [Action]
    let priority: Int
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct Condition: Codable {
    let type: ConditionType
    let property: String
    let `operator`: ConditionOperator
    let value: Any
    let logicalOperator: LogicalOperator?
    
    enum ConditionType: String, Codable {
        case userAttribute = "user_attribute"
        case eventProperty = "event_property"
        case sessionActivity = "session_activity"
        case temporal = "temporal"
        case location = "location"
        case appState = "app_state"
    }
    
    enum ConditionOperator: String, Codable {
        case equals = "equals"
        case notEquals = "not_equals"
        case greaterThan = "greater_than"
        case lessThan = "less_than"
        case contains = "contains"
        case startsWith = "starts_with"
        case endsWith = "ends_with"
        case `in` = "in"
        case notIn = "not_in"
    }
    
    enum LogicalOperator: String, Codable {
        case and = "and"
        case or = "or"
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, property, `operator`, value, logicalOperator
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(ConditionType.self, forKey: .type)
        property = try container.decode(String.self, forKey: .property)
        `operator` = try container.decode(ConditionOperator.self, forKey: .operator)
        value = try container.decode(AnyCodable.self, forKey: .value).value
        logicalOperator = try container.decodeIfPresent(LogicalOperator.self, forKey: .logicalOperator)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(property, forKey: .property)
        try container.encode(`operator`, forKey: .operator)
        try container.encode(AnyCodable(value), forKey: .value)
        try container.encodeIfPresent(logicalOperator, forKey: .logicalOperator)
    }
}

struct Action: Codable {
    let type: ActionType
    let parameters: [String: Any]
    
    enum ActionType: String, Codable {
        case sendPushNotification = "send_push_notification"
        case showInAppMessage = "show_in_app_message"
        case trackEvent = "track_event"
        case updateUserProperty = "update_user_property"
        case syncToServer = "sync_to_server"
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, parameters
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(ActionType.self, forKey: .type)
        parameters = try container.decode([String: AnyCodable].self, forKey: .parameters)
            .mapValues { $0.value }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(parameters.mapValues { AnyCodable($0) }, forKey: .parameters)
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

class LocalRuleEngine {
    
    private let storageHelper: StorageHelper
    private let eventTracker: ManualEventTracker
    private let sessionManager: SessionManager
    private let userTrackingManager: UserTrackingManager
    
    private var rules: [Rule] = []
    private let ruleQueue = DispatchQueue(label: "com.analytics.ruleengine", qos: .utility)
    
    init(storageHelper: StorageHelper = StorageHelper(),
         eventTracker: ManualEventTracker = ManualEventTracker(),
         sessionManager: SessionManager = SessionManager.shared,
         userTrackingManager: UserTrackingManager = UserTrackingManager()) {
        self.storageHelper = storageHelper
        self.eventTracker = eventTracker
        self.sessionManager = sessionManager
        self.userTrackingManager = userTrackingManager
        
        loadRules()
    }
    
    // MARK: - Public Methods
    
    func evaluateEvent(_ event: Event) {
        ruleQueue.async {
            self.evaluateRulesForEvent(event)
        }
    }
    
    func evaluateInAppMessageTrigger(_ trigger: String, context: [String: Any], completion: @escaping (Bool, InAppNotificationContent?) -> Void) {
        ruleQueue.async {
            let shouldShow = self.shouldShowInAppMessage(trigger, context: context)
            let content = shouldShow ? self.createInAppContent(trigger, context: context) : nil
            
            DispatchQueue.main.async {
                completion(shouldShow, content)
            }
        }
    }
    
    func updateRules(_ newRules: [Rule]) {
        ruleQueue.async {
            self.rules = newRules.sorted { $0.priority > $1.priority }
            self.saveRules()
            Logger.info("Updated \(newRules.count) local rules")
        }
    }
    
    func addRule(_ rule: Rule) {
        ruleQueue.async {
            self.rules.append(rule)
            self.rules.sort { $0.priority > $1.priority }
            self.saveRules()
        }
    }
    
    func removeRule(withId ruleId: String) {
        ruleQueue.async {
            self.rules.removeAll { $0.id == ruleId }
            self.saveRules()
        }
    }
    
    func getActiveRules() -> [Rule] {
        return rules.filter { $0.isActive }
    }
    
    // MARK: - Private Methods
    
    private func evaluateRulesForEvent(_ event: Event) {
        let activeRules = rules.filter { $0.isActive }
        
        for rule in activeRules {
            if evaluateConditions(rule.conditions, for: event) {
                executeActions(rule.actions, context: ["event": event])
                
                // Track rule execution
                let ruleData: [String: Any] = [
                    "rule_id": rule.id,
                    "rule_name": rule.name,
                    "event_name": event.name,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
                
                eventTracker.trackEvent(name: "rule_executed", data: ruleData)
            }
        }
    }
    
    private func evaluateConditions(_ conditions: [Condition], for event: Event) -> Bool {
        guard !conditions.isEmpty else { return true }
        
        var result = evaluateCondition(conditions[0], for: event)
        
        for i in 1..<conditions.count {
            let condition = conditions[i]
            let conditionResult = evaluateCondition(condition, for: event)
            
            if let logicalOperator = conditions[i-1].logicalOperator {
                switch logicalOperator {
                case .and:
                    result = result && conditionResult
                case .or:
                    result = result || conditionResult
                }
            } else {
                result = result && conditionResult
            }
        }
        
        return result
    }
    
    private func evaluateCondition(_ condition: Condition, for event: Event) -> Bool {
        let actualValue = getValueForCondition(condition, event: event)
        let expectedValue = condition.value
        
        return compareValues(actualValue, expectedValue, operator: condition.operator)
    }
    
    private func getValueForCondition(_ condition: Condition, event: Event) -> Any? {
        switch condition.type {
        case .eventProperty:
            return event.properties[condition.property]
            
        case .userAttribute:
            guard let userProfile = userTrackingManager.getUserDetails() else { return nil }
            return getUserPropertyValue(userProfile, property: condition.property)
            
        case .sessionActivity:
            guard let session = sessionManager.getCurrentSession() else { return nil }
            return getSessionPropertyValue(session, property: condition.property)
            
        case .temporal:
            return getTemporalValue(condition.property)
            
        case .location:
            return getLocationValue(condition.property)
            
        case .appState:
            return getAppStateValue(condition.property)
        }
    }
    
    private func getUserPropertyValue(_ userProfile: UserProfile, property: String) -> Any? {
        switch property {
        case "country": return userProfile.country
        case "city": return userProfile.city
        case "age": return userProfile.age
        case "subscriptionStatus": return userProfile.subscriptionStatus
        default:
            return userProfile.customAttributes?[property]
        }
    }
    
    private func getSessionPropertyValue(_ session: Session, property: String) -> Any? {
        switch property {
        case "duration": return session.duration
        case "screen_count": return session.screenCount
        case "event_count": return session.eventCount
        case "screens_viewed": return session.screensViewed
        default: return nil
        }
    }
    
    private func getTemporalValue(_ property: String) -> Any? {
        let now = Date()
        let calendar = Calendar.current
        
        switch property {
        case "local_time":
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: now)
        case "day_of_week":
            return calendar.component(.weekday, from: now)
        case "hour":
            return calendar.component(.hour, from: now)
        default: return nil
        }
    }
    
    private func getLocationValue(_ property: String) -> Any? {
        guard let location = LocationManager.shared.getCurrentLocation() else { return nil }
        
        switch property {
        case "latitude": return location.coordinate.latitude
        case "longitude": return location.coordinate.longitude
        case "accuracy": return location.horizontalAccuracy
        default: return nil
        }
    }
    
    private func getAppStateValue(_ property: String) -> Any? {
        switch property {
        case "is_foreground": return UIApplication.shared.applicationState == .active
        case "app_version": return Bundle.main.infoDictionary?["CFBundleShortVersionString"]
        case "os_version": return UIDevice.current.systemVersion
        default: return nil
        }
    }
    
    private func compareValues(_ actual: Any?, _ expected: Any, operator: Condition.ConditionOperator) -> Bool {
        guard let actual = actual else { return false }
        
        switch `operator` {
        case .equals:
            return isEqual(actual, expected)
        case .notEquals:
            return !isEqual(actual, expected)
        case .greaterThan:
            return isGreaterThan(actual, expected)
        case .lessThan:
            return isLessThan(actual, expected)
        case .contains:
            return contains(actual, expected)
        case .startsWith:
            return startsWith(actual, expected)
        case .endsWith:
            return endsWith(actual, expected)
        case .in:
            return isIn(actual, expected)
        case .notIn:
            return !isIn(actual, expected)
        }
    }
    
    private func isEqual(_ actual: Any, _ expected: Any) -> Bool {
        if let actualString = actual as? String, let expectedString = expected as? String {
            return actualString == expectedString
        } else if let actualNumber = actual as? NSNumber, let expectedNumber = expected as? NSNumber {
            return actualNumber == expectedNumber
        } else if let actualBool = actual as? Bool, let expectedBool = expected as? Bool {
            return actualBool == expectedBool
        }
        return false
    }
    
    private func isGreaterThan(_ actual: Any, _ expected: Any) -> Bool {
        if let actualNumber = actual as? NSNumber, let expectedNumber = expected as? NSNumber {
            return actualNumber.doubleValue > expectedNumber.doubleValue
        }
        return false
    }
    
    private func isLessThan(_ actual: Any, _ expected: Any) -> Bool {
        if let actualNumber = actual as? NSNumber, let expectedNumber = expected as? NSNumber {
            return actualNumber.doubleValue < expectedNumber.doubleValue
        }
        return false
    }
    
    private func contains(_ actual: Any, _ expected: Any) -> Bool {
        if let actualString = actual as? String, let expectedString = expected as? String {
            return actualString.contains(expectedString)
        } else if let actualArray = actual as? [Any], let expectedValue = expected as? Any {
            return actualArray.contains { isEqual($0, expectedValue) }
        }
        return false
    }
    
    private func startsWith(_ actual: Any, _ expected: Any) -> Bool {
        if let actualString = actual as? String, let expectedString = expected as? String {
            return actualString.hasPrefix(expectedString)
        }
        return false
    }
    
    private func endsWith(_ actual: Any, _ expected: Any) -> Bool {
        if let actualString = actual as? String, let expectedString = expected as? String {
            return actualString.hasSuffix(expectedString)
        }
        return false
    }
    
    private func isIn(_ actual: Any, _ expected: Any) -> Bool {
        if let expectedArray = expected as? [Any] {
            return expectedArray.contains { isEqual(actual, $0) }
        }
        return false
    }
    
    private func executeActions(_ actions: [Action], context: [String: Any]) {
        for action in actions {
            executeAction(action, context: context)
        }
    }
    
    private func executeAction(_ action: Action, context: [String: Any]) {
        switch action.type {
        case .sendPushNotification:
            handleSendPushNotification(action.parameters, context: context)
        case .showInAppMessage:
            handleShowInAppMessage(action.parameters, context: context)
        case .trackEvent:
            handleTrackEvent(action.parameters, context: context)
        case .updateUserProperty:
            handleUpdateUserProperty(action.parameters, context: context)
        case .syncToServer:
            handleSyncToServer(action.parameters, context: context)
        }
    }
    
    private func handleSendPushNotification(_ parameters: [String: Any], context: [String: Any]) {
        // This would trigger a server call to send push notification
        Logger.info("Rule triggered push notification with parameters: \(parameters)")
    }
    
    private func handleShowInAppMessage(_ parameters: [String: Any], context: [String: Any]) {
        guard let messageId = parameters["message_id"] as? String else { return }
        
        DispatchQueue.main.async {
            // This would show in-app message
            NotificationCenter.default.post(name: .showInAppMessage, object: messageId, userInfo: parameters)
        }
    }
    
    private func handleTrackEvent(_ parameters: [String: Any], context: [String: Any]) {
        guard let eventName = parameters["event_name"] as? String else { return }
        
        var eventData = parameters
        eventData.removeValue(forKey: "event_name")
        eventData["triggered_by_rule"] = true
        
        eventTracker.trackEvent(name: eventName, data: eventData)
    }
    
    private func handleUpdateUserProperty(_ parameters: [String: Any], context: [String: Any]) {
        guard let property = parameters["property"] as? String,
              let value = parameters["value"] else { return }
        
        // Update user property
        userTrackingManager.updateCustomAttribute(key: property, value: value)
    }
    
    private func handleSyncToServer(_ parameters: [String: Any], context: [String: Any]) {
        // Sync specific data to server
        Logger.info("Rule triggered server sync with parameters: \(parameters)")
    }
    
    private func shouldShowInAppMessage(_ trigger: String, context: [String: Any]) -> Bool {
        let messageRules = rules.filter { rule in
            rule.isActive && rule.actions.contains { $0.type == .showInAppMessage }
        }
        
        for rule in messageRules {
            if evaluateMessageRule(rule, trigger: trigger, context: context) {
                return true
            }
        }
        
        return false
    }
    
    private func evaluateMessageRule(_ rule: Rule, trigger: String, context: [String: Any]) -> Bool {
        // Simple evaluation for in-app message triggers
        return rule.conditions.allSatisfy { condition in
            if condition.property == "trigger" {
                return isEqual(trigger, condition.value)
            }
            
            if let contextValue = context[condition.property] {
                return compareValues(contextValue, condition.value, operator: condition.operator)
            }
            
            return false
        }
    }
    
    private func createInAppContent(_ trigger: String, context: [String: Any]) -> InAppNotificationContent {
        let content = InAppNotificationContent()
        content.title = "Special Offer"
        content.message = "Don't miss out on this limited time offer!"
        content.buttonText = "Learn More"
        content.buttonAction = "view_offer"
        content.campaignId = "rule_triggered_\(trigger)"
        return content
    }
    
    private func loadRules() {
        guard let data = storageHelper.getValue(forKey: Constants.Storage.ruleEngineData) as? Data else {
            return
        }
        
        do {
            rules = try JSONDecoder().decode([Rule].self, from: data)
            rules.sort { $0.priority > $1.priority }
            Logger.info("Loaded \(rules.count) local rules")
        } catch {
            Logger.error("Failed to load rules: \(error)")
        }
    }
    
    private func saveRules() {
        do {
            let data = try JSONEncoder().encode(rules)
            storageHelper.setValue(data, forKey: Constants.Storage.ruleEngineData)
        } catch {
            Logger.error("Failed to save rules: \(error)")
        }
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let showInAppMessage = Notification.Name("showInAppMessage")
}
