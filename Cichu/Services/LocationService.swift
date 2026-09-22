import CoreLocation
import Observation
import Foundation

/// Region monitoring and significant changes deliberately avoid continuous GPS.
/// Region callbacks are approximate OS observations, not exact arrival timestamps.
@MainActor @Observable final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let store: JournalStore
    private var gate = TransitionGate()
    private var verificationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var enabled: Bool
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var statusMessage: String?
    var authorized: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }
    var statusTitle: String {
        if store.isDemo { return "示例模式" }
        if !enabled { return "自动记录已暂停" }
        if authorization == .authorizedAlways { return "自动记录已开启" }
        if authorization == .authorizedWhenInUse { return "仅使用期间定位" }
        return "等待定位授权"
    }

    init(store: JournalStore, defaults: UserDefaults = .standard) {
        self.store = store; self.defaults = defaults
        enabled = !store.isDemo && defaults.bool(forKey: "trackingEnabled")
        if !store.isDemo, let data = defaults.data(forKey: "transitionGate"),
           let saved = try? JSONDecoder().decode(TransitionGate.self, from: data) { gate = saved }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        authorization = manager.authorizationStatus
        if enabled { refreshRegions() }
    }
    func setEnabled(_ value: Bool) {
        guard !store.isDemo else { return }
        enabled = value; defaults.set(value, forKey: "trackingEnabled")
        if value {
            if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
            else { refreshRegions() }
        } else {
            clearCandidate(); stopMonitoring(); store.stop()
        }
    }
    func requestBackgroundPermission() {
        guard !store.isDemo else { return }
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if authorization == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
    }
    func locateOnce() {
        guard !store.isDemo else { return }
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if authorized { manager.requestLocation() }
        else { statusMessage = "请在系统设置中允许此处访问位置。" }
    }
    func refreshRegions() {
        guard !store.isDemo, enabled, authorized else { return }
        stopMonitoring()
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            statusMessage = "当前设备不支持地点围栏，可使用手动记录。"; return
        }
        // iOS allows at most 20 regions per app. Prioritize nearby places when a fix exists.
        let places = store.visiblePlaces.sorted { a, b in
            guard let coordinate else { return a.createdAt < b.createdAt }
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return here.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude)) < here.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }
        for place in places.prefix(20) {
            let maximum = manager.maximumRegionMonitoringDistance
            let radius = maximum > 0 ? min(place.radius, maximum) : place.radius
            let region = CLCircularRegion(center: place.coordinate, radius: radius, identifier: place.id.uuidString)
            region.notifyOnEntry = true; region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
        manager.requestLocation()
    }
    private func stopMonitoring() {
        manager.monitoredRegions.forEach { manager.stopMonitoring(for: $0) }
        manager.stopMonitoringSignificantLocationChanges()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !store.isDemo else { return }
        authorization = manager.authorizationStatus
        if authorized {
            if enabled { refreshRegions() } else { manager.requestLocation() }
        } else if authorization == .denied || authorization == .restricted {
            clearCandidate(); stopMonitoring(); store.stop()
            statusMessage = "定位权限不可用。仍可添加地点和手动补记。"
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0,
              abs(fix.timestamp.timeIntervalSinceNow) < 120 else { return }
        coordinate = fix.coordinate; statusMessage = nil
        guard enabled, fix.horizontalAccuracy <= 100 else { return }
        // Require the accuracy circle to fit inside/outside a fence to reduce boundary jitter.
        let matches = store.visiblePlaces.compactMap { place -> (Place, Double)? in
            let distance = fix.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
            return distance + fix.horizontalAccuracy <= place.radius ? (place, distance) : nil
        }.sorted { $0.1 < $1.1 }
        // Keep the current place while overlapping fences still contain it.
        if let active = store.active, active.kind == .stay,
           matches.contains(where: { $0.0.id == active.placeID }) { clearCandidate(); return }
        if let place = matches.first?.0 { consider(place.id) }
        else if let active = store.active, active.kind == .stay, let place = store.place(active.placeID) {
            let distance = fix.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
            if distance - fix.horizontalAccuracy > place.radius + 50 { consider(nil) }
            else { clearCandidate() }
        } else { clearCandidate() }
    }
    private func clearCandidate() {
        gate.reset(); defaults.removeObject(forKey: "transitionGate")
        verificationTask?.cancel(); verificationTask = nil
    }
    private func consider(_ id: UUID?) {
        let current = store.active?.kind == .stay ? store.active?.placeID : nil
        if gate.observe(placeID: id, currentID: current, at: .now) {
            if let id, let place = store.place(id) { store.arrive(place) }
            else if let current { store.depart(current) }
            clearCandidate()
        } else {
            if let data = try? JSONEncoder().encode(gate) { defaults.set(data, forKey: "transitionGate") }
            guard gate.candidate != nil, verificationTask == nil else { return }
            verificationTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(95)) } catch { return }
                guard let self, self.enabled, self.authorized else { return }
                self.verificationTask = nil
                self.manager.requestLocation()
            }
        }
    }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // A fence callback requests a measured fix; it does not override an overlapping place.
        guard enabled, authorized else { return }
        manager.requestLocation()
    }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard enabled, authorized else { return }
        manager.requestLocation()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusMessage = "暂时无法获取位置，请稍后重试。"
    }
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        statusMessage = "部分地点未能开启自动识别，可在设置中重新开启记录。"
    }
}
