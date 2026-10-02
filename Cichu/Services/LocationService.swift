import CoreLocation
import Observation
import UIKit

/// Persist system events during their wake window; don't depend on a background timer.
@MainActor @Observable final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let driver: LocationDriving
    private let store: JournalStore
    private let defaults: UserDefaults
    private var explicitFix = false
    private var monitoring = false
    private var trackingSince: Date?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    private(set) var enabled: Bool
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var lastFixAt: Date?
    private(set) var lastEventAt: Date?
    private(set) var monitoredPlaceCount = 0
    private(set) var statusMessage: String?
    var authorized: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }
    var backgroundReady: Bool { enabled && authorization == .authorizedAlways && accuracyAuthorization == .fullAccuracy && UIApplication.shared.backgroundRefreshStatus == .available }
    var statusTitle: String {
        if store.isDemo { return "示例模式" }
        if !enabled { return "自动记录已暂停" }
        if !authorized { return "等待定位授权" }
        if accuracyAuthorization == .reducedAccuracy { return "需要开启精确位置" }
        if statusMessage != nil { return "定位需要检查" }
        if let active = store.active { return active.kind == .stay ? "停留中" : "移动 / 待识别" }
        return "等待定位识别"
    }
    var statusDetail: String {
        if store.isDemo { return "示例记录，不使用实际定位。" }
        if !enabled { return "开启自动记录后，定位到已设地点即可开始计时。" }
        if !authorized { return "请允许定位；仍可手动补记。" }
        if accuracyAuthorization == .reducedAccuracy { return "在系统设置开启精确位置，才能识别家、公司等地点范围。" }
        if let statusMessage { return statusMessage }
        if authorization != .authorizedAlways { return "前台记录可用；全天自动记录需要始终允许定位。" }
        if UIApplication.shared.backgroundRefreshStatus != .available { return "后台刷新受限，可能漏记；请检查系统设置。" }
        if store.active?.needsReview == true { return "这段时间有定位中断或延迟，时长为暂估，可查看与修正。" }
        return "到达、离开由系统事件记录，时间可能有偏差。"
    }
    init(store: JournalStore, defaults: UserDefaults = .standard, driver: LocationDriving? = nil) {
        self.store = store; self.defaults = defaults; self.driver = driver ?? CoreLocationDriver()
        enabled = !store.isDemo && defaults.bool(forKey: "trackingEnabled")
        trackingSince = defaults.object(forKey: "trackingSince") as? Date
        super.init()
        guard !store.isDemo else { return }
        self.driver.delegate = self; authorization = self.driver.authorization; accuracyAuthorization = self.driver.accuracyAuthorization
        if enabled { refreshRegions() }
    }
    func setEnabled(_ value: Bool) {
        guard !store.isDemo else { return }
        if value && !enabled { trackingSince = .now; defaults.set(trackingSince, forKey: "trackingSince") }
        enabled = value; defaults.set(value, forKey: "trackingEnabled")
        if value {
            explicitFix = true
            if authorization == .notDetermined { driver.requestWhenInUseAuthorization() }
            else { refreshRegions(); requestFix() }
        } else { explicitFix = false; stopMonitoring(); store.stop() }
    }
    func requestBackgroundPermission() {
        guard !store.isDemo else { return }
        if authorization == .notDetermined { driver.requestWhenInUseAuthorization() }
        else if authorization == .authorizedWhenInUse { driver.requestAlwaysAuthorization() }
    }
    func locateOnce() {
        guard !store.isDemo else { return }; explicitFix = true
        if authorization == .notDetermined { driver.requestWhenInUseAuthorization() }
        else if authorized { requestFix() }
        else { statusMessage = "请在系统设置中允许此处访问位置。" }
    }
    func resumeForeground() {
        guard !store.isDemo else { return }
        authorization = driver.authorization; accuracyAuthorization = driver.accuracyAuthorization
        if let active = store.active, active.source == .automatic, let observed = active.lastObserved, Date.now.timeIntervalSince(observed) > 21600 {
            active.needsReview = true; store.commit()
        }
        refreshRegions(); if enabled { locateOnce() }
    }
    private func requestFix() { if authorized { driver.requestLocation() } }
    func refreshRegions() {
        guard !store.isDemo, enabled, authorized else { return }
        if authorization == .authorizedAlways, !monitoring { driver.startMonitoringSignificantLocationChanges(); driver.startMonitoringVisits(); monitoring = true }
        guard accuracyAuthorization == .fullAccuracy, driver.regionsAvailable else {
            driver.regions.forEach { driver.stopMonitoring(for: $0) }; monitoredPlaceCount = 0; return
        }
        let places = store.visiblePlaces.filter { !$0.isDiscovered }.sorted { a, b in
            guard let coordinate else { return a.createdAt < b.createdAt }
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return here.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude)) < here.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }
        let desired = places.prefix(20).map { place -> CLCircularRegion in
            let maximum = driver.maximumRegionMonitoringDistance
            let region = CLCircularRegion(center: place.coordinate, radius: maximum > 0 ? min(place.radius, maximum) : place.radius, identifier: place.id.uuidString)
            region.notifyOnEntry = true; region.notifyOnExit = true; return region
        }
        let wanted = Set(desired.map(\.identifier))
        for old in driver.regions where !wanted.contains(old.identifier) { driver.stopMonitoring(for: old) }
        for region in desired {
            if let old = driver.regions.first(where: { $0.identifier == region.identifier }) as? CLCircularRegion,
               old.center.latitude == region.center.latitude, old.center.longitude == region.center.longitude, old.radius == region.radius { continue }
            if let old = driver.regions.first(where: { $0.identifier == region.identifier }) { driver.stopMonitoring(for: old) }
            driver.startMonitoring(for: region)
        }
        monitoredPlaceCount = desired.count
    }
    private func stopMonitoring() {
        driver.regions.forEach { driver.stopMonitoring(for: $0) }
        driver.stopMonitoringSignificantLocationChanges(); driver.stopMonitoringVisits(); monitoring = false; monitoredPlaceCount = 0
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorizationChanged() }
    func authorizationChanged() {
        guard !store.isDemo else { return }; authorization = driver.authorization; accuracyAuthorization = driver.accuracyAuthorization
        if authorized {
            statusMessage = nil
            if authorization != .authorizedAlways, monitoring { driver.stopMonitoringVisits(); driver.stopMonitoringSignificantLocationChanges(); monitoring = false }
            if enabled { refreshRegions() }; requestFix()
        } else if authorization == .denied || authorization == .restricted {
            stopMonitoring()
            if let active = store.active, active.source == .automatic { active.needsReview = true; store.stop() }
            statusMessage = "定位权限不可用。仍可添加地点和手动补记。"
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for fix in locations.sorted(by: { $0.timestamp < $1.timestamp }) { handleFix(fix) }
    }
    func handleFix(_ fix: CLLocation, now: Date = .now) {
        guard !store.isDemo, fix.horizontalAccuracy >= 0, fix.timestamp <= now, now.timeIntervalSince(fix.timestamp) < 120 else { return }
        coordinate = fix.coordinate; lastFixAt = fix.timestamp; statusMessage = nil
        guard enabled, accuracyAuthorization == .fullAccuracy else { return }
        let activePlace = store.active?.kind == .stay ? store.place(store.active?.placeID) : nil
        let evidence = LocationResolver.resolve(fix, places: store.visiblePlaces, active: activePlace, explicit: explicitFix)
        explicitFix = false
        switch evidence {
        case .inside(let id):
            guard let place = store.place(id) else { return }
            store.arrive(place, at: max(trackingSince ?? fix.timestamp, fix.timestamp))
            if store.active?.placeID == id { store.active?.lastObserved = fix.timestamp; store.commit(); lastEventAt = now }
        case .outside(let id):
            if let active = store.active, let previous = active.lastObserved, now.timeIntervalSince(previous) > 1800 { active.needsReview = true }
            store.depart(id, at: max(store.active?.start ?? fix.timestamp, fix.timestamp)); lastEventAt = now
        case .uncertain:
            statusMessage = fix.horizontalAccuracy > 250 ? "位置误差较大，暂未切换地点。请检查精确位置或稍后定位。" : nil
        }
        refreshRegions()
    }
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) { driver.requestState(for: region) }
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state == .inside { handleRegion(region, entered: true) }
        else if state == .outside { handleRegion(region, entered: false) }
    }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { handleRegion(region, entered: true) }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) { handleRegion(region, entered: false) }
    func handleRegion(_ region: CLRegion, entered: Bool, at date: Date = .now) {
        guard enabled, authorized, accuracyAuthorization == .fullAccuracy, let id = UUID(uuidString: region.identifier), let place = store.place(id), !place.archived else { return }
        if entered {
            if let active = store.active, active.kind == .stay, active.placeID != id, let old = store.place(active.placeID) {
                let distance = CLLocation(latitude: old.latitude, longitude: old.longitude).distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
                if distance < old.radius + place.radius { requestFix(); return }
            }
            store.arrive(place, at: date); store.active?.lastObserved = date; store.commit()
        } else {
            if let active = store.active, active.source == .automatic, active.placeID == id, active.lastObserved == nil || date.timeIntervalSince(active.lastObserved!) > 1800 { active.needsReview = true }
            store.depart(id, at: date)
        }
        lastEventAt = date; requestFix()
    }
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        handleVisit(coordinate: visit.coordinate, accuracy: visit.horizontalAccuracy, arrival: visit.arrivalDate == .distantPast ? nil : visit.arrivalDate, departure: visit.departureDate == .distantFuture ? nil : visit.departureDate)
    }
    func handleVisit(coordinate: CLLocationCoordinate2D, accuracy: Double, arrival: Date?, departure: Date?, receivedAt: Date = .now) {
        guard enabled, authorization == .authorizedAlways, !store.isDemo, accuracy >= 0, accuracy <= 500, (-90...90).contains(coordinate.latitude), (-180...180).contains(coordinate.longitude) else { return }
        let since = trackingSince ?? .distantPast
        if let departure, departure < since { return }
        guard arrival != nil || departure != nil else { return }
        let start = arrival.map { max($0, since) }
        guard (start ?? .distantPast) <= receivedAt, (departure ?? receivedAt) <= receivedAt else { return }
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let match = store.visiblePlaces.filter { point.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= $0.radius }.sorted {
            if $0.isDiscovered != $1.isDiscovered { return !$0.isDiscovered }
            return point.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < point.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }.first
        let key = "visit/\(arrival?.timeIntervalSince1970 ?? -1)/\(departure?.timeIntervalSince1970 ?? -1)/\(String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude))"
        if store.observations.contains(where: { $0.key == key }) { return }
        guard start != nil || match != nil else { return }
        let place = match ?? Place(name: "未命名地点 \(store.places.filter(\.isDiscovered).count + 1)", kind: .other, latitude: coordinate.latitude, longitude: coordinate.longitude, radius: max(150, min(500, accuracy)))
        if match == nil { place.isDiscovered = true; store.context.insert(place) }
        store.reconcileVisit(place, arrival: start, departure: departure, key: key, receivedAt: receivedAt)
        lastEventAt = receivedAt; statusMessage = nil
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { statusMessage = "暂时无法获取位置，已有记录保留。可稍后定位或手动修正。" }
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) { statusMessage = "部分地点围栏未开启，访问地点记录仍会尝试补充。请检查定位权限。" }
}
