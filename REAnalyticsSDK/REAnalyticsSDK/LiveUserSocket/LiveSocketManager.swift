import Foundation
import Network

class LiveSocketManager: NSObject {
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let socketURL: URL
    private let eventTracker: ManualEventTracker
    private let storageHelper: StorageHelper
    
    private var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var reconnectTimer: Timer?
    
    private let messageQueue = DispatchQueue(label: "com.analytics.socket", qos: .utility)
    
    init(socketURL: URL = URL(string: "wss://live.analytics-sdk.com/ws")!,
         eventTracker: ManualEventTracker = ManualEventTracker(),
         storageHelper: StorageHelper = StorageHelper()) {
        self.socketURL = socketURL
        self.eventTracker = eventTracker
        self.storageHelper = storageHelper
        super.init()
        
        setupSession()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Public Methods
    
    func connect() {
        guard !isConnected else { return }
        
        var request = URLRequest(url: socketURL)
        request.setValue(StorageHelper.getAppId(), forHTTPHeaderField: "X-App-ID")
        request.setValue(StorageHelper.getDeviceId(), forHTTPHeaderField: "X-Device-ID")
        
        if let authToken = StorageHelper.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()
        
        startListening()
        sendHeartbeat()
        
        Logger.info("Live socket connection initiated")
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        Logger.info("Live socket disconnected")
    }
    
    func sendMessage(_ message: [String: Any]) {
        guard isConnected else {
            Logger.warning("Cannot send message - socket not connected")
            return
        }
        
        messageQueue.async {
            do {
                let data = try JSONSerialization.data(withJSONObject: message, options: [])
                let socketMessage = URLSessionWebSocketTask.Message.data(data)
                
                self.webSocket?.send(socketMessage) { error in
                    if let error = error {
                        Logger.error("Failed to send socket message: \(error)")
                        self.handleConnectionError(error)
                    }
                }
            } catch {
                Logger.error("Failed to serialize socket message: \(error)")
            }
        }
    }
    
    func sendEvent(_ event: Event) {
        let eventMessage: [String: Any] = [
            "type": "event",
            "payload": [
                "name": event.name,
                "properties": event.properties,
                "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
                "session_id": SessionManager.shared.getCurrentSessionId() ?? "",
                "user_id": StorageHelper.getUserId() ?? ""
            ]
        ]
        
        sendMessage(eventMessage)
    }
    
    func sendUserUpdate(_ userProfile: UserProfile) {
        let userMessage: [String: Any] = [
            "type": "user_update",
            "payload": [
                "unique_id": userProfile.uniqueId,
                "properties": userProfile.toDictionary(),
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        
        sendMessage(userMessage)
    }
    
    // MARK: - Private Methods
    
    private func setupSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    private func startListening() {
        guard let webSocket = webSocket else { return }
        
        webSocket.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.startListening() // Continue listening
            case .failure(let error):
                Logger.error("Socket receive error: \(error)")
                self?.handleConnectionError(error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        messageQueue.async {
            switch message {
            case .data(let data):
                self.processDataMessage(data)
            case .string(let string):
                if let data = string.data(using: .utf8) {
                    self.processDataMessage(data)
                }
            @unknown default:
                Logger.warning("Unknown socket message type received")
            }
        }
    }
    
    private func processDataMessage(_ data: Data) {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let message = json as? [String: Any],
                  let type = message["type"] as? String else {
                return
            }
            
            switch type {
            case "connected":
                handleConnectedMessage(message)
            case "ping":
                sendPongResponse()
            case "rule_update":
                handleRuleUpdate(message)
            case "config_update":
                handleConfigUpdate(message)
            default:
                Logger.debug("Unhandled socket message type: \(type)")
            }
        } catch {
            Logger.error("Failed to process socket message: \(error)")
        }
    }
    
    private func handleConnectedMessage(_ message: [String: Any]) {
        isConnected = true
        reconnectAttempts = 0
        
        Logger.info("Live socket connected successfully")
        
        // Track connection event
        eventTracker.trackEvent(name: "live_socket_connected", data: [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ])
        
        // Send initial session info
        sendSessionInfo()
    }
    
    private func sendPongResponse() {
        let pong: [String: Any] = [
            "type": "pong",
            "timestamp": Date().timeIntervalSince1970
        ]
        sendMessage(pong)
    }
    
    private func sendHeartbeat() {
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] timer in
            guard self?.isConnected == true else {
                timer.invalidate()
                return
            }
            
            let heartbeat: [String: Any] = [
                "type": "ping",
                "timestamp": Date().timeIntervalSince1970
            ]
            
            self?.sendMessage(heartbeat)
        }
    }
    
    private func sendSessionInfo() {
        guard let sessionId = SessionManager.shared.getCurrentSessionId() else { return }
        
        let sessionInfo: [String: Any] = [
            "type": "session_info",
            "payload": [
                "session_id": sessionId,
                "device_id": StorageHelper.getDeviceId(),
                "app_version": DeviceInfoCollector().getAppVersion(),
                "os_version": DeviceInfoCollector().getOSVersion(),
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        
        sendMessage(sessionInfo)
    }
    
    private func handleRuleUpdate(_ message: [String: Any]) {
        // Notify rule engine of updates
        NotificationCenter.default.post(
            name: .liveSocketRuleUpdate,
            object: nil,
            userInfo: message
        )
    }
    
    private func handleConfigUpdate(_ message: [String: Any]) {
        // Handle configuration updates
        if let payload = message["payload"] as? [String: Any] {
            Logger.info("Received config update via live socket")
            // Process configuration changes
        }
    }
    
    private func handleConnectionError(_ error: Error) {
        isConnected = false
        
        eventTracker.trackEvent(name: "live_socket_error", data: [
            "error": error.localizedDescription,
            "reconnect_attempts": reconnectAttempts,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        scheduleReconnect()
    }
    
    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            Logger.error("Max reconnection attempts reached")
            return
        }
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0) // Exponential backoff, max 60s
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Logger.info("Attempting socket reconnection (\(self?.reconnectAttempts ?? 0)/\(self?.maxReconnectAttempts ?? 0))")
            self?.connect()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension LiveSocketManager: URLSessionWebSocketDelegate {
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Logger.info("WebSocket connection opened")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Logger.info("WebSocket connection closed with code: \(closeCode.rawValue)")
        handleConnectionError(NSError(domain: "WebSocketClosed", code: closeCode.rawValue, userInfo: nil))
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let liveSocketRuleUpdate = Notification.Name("liveSocketRuleUpdate")
}

