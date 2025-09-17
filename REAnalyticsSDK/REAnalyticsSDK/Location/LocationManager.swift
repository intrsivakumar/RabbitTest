
import Foundation
import CoreLocation

class LocationManager: NSObject, CLLocationManagerDelegate {
    
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    private let networkHandler: NetworkHandler
    private let storageHelper: StorageHelper
    private let consentManager: ConsentManager
    private let eventTracker: ManualEventTracker
    
    private var config: LocationConfig?
    private var currentLocation: CLLocation?
    private var lastLocationUpdate: Date?
    private var isTracking = false
    private var locationCache: [CLLocation] = []
    
     override init() {
        self.networkHandler = NetworkHandler()
        self.storageHelper = StorageHelper()
        self.consentManager = ConsentManager.shared
        self.eventTracker = ManualEventTracker()
        super.init()
        
        locationManager.delegate = self
        loadConfig()
    }
    
    // MARK: - Public Methods
    
    func setLocationTrackingConfig(_ config: LocationConfig) {
        self.config = config
        saveConfig()
        applyConfig()
    }
    
    func startTracking() {
        guard let config = config, config.enableAutoTracking else {
            Logger.warning("Location auto-tracking is disabled")
            return
        }
        
        guard consentManager.hasLocationConsent() else {
            Logger.warning("Location tracking requires user consent")
            return
        }
        
        guard CLLocationManager.locationServicesEnabled() else {
            Logger.error("Location services are disabled")
            return
        }
        
        requestLocationPermission()
        configureLocationManager()
        
        locationManager.startUpdatingLocation()
        isTracking = true
        
        Logger.info("Location tracking started")
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        isTracking = false
        Logger.info("Location tracking stopped")
    }
    
    func updateLocation(_ location: CLLocation) {
        guard consentManager.hasLocationConsent() else { return }
        
        processLocationUpdate(location, trigger: "manual")
    }
    
    func getCurrentLocation() -> CLLocation? {
        return currentLocation
    }
    
    // MARK: - Private Methods
    
    private func loadConfig() {
        if let data = storageHelper.getValue(forKey: "location_config") as? Data,
           let config = try? JSONDecoder().decode(LocationConfig.self, from: data) {
            self.config = config
        } else {
            self.config = LocationConfig() // Default config
        }
    }
    
    private func saveConfig() {
        guard let config = config else { return }
        
        do {
            let data = try JSONEncoder().encode(config)
            storageHelper.setValue(data, forKey: "location_config")
        } catch {
            Logger.error("Failed to save location config: \(error)")
        }
    }
    
    private func applyConfig() {
        guard let config = config else { return }
        
        if config.enableAutoTracking && !isTracking {
            startTracking()
        } else if !config.enableAutoTracking && isTracking {
            stopTracking()
        }
    }
    
    private func requestLocationPermission() {
        let status = locationManager.authorizationStatus
        
        switch status {
        case .notDetermined:
            if config?.requestAlwaysPermission == true {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            Logger.warning("Location permission denied")
        case .authorizedWhenInUse:
            if config?.requestAlwaysPermission == true {
                locationManager.requestAlwaysAuthorization()
            }
        case .authorizedAlways:
            // Already have the required permission
            break
        @unknown default:
            Logger.warning("Unknown location authorization status")
        }
    }
    
    private func configureLocationManager() {
        guard let config = config else { return }
        
        locationManager.desiredAccuracy = config.accuracy
        locationManager.distanceFilter = config.distanceFilter
        
        // Enable background location updates if always permission is requested
        if config.requestAlwaysPermission {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.pausesLocationUpdatesAutomatically = false
        }
    }
    
    private func processLocationUpdate(_ location: CLLocation, trigger: String) {
        // Validate location
        guard location.horizontalAccuracy < 200 else {
            Logger.debug("Location accuracy too low: \(location.horizontalAccuracy)m")
            return
        }
        
        // Check for duplicate locations
        if let lastLocation = currentLocation,
           location.distance(from: lastLocation) < 10,
           Date().timeIntervalSince(location.timestamp) < 30 {
            return // Skip duplicate/stale location
        }
        
        currentLocation = location
        lastLocationUpdate = Date()
        
        // Cache location
        locationCache.append(location)
        if locationCache.count > 100 {
            locationCache.removeFirst()
        }
        
        // Create location event data
        let locationData: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "horizontal_accuracy": location.horizontalAccuracy,
            "altitude": location.altitude,
            "vertical_accuracy": location.verticalAccuracy,
            "speed": location.speed >= 0 ? location.speed : NSNull(),
            "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
            "trigger": trigger
        ]
        
        // Track location update event
        eventTracker.trackEvent(name: "location_update", data: locationData)
        
        // Send to server
        sendLocationToServer(location, trigger: trigger)
    }
    
    private func sendLocationToServer(_ location: CLLocation, trigger: String) {
        let locationData: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "horizontal_accuracy": location.horizontalAccuracy,
            "altitude": location.altitude,
            "vertical_accuracy": location.verticalAccuracy,
            "speed": location.speed >= 0 ? location.speed : NSNull(),
            "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
            "trigger": trigger,
            "session_id": SessionManager.shared.getCurrentSessionId() ?? "",
            "device_id": StorageHelper.getDeviceId()
        ]
        
        networkHandler.sendLocation(locationData) { result in
            switch result {
            case .success:
                Logger.debug("Location sent successfully")
            case .failure(let error):
                Logger.error("Failed to send location: \(error)")
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        processLocationUpdate(location, trigger: "auto")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.error("Location manager failed with error: \(error)")
        
        let errorData: [String: Any] = [
            "error_description": error.localizedDescription,
            "error_code": (error as NSError).code,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        eventTracker.trackEvent(name: "location_error", data: errorData)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Logger.info("Location authorization changed to: \(status.rawValue)")
        
        let authData: [String: Any] = [
            "authorization_status": status.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        eventTracker.trackEvent(name: "location_authorization_changed", data: authData)
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if config?.enableAutoTracking == true && !isTracking {
                startTracking()
            }
        case .denied, .restricted:
            stopTracking()
        default:
            break
        }
    }
}
