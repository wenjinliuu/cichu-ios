import CoreLocation

@MainActor protocol LocationDriving: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var authorization: CLAuthorizationStatus { get }
    var accuracyAuthorization: CLAccuracyAuthorization { get }
    var regions: Set<CLRegion> { get }
    var regionsAvailable: Bool { get }
    var maximumRegionMonitoringDistance: Double { get }
    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func requestLocation()
    func startMonitoring(for region: CLRegion)
    func stopMonitoring(for region: CLRegion)
    func requestState(for region: CLRegion)
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
    func startMonitoringVisits()
    func stopMonitoringVisits()
}
@MainActor final class CoreLocationDriver: LocationDriving {
    private let manager = CLLocationManager()
    init() { manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters; manager.distanceFilter = 100 }
    var delegate: CLLocationManagerDelegate? { get { manager.delegate } set { manager.delegate = newValue } }
    var authorization: CLAuthorizationStatus { manager.authorizationStatus }
    var accuracyAuthorization: CLAccuracyAuthorization { manager.accuracyAuthorization }
    var regions: Set<CLRegion> { manager.monitoredRegions }
    var regionsAvailable: Bool { CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) }
    var maximumRegionMonitoringDistance: Double { manager.maximumRegionMonitoringDistance }
    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestAlwaysAuthorization() { manager.requestAlwaysAuthorization() }
    func requestLocation() { manager.requestLocation() }
    func startMonitoring(for region: CLRegion) { manager.startMonitoring(for: region) }
    func stopMonitoring(for region: CLRegion) { manager.stopMonitoring(for: region) }
    func requestState(for region: CLRegion) { manager.requestState(for: region) }
    func startMonitoringSignificantLocationChanges() { if CLLocationManager.significantLocationChangeMonitoringAvailable() { manager.startMonitoringSignificantLocationChanges() } }
    func stopMonitoringSignificantLocationChanges() { manager.stopMonitoringSignificantLocationChanges() }
    func startMonitoringVisits() { manager.startMonitoringVisits() }
    func stopMonitoringVisits() { manager.stopMonitoringVisits() }
}
enum LocationEvidence: Equatable { case inside(UUID), outside(UUID), uncertain }
enum LocationResolver {
    static func resolve(_ fix: CLLocation, places: [Place], active: Place?, explicit: Bool) -> LocationEvidence {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 250 else { return .uncertain }
        func distance(_ place: Place) -> Double { fix.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) }
        if let active, !active.archived, distance(active) <= active.radius + min(fix.horizontalAccuracy, 50) { return .inside(active.id) }
        let candidates = places.filter {
            !$0.archived && fix.horizontalAccuracy <= max(100, $0.radius) && distance($0) + (explicit ? 0 : min(fix.horizontalAccuracy, 30)) <= $0.radius
        }.sorted { distance($0) < distance($1) }
        if let place = candidates.first { return .inside(place.id) }
        if let active, distance(active) - fix.horizontalAccuracy > active.radius + 50 { return .outside(active.id) }
        return .uncertain
    }
}
