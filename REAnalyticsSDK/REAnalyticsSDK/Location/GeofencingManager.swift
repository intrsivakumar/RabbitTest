
import Foundation
import CoreLocation

struct GeofenceDefinition: Codable {
    let id: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let type: String?
    let metadata: [String: Any]?
    
    private enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, radius, type, metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        radius = try container.decode(Double.self, forKey: .radius)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        metadata = try container.decodeIfPresent([String: Any].self, forKey: .metadata)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(radius, forKey: .radius)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

class GeofencingManager: NSObject, CLLocationManagerDelegate {
    
    private let locationManager: CLLocationManager
    private let networkHandler: NetworkHandler
    private let eventTracker: ManualEventTracker
    private let storageHelper: StorageHelper
    
    private var monitoredGeofences: [String: GeofenceDefinition] = [:]
    private var syncTimer: Timer?
    
    init(locationManager: CLLocationManager = CLLocationManager(),
         networkHandler: NetworkHandler = NetworkHandler(),
         eventTracker: ManualEventTracker = ManualEventTracker(),
         storageHelper: StorageHelper = StorageHelper()) {
        self.locationManager = locationManager
        self.networkHandler = networkHandler
        self.eventTracker = eventTracker
        self.storageHelper = storageHelper
        super.init()
        
        locationManager.delegate = self
        loadStoredGeofences()
        setupPeriodicSync()
    }
    
    deinit {
        syncTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func syncGeofences() {
        networkHandler.fetchGeofences { [weak self] result in
            switch result {
            case .success(let geofences):
                self?.updateGeofences(geofences)
            case .failure(let error):
                Logger.error("Failed to sync geofences: \(error)")
            }
        }
    }
    
    func getMonitoredGeofences() -> [CLRegion] {
        return Array(locationManager.monitoredRegions)
    }
    
    func addGeofence(_ definition: GeofenceDefinition) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            Logger.error("Geofencing is not available")
            return
        }
        
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: definition.latitude, longitude: definition.longitude),
            radius: definition.radius,
            identifier: definition.id
        )
        
        region.notifyOnEntry = true
        region.notifyOnExit = true
        
        locationManager.startMonitoring(for: region)
        monitoredGeofences[definition.id] = definition
        
        Logger.info("Added geofence: \(definition.id)")
    }
    
    func removeGeofence(_ geofenceId: String) {
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == geofenceId }) {
            locationManager.stopMonitoring(for: region)
            monitoredGeofences.removeValue(forKey: geofenceId)
            Logger.info("Removed geofence: \(geofenceId)")
        }
    }
    
    // MARK: - Private Methods
    
    private func updateGeofences(_ geofences: [GeofenceDefinition]) {
        // Remove old geofences
        for region in locationManager.monitoredRegions {
            if !geofences.contains(where: { $0.id == region.identifier }) {
                locationManager.stopMonitoring(for: region)
            }
        }
        
        // Add new geofences (limited to 20 by iOS)
        let maxGeofences = 20
        let geofencesToAdd = Array(geofences.prefix(maxGeofences))
        
        for definition in geofencesToAdd {
            if !locationManager.monitoredRegions.contains(where: { $0.identifier == definition.id }) {
                addGeofence(definition)
            }
        }
        
        // Update stored geofences
        monitoredGeofences = Dictionary(uniqueKeysWithValues: geofencesToAdd.map { ($0.id, $0) })
        saveGeofences()
        
        Logger.info("Updated \(geofencesToAdd.count) geofences")
    }
    
    private func loadStoredGeofences() {
        guard let data = storageHelper.getValue(forKey: Constants.Storage.geofenceData) as? Data else {
            return
        }
        
        do {
            let geofences = try JSONDecoder().decode([GeofenceDefinition].self, from: data)
            for geofence in geofences {
                addGeofence(geofence)
            }
        } catch {
            Logger.error("Failed to load stored geofences: \(error)")
        }
    }
    
    private func saveGeofences() {
        do {
            let geofences = Array(monitoredGeofences.values)
            let data = try JSONEncoder().encode(geofences)
            storageHelper.setValue(data, forKey: Constants.Storage.geofenceData)
        } catch {
            Logger.error("Failed to save geofences: \(error)")
        }
    }
    
    private func setupPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.syncGeofences()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let geofence = monitoredGeofences[region.identifier] else { return }
        
        var eventData: [String: Any] = [
            "geofence_id": region.identifier,
            "trigger_type": "entry",
            "geofence_type": geofence.type ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "metadata": geofence.metadata ?? [:]
        ]
        
        // Add current location if available
        if let location = LocationManager.shared.getCurrentLocation() {
            eventData["latitude"] = location.coordinate.latitude
            eventData["longitude"] = location.coordinate.longitude
        }
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.geofenceEntered, data: eventData)
        
        // Trigger server notification
        triggerGeofenceNotification(geofenceId: region.identifier, triggerType: "entry")
        
        Logger.info("Entered geofence: \(region.identifier)")
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let geofence = monitoredGeofences[region.identifier] else { return }
        
        var eventData: [String: Any] = [
            "geofence_id": region.identifier,
            "trigger_type": "exit",
            "geofence_type": geofence.type ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "metadata": geofence.metadata ?? [:]
        ]
        
        // Add current location if available
        if let location = LocationManager.shared.getCurrentLocation() {
            eventData["latitude"] = location.coordinate.latitude
            eventData["longitude"] = location.coordinate.longitude
        }
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.geofenceExited, data: eventData)
        
        // Trigger server notification
        triggerGeofenceNotification(geofenceId: region.identifier, triggerType: "exit")
        
        Logger.info("Exited geofence: \(region.identifier)")
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Logger.error("Geofence monitoring failed for region \(region?.identifier ?? "unknown"): \(error)")
        
        let errorData: [String: Any] = [
            "geofence_id": region?.identifier ?? "",
            "error_description": error.localizedDescription,
            "error_code": (error as NSError).code,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        eventTracker.trackEvent(name: "geofence_monitoring_error", data: errorData)
    }
    
    private func triggerGeofenceNotification(geofenceId: String, triggerType: String) {
        let notificationData: [String: Any] = [
            "geofence_id": geofenceId,
            "trigger_type": triggerType,
            "user_id": StorageHelper.getUserId() ?? "",
            "device_id": StorageHelper.getDeviceId(),
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        networkHandler.triggerGeofenceNotification(notificationData) { result in
            switch result {
            case .success:
                Logger.debug("Geofence notification triggered successfully")
            case .failure(let error):
                Logger.error("Failed to trigger geofence notification: \(error)")
            }
        }
    }
}
